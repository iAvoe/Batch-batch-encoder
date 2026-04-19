<#
.SYNOPSIS
    影片編碼工具調用管線生成器
.DESCRIPTION
    生成用於影片編碼的批處理文件，支持多種編碼工具鏈組合。繁體在地化由繁化姬實現：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.7
#>

# 下游工具（編碼器）必須支持 Y4M 管道，否則需要添加管道無法匹配的錯誤退出邏輯（由於所有工具支持因此未創建代碼）
# 選用 Y4M/RAW 由上游決定；one_line_shot_args（SVFI）近期已經實現 Y4M 管道支持；
# 如果有隻支持 RAW YUV 管道的上游工具，則強制覆蓋下游工具的管道輸入，並且利用 ffprobe 獲取的影片元數據/SEI 來指定解析度，幀率等資訊的純參數賦值
# 編碼工具線路表：
<#
────────────────────────────────────────────────────────────
ID     Preset                 Upstream     Downstream
────────────────────────────────────────────────────────────
[1 ]  ffmpeg_x264            ffmpeg       x264
[2 ]  ffmpeg_x265            ffmpeg       x265
[3 ]  ffmpeg_svtav1          ffmpeg       svtav1
[4 ]  vspipe_x264            vspipe       x264
[5 ]  vspipe_x265            vspipe       x265
[6 ]  vspipe_svtav1          vspipe       svtav1
[7 ]  avs2yuv_x264           avs2yuv      x264
[8 ]  avs2yuv_x265           avs2yuv      x265
[9 ]  avs2yuv_svtav1         avs2yuv      svtav1
[10]  avs2pipemod_x264       avs2pipemod  x264
[11]  avs2pipemod_x265       avs2pipemod  x265
[12]  avs2pipemod_svtav1     avs2pipemod  svtav1
[13]  svfi_x264              svfi         x264
[14]  svfi_x265              svfi         x265
[15]  svfi_svtav1            svfi         svtav1
────────────────────────────────────────────────────────────
#>

# 載入共用代碼
. "$PSScriptRoot\Common\Core.ps1"

$Script:DownstreamPipeParams = @{
    y4m = @{
        x264   = '--demuxer y4m'
        x265   = '--y4m'
        svtav1 = ''
    }
    raw = @{
        x264   = '--demuxer raw'
        x265   = ''
        svtav1 = ''
    }
}

# 腳本運行位置
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 可導入的工具
$upstreamTools = [ordered]@{
    'ffmpeg' = $null
    'vspipe' = $null
    'avs2yuv' = $null
    'avs2pipemod' = $null
    'svfi' = $null
}
$downstreamTools = [ordered]@{
    'x264' = $null
    'x265' = $null
    'svtav1' = $null
}
$analysisTools = [ordered]@{
    'ffprobe' = $null
}

<#
$toolHintsZHCN = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 发布版的路径是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安装版 VapourSynth 的默认可执行文件路径是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
#>
$toolHintsZHTW = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 發布版的路徑是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安裝版 VapourSynth 的默認可執行文件路徑是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
<#
$toolHintsEN = @{
    'svfi'    = " Steam SVFI installation (one_line_shot_args.exe) is at X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " Default install path for VapourSynth: C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " Both AviSynth (0.26) & AviSynth+ (0.30) are supported"
}
#>

#region Helpers
# 不同工具支持的管道格式
function Get-PipeType($upstream) {
    switch ($upstream) {
        'ffmpeg'       { 'y4m' }
        'vspipe'       { 'y4m' }
        'avs2pipemod'  { 'y4m' }
        'avs2yuv'      { 'y4m' } # 不是 RAW !
        'svfi'         { 'y4m' } # 不是 RAW !
        default        { 'raw' }
    }
}

# 不檢測 VapourSynth 版本和 API，直接嘗試運行命令，只要捕獲到特定返回結果就說明能跑
function Get-VSPipeY4MArgument {
    param([Parameter(Mandatory=$true)][string]$VSpipePath)
    $tests = @(
        @("-c", "y4m"),
        @("--container", "y4m"),
        @("--y4m")
    )

    foreach ($testArgs in $tests) {
        Write-Host (" 測試：{0} {1}" -f $VSpipePath, ($testArgs -join " "))
        
        # 使用 Start-Process 啟動獨立進程，避免影響當前控制台的字元集
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $VSpipePath
        $processInfo.Arguments = $testArgs -join " "
        $processInfo.RedirectStandardError = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        $vsResponse = $output + $errorOutput
        
        if ($vsResponse -match "No script file specified") {
            return @{
                Args = $testArgs -join " "
                Note = "vspipe 參數自動檢測成功：$($testArgs -join ' ')"
            }
        }
    }
    throw "檢測不到 vspipe 支持的 y4m 參數。VapourSynth 或 Python 環境異常，請檢查安裝"
}

# 遍歷所有已導入工具組合，從而導出“備用路線”
function Get-CommandFromPreset([string]$presetName, $tools, $vsAPI, [bool]$DebugMode = $false) {
    if ($DebugMode) {
        $debugInfo = [PSCustomObject]@{
            PresetName = $presetName
            Tools      = $tools
            vsAPI      = $vsAPI
        }
        Show-Debug "`r`nGet-CommandFromPreset" -ForegroundColor Yellow
        $debugInfo | ConvertTo-Json | Write-Host -ForegroundColor DarkGray
    }
    if (-not $presetName) {
        throw "Get-CommandFromPreset——未選擇任何編碼工具鏈"
    }
    $preset = $Global:PipePresets[$presetName]
    if (-not $preset) {
        throw "Get-CommandFromPreset——不存在的編碼工具鏈：$presetName"
    }

    $up    = $preset.Upstream
    $down  = $preset.Downstream
    $pType = Get-PipeType $up
    $pArg  = $Script:DownstreamPipeParams[$pType][$down]
    $template = switch ($up) {
        'ffmpeg'      { '"{0}" %ffmpeg_params% -f yuv4mpegpipe -an -strict unofficial - | "{1}" {3} %{2}_params%' }
        'vspipe'      { '"{0}" %vspipe_params% {3} - | "{1}" {4} %{2}_params%' }
        'avs2yuv'     { '"{0}" %avs2yuv_params% - | "{1}" {3} %{2}_params%' }
        'avs2pipemod' { '"{0}" %avs2pipemod_params% -y4mp | "{1}" {3} %{2}_params%' } # 不在 pipe 上游寫 -
        'svfi'        { '"{0}" %svfi_params% --pipe-out | "{1}" {3} %{2}_params%' } # 不在 pipe 上游寫 -
    }

    # 檢查管道格式
    if (-not $Script:DownstreamPipeParams.ContainsKey($pType)) {
        throw "Get-CommandFromPreset——未知 PipeType：$pType，請重試"
    }
    if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
        throw "Get-CommandFromPreset——下游編碼器 $down 不支持 $pType 管道"
    }
    if ($up -eq 'vspipe') {
        if (-not $vsAPI -or -not $vsAPI.Args) {
            throw "Get-CommandFromPreset：vspipe 參數檢測失敗，運行環境（Python）或已損壞，請先修好"
        }
        return $template -f $tools[$up], $tools[$down], $down, $vsAPI.Args, $pArg
    }
    else {
        return $template -f $tools[$up], $tools[$down], $down, $pArg
    }
}

# 通用路徑字串賦值函數
function Update-ToolMap {
    param ([System.Collections.IDictionary]$targetMap, $sourceObj)
    if (-not $sourceObj) { return }
    foreach ($prop in $sourceObj.psobject.Properties) {
        if ($prop.Value) {
            $targetMap[$prop.Name] = $prop.Value
        }
    }
}

# 通用工具路徑獲取函數
function Import-ToolPaths {
    param (
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$ToolsToHave, # 這不是 JSON 裡的項目，而是待導入的工具
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [hashtable]$toolTips,
        [scriptblock]$PostImportAction = { } # 給特定工具準備導入後邏輯（如版本檢測）
    )

    $i = 0
    $total = $ToolsToHave.Count
    foreach ($tool in $ToolsToHave.Keys) {
        $i++
        $savedPath = $ToolsToHave[$tool] # 運行此函數前，$upstreamTools 已被 Read-Json 更新
        $isSwapNeeded = $false

        # 1. 詢問是否需要導入/更換
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n 檢測到已保存的 $tool 路徑：$savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$total) 是否更換 $tool ？(y=換，Enter 不換)"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }
        else {
            Write-Host "`r`n 未保存 $tool 的路徑，需要手動導入" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$total) 導入 $tool 可執行文件？（y=是，Enter 跳過）"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }

        # 2. 執行導入邏輯
        if ($isSwapNeeded) {
            $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $ScriptDir
            if ($autoPath) {
                Write-Host "自動檢測到 $tool 位於：$autoPath" -ForegroundColor Green
                $useAuto = Read-Host "是否使用此文件？（Enter=確認, n=手動選擇）"
                if ('n' -eq $useAuto) {
                    $ToolsToHave[$tool] = Select-File -Title "選擇 $tool 可執行文件" -ExeOnly
                }
                else { $ToolsToHave[$tool] = $autoPath }
            }
            else {
                Write-Host " 未自動檢測到 $tool，請手動選擇"
                if ($toolHints.ContainsKey($tool)) {
                    Write-Host $toolHints[$tool] -ForegroundColor DarkGray
                }
                $ToolsToHave[$tool] = Select-File -Title "選擇 $tool 可執行文件" -ExeOnly
            }
        }

        # 3. 列印結果
        if ($ToolsToHave[$tool]) {
            Show-Success "$tool 已導入: $($ToolsToHave[$tool])"
            # 4. 執行特定工具的後續操作 (如 vspipe 版本檢測)
            $PostImportAction.Invoke($tool, $ToolsToHave[$tool])
        }
    }
}
#endregion

#region Main
function Main {
    $toolsJson = Join-Path $Global:TempFolder "tools.json"

    # vspipe API 版本與 AVS 版本
    $vspipeInfo = $null
    $isAvsPlus = $true # 老軟體，用戶幾乎不可能做更新，可直接保存
    
    Show-Border
    Write-Host "影片編碼工具調用管線生成器" -ForegroundColor Cyan
    Show-Border
    Write-Host ''
    Show-Info "使用說明："
    Write-Host "1. 後續的腳本將基於此‘管線批處理’（encode_template.bat）生成‘編碼批處理’"
    Write-Host "   因此無需每次編碼都要運行此步驟"
    Write-Host "2. 本工具會嘗試在腳本本地目錄，常見安裝目錄和環境變數中搜索工具，"
    Write-Host "   因此複製工具到此腳本目錄下即可減少手動操作複雜度"
    Write-Host ("─" * 50)

    # 選擇輸出路徑
    Show-Info "選擇批處理文件保存位置..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "選擇批處理文件保存位置"
        if (-not (Test-NullablePath $outputPath)) {
            if ('q' -eq (Read-Host "未選擇導出路徑，請重試輸入 'q' 強制退出")) {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_template.bat"
    Show-Success "輸出文件：$batchFullPath"
    Write-Host ("─" * 50)

    # 嘗試讀取保存的 tools.json，但可能已經過時，因此後續步驟仍需手動確認
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Info "檢測到路徑設定檔（$($savedConfig.SaveDate)），正在載入..."
            Update-ToolMap $upstreamTools   $savedConfig.Upstream
            Update-ToolMap $downstreamTools $savedConfig.Downstream
            Update-ToolMap $analysisTools   $savedConfig.Analysis
            # 用戶可能會使用安裝包升級或降級 VS（舊路徑新參數），每次調用都應該檢查，無法避免重複測試
        }
        catch { Show-Info "工具路徑設定檔損壞，需手動導入" }
    }

    Show-Info "開始導入上游編碼工具..."
    Import-ToolPaths -ToolsToHave $upstreamTools -CategoryName "上游" -ScriptDir $scriptDir -toolTips $toolHintsZHTW -PostImportAction {
        param($tool, $path)
        if ($tool -eq 'vspipe') {
            Write-Host ''
            Show-Info "檢測 VapourSynth 管道參數..."
            $global:vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $path
            Show-Success $global:vspipeInfo.Note
        }
        elseif ($tool -eq 'avs2yuv') {
            while ($true) { # 不導入 AviSynth 無法檢測其版本，需手動指定
                Show-Info "選擇使用的 avs2yuv(64).exe 類型："
                $avs2yuvVer = Read-Host " [默認 Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
                if ([string]::IsNullOrWhiteSpace($avs2yuvVer) -or 'a' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $true; break
                }
                elseif ('b' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $false; break
                }
                Show-Warning "輸入值超出理解，請重試"
            }
        }
    }

    Write-Host ("─" * 50)
    Show-Info "開始導入下游編碼工具..."
    Import-ToolPaths -ToolsToHave $downstreamTools -CategoryName "下游" -toolTips $toolHintsZHTW -ScriptDir $scriptDir

    Write-Host ("─" * 50)
    Show-Info "開始導入檢測工具..."
    Import-ToolPaths -ToolsToHave $analysisTools -CategoryName "檢測" -toolTips $toolHintsZHTW -ScriptDir $scriptDir

    # 合併工具（手動合併以避免 Clone() 帶來的對象引用/類型問題）
    $tools = @{}
    # 複製上游、下游及檢測工具
    foreach ($k in $upstreamTools.Keys) { $tools[$k] = $upstreamTools[$k] }
    foreach ($k in $downstreamTools.Keys) { $tools[$k] = $downstreamTools[$k] }
    foreach ($k in $analysisTools.Keys) { $tools[$k] = $analysisTools[$k] }

    <#
    Show-Debug "合併後的工具列表..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }
    #>

    # 檢查至少一組工具
    $hasUpstreamTool =
        @('ffmpeg', 'vspipe', 'avs2yuv', 'avs2pipemod', 'svfi') | Where-Object { 
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '') 
        }
    $hasDownstreamTool =
        @('x264', 'x265', 'svtav1') | Where-Object { 
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '') 
        }
    $hasAnalysisTool =
        @('ffprobe') | Where-Object {
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '')
        }

    if (($hasUpstreamTool.Count -eq 0) -or ($hasDownstreamTool.Count -eq 0)) {
        Show-Error "至少需要選擇一個上游工具和一個下游工具（如 ffmpeg + x265 或 ffmpeg + svtav1）"
        exit 1
    }
    if (!$hasAnalysisTool) {
        Show-Info "未導入檢測工具，將在運行後續步驟腳本時要求導入"
    }

    # 顯示可用工具鏈
    Write-Host ''
    Show-Info "可用編碼工具鏈："
    Write-Host ("─" * 50)

    # 構建“ID → PresetName”的映射表
    $presetIdMap = [ordered]@{}
    $availablePresets =
        $Global:PipePresets.GetEnumerator() |
        Where-Object {
            if ($null -eq $_.Value) { return $false } # 允許 Null
            $up = $_.Value.Upstream
            $down = $_.Value.Downstream
            $tools[$up] -and $tools[$down]
        } |
        Sort-Object { $_.Value.ID }
    
    Write-Host ("{0,-6} {1,-22} {2,-12} {3}" -f "ID", "Preset", "Upstream", "Downstream") -ForegroundColor Yellow
    Write-Host ("─" * 50)
    
    foreach ($ap in $availablePresets) {
        $id   = $ap.Value.ID
        $name = $ap.Key
        $up   = $ap.Value.Upstream
        $down = $ap.Value.Downstream

        # [ordered]@{} 創建 System.Collections.Specialized.OrderedDictionary 類
        # $presetIdMap[$id] = $value 且 $id 為整數時，會優先綁定到 Item[int index]
        # 導致 ID 值被篡改，變成空字典
        $presetIdMap["$id"] = $name # 強制使用字串鍵
        Write-Host ("[{0,-2}]  {1,-22} {2,-12} {3}" -f $id, $name, $up, $down)
    }
    
    Write-Host ("─" * 50)

    $selectedPreset = $null
    if ($presetIdMap.Count -eq 0) {
        Show-Error "沒有可用的完整工具鏈組合"
        exit 1
    }
    elseif ($presetIdMap.Count -eq 1) {
        # 只有一個工具鏈則直接選中
        $first = $presetIdMap.GetEnumerator() | Select-Object -First 1
        $selectedId = $first.Key
        $selectedPreset = $first.Value
        Show-Success "僅有一種工具鏈可用，已自動選擇: [$selectedId] $selectedPreset"
    }
    else { # 選擇工具鏈
        while ($true) {
            Write-Host ''
            $inputId = Read-Host "請輸入工具鏈編號正整數"

            if ($inputId -match '^\d+$' -and $presetIdMap.Contains($inputId)) {
                $selectedPreset = $presetIdMap[$inputId]
                Show-Success "已選擇工具鏈: [$inputId] $selectedPreset"
                break
            }
            Show-Error "無效編號，請輸入上面列表中的數字"
        }
    }
    
    # 生成批處理內容，追加管道指定命令
    # 1. 生成當前選定的主命令
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vsAPI $global:vspipeInfo

    # 2. 生成其它已導入線路的備用命令 (REM 寫入)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # 注意是調用 Key 屬性，因此嗎 = $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vsAPI $global:vspipeInfo
        $otherCommands += "REM PRESET[$presetName]: $cmdStr"
    }
    $remCommands = $otherCommands -join "`r`n"

    # 構建批處理文件（文件開頭需要雙換行）
    $batchContent = @'

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM 影片編碼工具調用管線
REM 生成時間: {0}
REM 工具鏈（變更時需指定）: {1}
REM ========================================

echo.
echo 開始編碼任務...
echo.

REM 參數範例（由後續腳本編輯）
REM set ffmpeg_params=-i input.mkv -an -f yuv4mpegpipe -strict unofficial
REM set x265_params=--y4m - -o output.hevc
REM set svtav1_params=-i - -b output.ivf

REM 指定本次所需編碼命令

{2}

REM ========================================
REM 備用編碼命令（手動切換，只導入一種編碼器則留空）
REM ========================================

{3}

echo.
echo 編碼完成！輸入 exit 退出...
echo.

timeout /t 1 /nobreak >nul
endlocal
cmd /k
'@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $selectedPreset, $command, $remCommands
    
    # 保存文件
    try {
        Confirm-FileDelete $batchFullPath
        Write-TextFile -Path $batchFullPath -Content $batchContent -UseBOM $true
        Show-Success "批處理文件已生成：$batchFullPath"
        
        # 驗證換行符
        Show-Debug "驗證批處理檔案格式..."
        if (-not (Test-TextFileFormat -Path $batchFullPath)) {
            return
        }
    
        # 顯示額外說明；x265 位於路線 2, 5, 8, 10, 14，SVT-AV1 位於路線 3, 6, 9, 12, 15
        $selectedDownstream = $Global:PipePresets[$selectedPreset].Downstream
        Write-Host ''
        if ($selectedDownstream -eq 'x265') {
            Show-Info "x265 編碼器默認輸出 .hevc 文件"
            Write-Host " 如需容器，請使用後續腳本或 ffmpeg 封裝"
        }
        # 用戶可能同時選擇 x265 和 SVT-AV1，勿用 elseif
        if ($selectedDownstream -eq 'svtav1') {
            Show-Info "建議自行編譯 SVT-AV1 編碼器（快很多）"
            Write-Host " 編譯教學：https://iavoe.github.io/av1-web-tutorial/HTML/index.html"

            Show-Info "AV1 編碼器默認輸出 .ivf 文件（Indeo）"
            Write-Host " 如需容器，請使用後續腳本或 ffmpeg 封裝"
        }
        Write-Host ("─" * 50)
    
    }
    catch {
        Show-Error ("保存文件失敗：" + $_)
        exit 1
    }

    # 保存工具配置到 JSON
    try {
        Confirm-FileDelete $toolsJson
        
        $configToSave = [ordered]@{
            Upstream   = $upstreamTools
            Downstream = $downstreamTools
            Analysis   = $analysisTools
            IsAvsPlus  = $isAvsPlus
            # VSPipeInfo = $vspipeInfo 用戶可能會升級或降級 VS，每次調用都應該檢查
            SaveDate   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        Write-JsonFile $toolsJson $configToSave
        Show-Success "工具配置已保存至: $toolsJson"
    }
    catch {
        Show-Warning ("保存路徑配置失敗: " + $_)
    }

    Write-Host ''
    Show-Success "腳本執行完成！"
    Read-Host "按 Enter 退出"
}
#endregion

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}