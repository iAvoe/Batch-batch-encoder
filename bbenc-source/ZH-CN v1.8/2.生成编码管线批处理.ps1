<#
.SYNOPSIS
    视频编码工具调用管线生成器
.DESCRIPTION
    生成用于视频编码的批处理文件，支持多种编码工具链组合。繁体本地化由繁化姬实现：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.8
#>

# 下游工具（编码器）必须支持 Y4M 管道，否则需要添加管道无法匹配的错误退出逻辑（由于所有工具支持因此未创建代码）
# 选用 Y4M/RAW 由上游决定；one_line_shot_args（SVFI）近期已经实现 Y4M 管道支持；
# 如果有只支持 RAW YUV 管道的上游工具，则强制覆盖下游工具的管道输入，并且利用 ffprobe 获取的视频元数据/SEI 来指定分辨率，帧率等信息的纯参数赋值
# 编码工具线路表：
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

# 加载共用代码
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

# 脚本运行位置
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 可导入的工具
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

$toolHintsZHCN = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 发布版的路径是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安装版 VapourSynth 的默认可执行文件路径是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
<#
$toolHintsZHTW = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 發布版的路徑是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安裝版 VapourSynth 的默認可執行文件路徑是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
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

# 不检测 VapourSynth 版本和 API，直接尝试运行命令，只要捕获到特定返回结果就说明能跑
function Get-VSPipeY4MArgument {
    param([Parameter(Mandatory=$true)][string]$VSpipePath)
    $tests = @(
        @("-c", "y4m"),
        @("--container", "y4m"),
        @("--y4m")
    )

    foreach ($testArgs in $tests) {
        Write-Host (" 测试：{0} {1}" -f $VSpipePath, ($testArgs -join " "))
        
        # 使用 Start-Process 启动独立进程，避免影响当前控制台的字符集
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
                Note = "vspipe 参数自动检测成功：$($testArgs -join ' ')"
            }
        }
    }
    throw "检测不到 vspipe 支持的 y4m 参数。VapourSynth 或 Python 环境异常，请检查安装"
}

# 遍历所有已导入工具组合，从而导出“备用路线”
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
        throw "Get-CommandFromPreset：未选择任何编码工具链"
    }
    $preset = $Global:PipePresets[$presetName]
    if (-not $preset) {
        throw "Get-CommandFromPreset——不存在的编码工具链：$presetName"
    }

    $up    = $preset.Upstream
    $down  = $preset.Downstream
    $pType = Get-PipeType $up
    $pArg  = $Script:DownstreamPipeParams[$pType][$down]
    $template = switch ($up) {
        'ffmpeg'      { '"{0}" %ffmpeg_params% -f yuv4mpegpipe -an -strict unofficial - | "{1}" {3} %{2}_params%' }
        'vspipe'      { '"{0}" %vspipe_params% {3} - | "{1}" {4} %{2}_params%' }
        'avs2yuv'     { '"{0}" %avs2yuv_params% - | "{1}" {3} %{2}_params%' }
        'avs2pipemod' { '"{0}" %avs2pipemod_params% -y4mp | "{1}" {3} %{2}_params%' } # 不在 pipe 上游写 -
        'svfi'        { '"{0}" %svfi_params% --pipe-out | "{1}" {3} %{2}_params%' } # 不在 pipe 上游写 -
    }

    # 检查管道格式
    if (-not $Script:DownstreamPipeParams.ContainsKey($pType)) {
        throw "Get-CommandFromPreset——未知 PipeType：$pType，请重试"
    }
    if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
        throw "Get-CommandFromPreset——下游编码器 $down 不支持 $pType 管道"
    }
    if ($up -eq 'vspipe') {
        if (-not $vsAPI -or -not $vsAPI.Args) {
            throw "Get-CommandFromPreset：vspipe 参数检测失败，运行环境（Python）或已损坏，请先修好"
        }
        return $template -f $tools[$up], $tools[$down], $down, $vsAPI.Args, $pArg
    }
    else {
        return $template -f $tools[$up], $tools[$down], $down, $pArg
    }
}

# 通用路径字符串赋值函数
function Update-ToolMap {
    param ([System.Collections.IDictionary]$targetMap, $sourceObj)
    if (-not $sourceObj) { return }
    foreach ($prop in $sourceObj.psobject.Properties) {
        if ($prop.Value) {
            $targetMap[$prop.Name] = $prop.Value
        }
    }
}

# 通用工具路径获取函数
function Import-ToolPaths {
    param (
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$ToolsToHave, # 这不是 JSON 里的项目，而是待导入的工具
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [hashtable]$toolTips,
        [scriptblock]$PostImportAction = { } # 给特定工具准备导入后逻辑（如版本检测）
    )

    $i = 0
    $total = $ToolsToHave.Count
    foreach ($tool in $ToolsToHave.Keys) {
        $i++
        $savedPath = $ToolsToHave[$tool] # 运行此函数前，$upstreamTools 已被 Read-Json 更新
        $isSwapNeeded = $false

        # 1. 询问是否需要导入/更换
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n 检测到已保存的 $tool 路径：$savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$total) 是否更换 $tool ？(y=换，Enter 不换)"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }
        else {
            Write-Host "`r`n 未保存 $tool 的路径，需要手动导入" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$total) 导入 $tool 可执行文件？（y=是，Enter 跳过）"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }

        # 2. 执行导入逻辑
        if ($isSwapNeeded) {
            $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $ScriptDir
            if ($autoPath) {
                Write-Host "自动检测到 $tool 位于：$autoPath" -ForegroundColor Green
                $useAuto = Read-Host "是否使用此文件？（Enter=确认, n=手动选择）"
                if ('n' -eq $useAuto) {
                    $ToolsToHave[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
                }
                else { $ToolsToHave[$tool] = $autoPath }
            }
            else {
                Write-Host " 未自动检测到 $tool，请手动选择"
                if ($toolHints.ContainsKey($tool)) {
                    Write-Host $toolHints[$tool] -ForegroundColor DarkGray
                }
                $ToolsToHave[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
            }
        }

        # 3. 打印结果
        if ($ToolsToHave[$tool]) {
            Show-Success "$tool 已导入: $($ToolsToHave[$tool])"
            # 4. 执行特定工具的后续操作 (如 vspipe 版本检测)
            $PostImportAction.Invoke($tool, $ToolsToHave[$tool])
        }
    }
}
#endregion

#region Main
function Main {
    $toolsJson = Join-Path $Global:TempFolder "tools.json"

    # vspipe API 版本与 AVS 版本
    $vspipeInfo = $null
    $isAvsPlus = $true # 老软件，用户几乎不可能做更新，因此可以直接保存版本

    Show-Border
    Write-Host "视频编码工具调用管线生成器" -ForegroundColor Cyan
    Show-Border
    Write-Host ''
    Show-Info "使用说明："
    Write-Host "1. 后续的脚本将基于此‘管线批处理’（encode_template.bat）生成‘编码批处理’"
    Write-Host "   因此无需每次编码都要运行此步骤"
    Write-Host "2. 本工具会尝试在脚本本地目录，常见安装目录和环境变量中搜索工具，"
    Write-Host "   因此复制工具到此脚本目录下即可减少手动操作复杂度"
    Write-Host ("─" * 50)

    # 选择输出路径
    Show-Info "选择批处理文件保存位置..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "选择批处理文件保存位置"
        if (-not (Test-NullablePath $outputPath)) {
            if ('q' -eq (Read-Host "未选择导出路径，请重试输入 'q' 强制退出")) {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_template.bat"
    Show-Success "输出文件：$batchFullPath"
    Write-Host ("─" * 50)
    
    # 尝试读取保存的 tools.json，但可能已经过时，因此后续步骤仍需手动确认
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Success "检测到配置文件（$($savedConfig.SaveDate)），正在加载..."
            Update-ToolMap $upstreamTools   $savedConfig.Upstream
            Update-ToolMap $downstreamTools $savedConfig.Downstream
            Update-ToolMap $analysisTools   $savedConfig.Analysis
            # 用户可能会使用安装包升级或降级 VS（旧路径新参数），每次调用都应该检查，无法避免重复测试
        }
        catch { Show-Info "工具路径配置文件损坏，需手动导入" }
    }

    Show-Info "开始导入上游编码工具..."
    Import-ToolPaths -ToolsToHave $upstreamTools -CategoryName "上游" -ScriptDir $scriptDir -toolTips $toolHintsZHCN -PostImportAction {
        param($tool, $path)
        # 无论是否更换 vspipe 都检测其 API 版本
        if ($tool -eq 'vspipe') {
            Write-Host ''
            Show-Info "检测 VapourSynth 管道参数..."
            $global:vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $path
            Show-Success $global:vspipeInfo.Note
        }
        elseif ($tool -eq 'avs2yuv') {
            while ($true) {
                Show-Info "选择使用的 avs2yuv(64).exe 类型："
                $avs2yuvVer = Read-Host " [默认 Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
                if ([string]::IsNullOrWhiteSpace($avs2yuvVer) -or 'a' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $true
                    break
                }
                elseif ('b' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $false
                    break
                }
                Show-Warning "输入值超出理解，请重试"
            }
        }
    }

    Write-Host ("─" * 50)
    Show-Info "开始导入下游编码工具..."
    Import-ToolPaths -ToolsToHave $downstreamTools -CategoryName "下游" -toolTips $toolHintsZHCN -ScriptDir $scriptDir

    Write-Host ("─" * 50)
    Show-Info "开始导入检测工具..."
    Import-ToolPaths -ToolsToHave $analysisTools -CategoryName "检测" -toolTips $toolHintsZHCN -ScriptDir $scriptDir

    # 合并工具（手动合并以避免 Clone() 带来的对象引用/类型问题）
    $tools = @{}
    # 复制上游、下游及检测工具
    foreach ($k in $upstreamTools.Keys) { $tools[$k] = $upstreamTools[$k] }
    foreach ($k in $downstreamTools.Keys) { $tools[$k] = $downstreamTools[$k] }
    foreach ($k in $analysisTools.Keys) { $tools[$k] = $analysisTools[$k] }

    <#
    Show-Debug "合并后的工具列表..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }
    #>

    # 检查至少一组工具
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
        Show-Error "至少需要选择一个上游工具和一个下游工具（如 ffmpeg + x265 或 ffmpeg + svtav1）"
        exit 1
    }
    if (!$hasAnalysisTool) {
        Show-Info "未导入检测工具，将在运行后续步骤脚本时要求导入"
    }

    # 显示可用工具链
    Write-Host ''
    Show-Info "可用编码工具链："
    Write-Host ("─" * 50)

    # 构建“ID → PresetName”的映射表
    $presetIdMap = [ordered]@{}
    $availablePresets =
        $Global:PipePresets.GetEnumerator() |
        Where-Object {
            if ($null -eq $_.Value) { return $false } # 允许 Null
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

        # [ordered]@{} 创建 System.Collections.Specialized.OrderedDictionary 类
        # $presetIdMap[$id] = $value 且 $id 为整数时，会优先绑定到 Item[int index]
        # 导致 ID 值被篡改，变成空字典
        $presetIdMap["$id"] = $name # 强制使用字符串键
        Write-Host ("[{0,-2}]  {1,-22} {2,-12} {3}" -f $id, $name, $up, $down)
    }
    
    Write-Host ("─" * 50)

    $selectedPreset = $null
    if ($presetIdMap.Count -eq 0) {
        Show-Error "没有可用的完整工具链组合"
        exit 1
    }
    elseif ($presetIdMap.Count -eq 1) {
        # 只有一个工具链则直接选中
        $first = $presetIdMap.GetEnumerator() | Select-Object -First 1
        $selectedId = $first.Key
        $selectedPreset = $first.Value
        Show-Success "仅有一种工具链可用，已自动选择: [$selectedId] $selectedPreset"
    }
    else { # 选择工具链
        while ($true) {
            Write-Host ''
            $inputId = Read-Host "请输入工具链编号正整数"

            if ($inputId -match '^\d+$' -and $presetIdMap.Contains($inputId)) {
                $selectedPreset = $presetIdMap[$inputId]
                Show-Success "已选择工具链: [$inputId] $selectedPreset"
                break
            }
            Show-Error "无效编号，请输入上面列表中的数字"
        }
    }
    
    # 生成批处理内容，追加管道指定命令
    # 1. 生成当前选定的主命令
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vsAPI $global:vspipeInfo

    # 2. 生成其它已导入线路的备用命令 (REM 写入)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # 注意是调用 Key 属性，因此不 = $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vsAPI $global:vspipeInfo
        $otherCommands += "REM PRESET[$presetName]: $cmdStr"
    }
    $remCommands = $otherCommands -join "`r`n"

    # 构建批处理文件（文件开头需要双换行）
    $batchContent = @'

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM 视频编码工具调用管线
REM 生成时间: {0}
REM 工具链（变更时需指定）: {1}
REM ========================================

echo.
echo 开始编码任务...
echo.

REM 参数示例（由后续脚本编辑）
REM set ffmpeg_params=-i input.mkv -an -f yuv4mpegpipe -strict unofficial
REM set x265_params=--y4m - -o output.hevc
REM set svtav1_params=-i - -b output.ivf

REM 指定本次所需编码命令

{2}

REM ========================================
REM 备用编码命令（手动切换，只导入一种编码器则留空）
REM ========================================

{3}

echo.
echo 编码完成！输入 exit 退出...
echo.

timeout /t 1 /nobreak >nul
endlocal
cmd /k
'@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $selectedPreset, $command, $remCommands
    
    # 保存文件
    try {
        Confirm-FileDelete $batchFullPath
        Write-TextFile -Path $batchFullPath -Content $batchContent -UseBOM $true
        Show-Success "批处理文件已生成：$batchFullPath"
        
        # 验证换行符
        Show-Debug "验证批处理文件格式..."
        if (-not (Test-TextFileFormat -Path $batchFullPath)) {
            return
        }
    
        # 显示额外说明；x265 位于路线 2, 5, 8, 10, 14，SVT-AV1 位于路线 3, 6, 9, 12, 15
        $selectedDownstream = $Global:PipePresets[$selectedPreset].Downstream
        Write-Host ''
        if ($selectedDownstream -eq 'x265') {
            Show-Info "x265 编码器默认输出 .hevc 文件"
            Write-Host " 如需容器，请使用后续脚本或 ffmpeg 封装"
        }
        # 用户可能同时选择 x265 和 SVT-AV1，勿用 elseif
        if ($selectedDownstream -eq 'svtav1') {
            Show-Info "建议自行编译 SVT-AV1 编码器（快很多）"
            Write-Host " 编译教程：https://iavoe.github.io/av1-web-tutorial/HTML/index.html"

            Show-Info "AV1 编码器默认输出 .ivf 文件（Indeo）"
            Write-Host " 如需容器，请使用后续脚本或 ffmpeg 封装"
        }
        Write-Host ("─" * 50)
    
    }
    catch {
        Show-Error ("保存文件失败：" + $_)
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
            # VSPipeInfo = $vspipeInfo 用户可能会升级或降级 VS，每次调用都应该检查
            SaveDate   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        Write-JsonFile $toolsJson $configToSave
        Show-Success "工具配置已保存至: $toolsJson"
    }
    catch {
        Show-Warning ("保存路径配置失败: " + $_)
    }

    Write-Host ''
    Show-Success "脚本执行完成！"
    Read-Host "按 Enter 退出"
}
#endregion

try { Main }
catch {
    Show-Error $_
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}