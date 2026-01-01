<#
.SYNOPSIS
    影片編碼工具調用管線生成器
.DESCRIPTION
    生成用於影片編碼的批處理文件，支持多種編碼工具鏈組合
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# 下游工具（編碼器）必須支持 Y4M 管道，否則需要添加強制覆蓋上遊程序的邏輯
# 選用 Y4M/RAW 由上游決定；one_line_shot_args（SVFI）只支持 RAW YUV 管道，強制覆蓋下游工具

# 載入共用代碼，工具鏈組合全局變數
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

# 編碼工具
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
    
    throw "檢測不到 vspipe 支持的 y4m 參數"
}

# 遍歷所有已導入工具組合，從而導出“備用路線”
function Get-CommandFromPreset([string]$presetName, $tools, $vspipeInfo) {
    $preset = $Global:PipePresets[$presetName]
    if (-not $preset) {
        throw "未知的 PipePreset：$presetName"
    }

    $up   = $preset.Upstream
    $down = $preset.Downstream
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
        throw "未知 PipeType：$pType"
    }
    if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
        throw "下游編碼器 $down 不支持 $pType 管道"
    }

    if ($up -eq 'vspipe') {
        return $template -f $tools[$up], $tools[$down], $down, $vspipeInfo.Args, $pArg
    }
    else {
        return $template -f $tools[$up], $tools[$down], $down, $pArg
    }
}

# 主程式
function Main {
    # 顯示標題
    Show-Border
    Write-Host "影片編碼工具調用管線生成器" -ForegroundColor Cyan
    Show-Border
    Write-Host ""
    
    # 顯示編碼範例
    Show-Info "常用編碼命令範例："
    Write-Host "ffmpeg -i [輸入] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    Write-Host "vspipe [腳本.vpy] --y4m - | x265.exe --y4m - -o"
    Write-Host "avs2pipemod [腳本.avs] -y4mp | x265.exe --y4m - -o"
    Write-Host ""
    
    # 選擇輸出路徑
    Show-Info "選擇批處理文件保存位置..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "選擇批處理文件保存位置"
        if (-not $outputPath -or -not (Test-Path $outputPath)) {
            if ((Read-Host "未選擇導出路徑，請重試。輸入 'q' 強制退出") -eq 'q') {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_single.bat"

    Show-Success "輸出文件：$batchFullPath"

    Show-Info "開始導入上游編碼工具..."
    Write-Host " 提示：Select-File 支持 -InitialDirectory 參數，在此腳本中添加即可最佳化導入操作步驟" -ForegroundColor DarkGray
    Write-Host " 如果難以實現腳本修好，你還可以創建文件夾捷徑"
    
    # 儲存 vspipe 版本與其 API 版本
    $vspipeInfo = $null

    # 上游工具
    $i=0
    foreach ($tool in @($upstreamTools.Keys)) {
        $i++
        $choice = Read-Host "`r`n [上游] ($i/$($upstreamTools.Count)) 導入 $tool？（y=是，Enter 跳過）"
        if ($choice -eq 'y') {
            $upstreamTools[$tool] =
                if ($tool -eq 'svfi') {
                    Show-Info "正在檢測 SVFI (one_line_shot_args.exe) 可能的路徑..."
                    $foundPath = Get-PSDrive -PSProvider FileSystem | ForEach-Object { 
                        $p = "$($_.Root)SteamLibrary\steamapps\common\SVFI"
                        if (Test-Path $p) { $p }
                    } | Select-Object -First 1

                    if ($foundPath) { # 嘗試自動定位到的 SVFI 路徑（Select-File 能自動回退到 Desktop）
                        Show-Success "已定位候選路徑：$foundPath"
                        Select-File -Title "選擇 one_line_shot_args.exe" -ExeOnly -InitialDirectory $foundPath
                    }
                    else { # DIY
                        Show-Info "SVFI（one_line_shot_args.exe）Steam 發布版的路徑是 X:\SteamLibrary\steamapps\common\SVFI\"
                        Select-File -Title "選擇 one_line_shot_args.exe" -ExeOnly
                    }
                }
                elseif ($tool -eq 'vspipe') {
                    Show-Info "正在檢測 vspipe.exe 可能的路徑..."
                    $foundPath = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                        $p = "$($_.Root)Program Files\VapourSynth\core"
                        if (Test-Path $p) { $p }
                    } | Select-Object -First 1

                    if ($foundPath) { # 嘗試自動定位到的 vspipe 路徑（Select-File 能自動回退到 Desktop）
                        Show-Success "已定位候選路徑：$foundPath"
                        Select-File -Title "選擇 vspipe.exe" -ExeOnly -InitialDirectory $foundPath
                    }
                    else { # DIY
                        Show-Info "安裝版 VapourSynth 的默認可執行文件路徑是 C:\Program Files\VapourSynth\core\vspipe.exe"
                        Select-File -Title "選擇 vspipe.exe" -ExeOnly
                    }
                }
                elseif ($tool -eq 'avs2yuv') {
                    Show-Info "此工具同時提供 AviSynth（0.26）和支持 AviSynth+（0.30）的 avs2yuv 支持"
                    Select-File -Title "選擇 avs2yuv.exe 或 avs2yuv64.exe" -ExeOnly
                }
                else {
                    Select-File -Title "選擇 $tool 可執行文件" -ExeOnly
                }

            Show-Success "$tool 已導入: $($upstreamTools[$tool])"
        }

        # 若是 vspipe，檢測 API 版本
        if ($tool -eq 'vspipe' -and $upstreamTools[$tool]) {
            Write-Host ""
            Show-Info "檢測 VapourSynth 管道參數..."
            $vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $upstreamTools[$tool]
            Show-Success $($vspipeInfo.Note)
        }
        # avs2yuv version check should be in step 4:
        # elseif ($tool -eq 'avs2yuv' -and $upstreamTools[$tool]) {}
    }
    
    Show-Info "開始導入下游編碼工具..."

    # 下游工具
    $i = 0
    foreach ($tool in @($downstreamTools.Keys)) {
        $i++
        $choice = Read-Host "`r`n [下游] ($i/$($downstreamTools.Count)) 導入 $tool？（y=是，Enter 跳過）"
        if ($choice -eq 'y') {
            $downstreamTools[$tool] = Select-File -Title "選擇 $tool 可執行文件" -ExeOnly
            Show-Success "$tool 已導入: $($downstreamTools[$tool])"
        }
    }

    # 合併工具（手動合併以避免 Clone() 帶來的對象引用/類型問題）
    $tools = @{}
    # 複製上游工具
    foreach ($k in $upstreamTools.Keys) {
        $tools[$k] = $upstreamTools[$k]
    }
    # 複製下游工具
    foreach ($k in $downstreamTools.Keys) {
        if ($k -eq 'svtav1') {
            Write-Host " 由於性能差距大且編譯好的 EXE 不易獲取，因此建議自行編譯 SVT-AV1 編碼器"
            Write-Host " 編譯教學可在 AV1 教學完整版（iavoe.github.io）或 SVT-AV1 教學急用版中查看"
        }
        $tools[$k] = $downstreamTools[$k]
    }

    Show-Debug "合併後的工具列表..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }

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

    if (($hasUpstreamTool.Count -eq 0) -or ($hasDownstreamTool.Count -eq 0)) {
        Show-Error "至少需要選擇一個上游工具和一個下游工具（例如 ffmpeg + x265 或 ffmpeg + svtav1）"
        exit 1
    }

    # 顯示可用工具鏈
    Show-Info "可用編碼工具鏈："
    Write-Host ("─" * 60)

    # 構建“ID → PresetName”的映射表
    $presetIdMap = @{}
    $availablePresets =
        $Global:PipePresets.GetEnumerator() |
        Where-Object {
            if ($null -eq $_.Value) { return $false }  # 允許 Null
            $up = $_.Value.Upstream
            $down = $_.Value.Downstream
            $tools[$up] -and $tools[$down]
        } |
        Sort-Object { $_.Value.ID }
    
    Write-Host ("{0,-6} {1,-22} {2,-12} {3}" -f "ID", "Preset", "Upstream", "Downstream") -ForegroundColor Yellow
    Write-Host ("─" * 60)
    
    foreach ($item in $availablePresets) {
        $id   = $item.Value.ID
        $name = $item.Key
        $up   = $item.Value.Upstream
        $down = $item.Value.Downstream

        $presetIdMap[$id] = $name

        Write-Host ("[{0,-2}]  {1,-22} {2,-12} {3}" -f $id, $name, $up, $down)
    }
    
    Write-Host ("─" * 60)

    if ($presetIdMap.Count -eq 0) {
        Show-Error "沒有可用的完整工具鏈組合"
        exit 1
    }
    
    # 選擇工具鏈
    do {
        Write-Host ""
        $inputId = Read-Host "請輸入工具鏈編號（數字）"

        if ($inputId -match '^\d+$' -and $presetIdMap.ContainsKey([int]$inputId)) {
            $selectedPreset = $presetIdMap[[int]$inputId]
            Show-Success "已選擇工具鏈: [$inputId] $selectedPreset"
            break
        }
        Show-Error "無效編號，請輸入上面列表中的數字"
    }
    while ($true)
    
    # 生成批處理內容，追加管道指定命令
    # 1. 生成當前選定的主命令
    # Show-Debug "S $selectedPreset"; Show-Debug "T $tools"; Show-Debug "V $vspipeInfo"
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vspipeInfo $vspipeInfo

    # 2. 生成其它已導入線路的備用命令 (REM 寫入)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # 注意是調用 Key 屬性，因此嗎 = $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vspipeInfo $vspipeInfo
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
REM 備用編碼命令（手動切換）
REM ========================================

{3}

echo.
echo 編碼完成！
echo.
pause

endlocal
echo 按任意鍵進入命令提示字元，輸入 exit 退出...
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
    
        # 顯示使用說明
        Write-Host ""
        Write-Host ("─" * 50)
        Show-Info "使用說明："
        Write-Host "1. 後續的腳本將基於此‘管線批處理’生成新的‘編碼批處理’，從而啟動編碼流程"
        Write-Host "   因此只要編碼工具不變就無需在每次使用都生成新的管線批處理"
        Write-Host "2. 建議在使用前二次確認所有工具路徑正確，尤其是長時間未使用後"
        Write-Host "3. 儘管可以透過編輯已生成的批處理來變更工具，但重新生成可以減少失誤機率"
        
        if ($downstream -eq 'x265') {
            Show-Warning "x265 編碼器默認輸出 .hevc 文件"
            Write-Host " 如需容器，請使用後續腳本或 ffmpeg 封裝"
        }

        if ($downstream -eq 'svtav1') {
            Show-Warning "AV1 編碼器默認輸出 .ivf 文件（Indeo 格式）"
            Write-Host " 如需容器，請使用後續腳本或 ffmpeg 封裝"
        }
        Write-Host ("─" * 50)
        
    }
    catch {
        Show-Error "保存文件失敗：$_"
        exit 1
    }
    
    Write-Host ""
    Show-Success "腳本執行完成！"
    Read-Host "按Enter 鍵退出"
}

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按Enter 鍵退出"
}