<#
.SYNOPSIS
    视频编码工具调用管线生成器
.DESCRIPTION
    生成用于视频编码的批处理文件，支持多种编码工具链组合
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# 下游工具（编码器）必须支持 Y4M 管道，否则需要添加强制覆盖上游程序的逻辑
# 选用 Y4M/RAW 由上游决定；one_line_shot_args（SVFI）只支持 RAW YUV 管道，强制覆盖下游工具

# 加载共用代码，工具链组合全局变量
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

# 编码工具
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
    
    throw "检测不到 vspipe 支持的 y4m 参数"
}

# 遍历所有已导入工具组合，从而导出“备用路线”
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
        'avs2pipemod' { '"{0}" %avs2pipemod_params% -y4mp | "{1}" {3} %{2}_params%' } # 不在 pipe 上游写 -
        'svfi'        { '"{0}" %svfi_params% --pipe-out | "{1}" {3} %{2}_params%' } # 不在 pipe 上游写 -
    }

    # 检查管道格式
    if (-not $Script:DownstreamPipeParams.ContainsKey($pType)) {
        throw "未知 PipeType：$pType"
    }
    if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
        throw "下游编码器 $down 不支持 $pType 管道"
    }

    if ($up -eq 'vspipe') {
        return $template -f $tools[$up], $tools[$down], $down, $vspipeInfo.Args, $pArg
    }
    else {
        return $template -f $tools[$up], $tools[$down], $down, $pArg
    }
}

# 主程序
function Main {
    # 显示标题
    Show-Border
    Write-Host "视频编码工具调用管线生成器" -ForegroundColor Cyan
    Show-Border
    Write-Host ""
    
    # 显示编码示例
    Show-Info "常用编码命令示例："
    Write-Host "ffmpeg -i [输入] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    Write-Host "vspipe [脚本.vpy] --y4m - | x265.exe --y4m - -o"
    Write-Host "avs2pipemod [脚本.avs] -y4mp | x265.exe --y4m - -o"
    Write-Host ""
    
    # 选择输出路径
    Show-Info "选择批处理文件保存位置..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "选择批处理文件保存位置"
        if (-not $outputPath -or -not (Test-Path $outputPath)) {
            if ((Read-Host "未选择导出路径，请重试。输入 'q' 强制退出") -eq 'q') {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_single.bat"

    Show-Success "输出文件：$batchFullPath"

    Show-Info "开始导入上游编码工具（由于使用了哈希表，导入顺序会被打乱）..."
    Write-Host " 提示：Select-File 支持 -InitialDirectory 参数，在此脚本中添加即可优化导入操作步骤" -ForegroundColor DarkGray
    Write-Host " 如果难以实现脚本修好，你还可以创建文件夹快捷方式"
    
    # 存储 vspipe 版本与其 API 版本
    $vspipeInfo = $null

    # 上游工具
    $i=0
    foreach ($tool in @($upstreamTools.Keys)) {
        $i++
        $choice = Read-Host " [上游] ($i/$($upstreamTools.Count)) 导入 $tool？（y=是，Enter 跳过）"
        if ($choice -eq 'y') {
            $upstreamTools[$tool] =
                if ($tool -eq 'svfi') {
                    Show-Info "SVFI 的可执行文件为 one_line_shot_args.exe，Steam 版的路径是 X:\SteamLibrary\steamapps\common\SVFI\"
                    Select-File -Title "选择 one_line_shot_args.exe" -ExeOnly
                }
                elseif ($tool -eq 'vspipe') {
                    Show-Info "安装版 VapourSynth 的默认可执行文件路径是 C:\Program Files\VapourSynth\core\vspipe.exe"
                    Select-File -Title "选择 vspipe.exe"
                }
                elseif ($tool -eq 'avs2yuv') {
                    Show-Info "此工具同时提供 AviSynth（0.26）和支持 AviSynth+（0.30）的 avs2yuv 支持"
                    Select-File -Title "选择 avs2yuv.exe 或 avs2yuv64.exe"
                }
                else {
                    Select-File -Title "选择 $tool 可执行文件" -ExeOnly
                }

            Show-Success "$tool 已导入: $($upstreamTools[$tool])"
        }

        # 若是 vspipe，检测 API 版本
        if ($tool -eq 'vspipe' -and $upstreamTools[$tool]) {
            Write-Host ""
            Show-Info "检测 VapourSynth 管道参数..."
            $vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $upstreamTools[$tool]
            Show-Success $($vspipeInfo.Note)
        }
        # avs2yuv version check should be in step 4:
        # elseif ($tool -eq 'avs2yuv' -and $upstreamTools[$tool]) {}
    }
    
    Show-Info "开始导入下游编码工具..."

    # 下游工具
    $i = 0
    foreach ($tool in @($downstreamTools.Keys)) {
        $i++
        $choice = Read-Host " [下游] ($i/$($downstreamTools.Count)) 导入 $tool？（y=是，Enter 跳过）"
        if ($choice -eq 'y') {
            $downstreamTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
            Show-Success "$tool 已导入: $($downstreamTools[$tool])"
        }
    }

    # 合并工具（手动合并以避免 Clone() 带来的对象引用/类型问题）
    $tools = @{}
    # 复制上游工具
    foreach ($k in $upstreamTools.Keys) {
        $tools[$k] = $upstreamTools[$k]
    }
    # 复制下游工具
    foreach ($k in $downstreamTools.Keys) {
        if ($k -eq 'svtav1') {
            Write-Host " 由于性能差距大且编译好的 EXE 不易获取，因此建议自行编译 SVT-AV1 编码器"
            Write-Host " 编译教程可在 AV1 教程完整版（iavoe.github.io）或 SVT-AV1 教程急用版中查看"
        }
        $tools[$k] = $downstreamTools[$k]
    }

    Show-Debug "合并后的工具列表..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }

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

    if (($hasUpstreamTool.Count -eq 0) -or ($hasDownstreamTool.Count -eq 0)) {
        Show-Error "至少需要选择一个上游工具和一个下游工具（例如 ffmpeg + x265 或 ffmpeg + svtav1）"
        exit 1
    }

    # 显示可用工具链
    Show-Info "可用编码工具链："
    Write-Host ("─" * 60)

    # 构建“ID → PresetName”的映射表
    $presetIdMap = @{}
    $availablePresets =
        $Global:PipePresets.GetEnumerator() |
        Where-Object {
            if ($null -eq $_.Value) { return $false }  # 允许 Null
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
        Show-Error "没有可用的完整工具链组合"
        exit 1
    }
    
    # 选择工具链
    do {
        Write-Host ""
        $inputId = Read-Host "请输入工具链编号（数字）"

        if ($inputId -match '^\d+$' -and $presetIdMap.ContainsKey([int]$inputId)) {
            $selectedPreset = $presetIdMap[[int]$inputId]
            Show-Success "已选择工具链: [$inputId] $selectedPreset"
            break
        }
        Show-Error "无效编号，请输入上面列表中的数字"
    }
    while ($true)
    
    # 生成批处理内容，追加管道指定命令
    # 1. 生成当前选定的主命令
    # Show-Debug "S $selectedPreset"; Show-Debug "T $tools"; Show-Debug "V $vspipeInfo"
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vspipeInfo $vspipeInfo

    # 2. 生成其它已导入线路的备用命令 (REM 写入)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # 注意是调用 Key 属性，因此不 = $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vspipeInfo $vspipeInfo
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
REM 备用编码命令（手动切换）
REM ========================================

{3}

echo.
echo 编码完成！
echo.
pause

endlocal
echo 按任意键进入命令提示符，输入 exit 退出...
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
    
        # 显示使用说明
        Write-Host ""
        Write-Host ("─" * 50)
        Show-Info "使用说明："
        Write-Host "1. 后续的脚本将基于此‘管线批处理’生成新的‘编码批处理’，从而启动编码流程"
        Write-Host "   因此只要编码工具不变就无需在每次使用都生成新的管线批处理"
        Write-Host "2. 建议在使用前二次确认所有工具路径正确，尤其是长时间未使用后"
        Write-Host "3. 尽管可以通过编辑已生成的批处理来变更工具，但重新生成可以减少失误概率"
        
        if ($downstream -eq 'x265') {
            Show-Warning "x265 编码器默认输出 .hevc 文件"
            Write-Host " 如需容器，请使用后续脚本或 ffmpeg 封装"
        }

        if ($downstream -eq 'svtav1') {
            Show-Warning "AV1 编码器默认输出 .ivf 文件（Indeo 格式）"
            Write-Host " 如需容器，请使用后续脚本或 ffmpeg 封装"
        }
        Write-Host ("─" * 50)
        
    }
    catch {
        Show-Error "保存文件失败：$_"
        exit 1
    }
    
    Write-Host ""
    Show-Success "脚本执行完成！"
    Read-Host "按回车键退出"
}

try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按回车键退出"
}