<#
.SYNOPSIS
    ffprobe 分析调用脚本，导出到 %USERPROFILE%\temp_v_info(_is_mov).csv
.DESCRIPTION
    分析源视频并导出 CSV: 总帧数，宽，高，色彩空间，传输特定等
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# .mov 格式支持 $ffprobeCSV.A-I + ...；其它格式支持 $ffprobeCSV.A-AA + ...
# 若同时检测到 temp_v_info_is_mov.csv 与 temp_v_info.csv，则使用其中创建日期最新的文件
# $ffprobeCSV.A：stream (or not stream)
# $ffprobeCSV.B：width
# $ffprobeCSV.C：height  
# $ffprobeCSV.D：pixel format (pix_fmt)
# $ffprobeCSV.E：color_space
# $ffprobeCSV.F：color_transfer
# $ffprobeCSV.G：color_primaries
# $ffprobeCSV.H：avg_frame_rate
# $ffprobeCSV.I：nb_frames (for MOV) or first frame count field (for others)
# $ffprobeCSV.AA：NUMBER_OF_FRAMES-eng (only for non-MOV files)
# $sourceCSV.SourcePath：视频源路径
# $sourceCSV.UpstreamCode：指定管道上游程序
# $sourceCSV.Avs2PipeModDLLPath：Avs2PipeMod 需要的 avisynth.dll
# $sourceCSV.SvfiConfigPath：one_line_shot_args（SVFI）的渲染配置 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini

# 加载共用代码，包括 $utf8NoBOM、Get-QuotedPath、Select-File、Select-Folder...
. "$PSScriptRoot\Common\Core.ps1"

# 同时生成占位 AVS/VS 脚本到 %USERPROFILE%，从而在用户暂无可用脚本的情况下顶替
function Get-BlankAVSVSScript {
    param([Parameter(Mandatory=$true)][string]$videoSource)

    # 尝试用共用函数拿到带引号的路径
    $quotedImport = Get-QuotedPath $videoSource

    # 空脚本与导出路径
    $AVSScriptPath = Join-Path $Global:TempFolder "blank_avs_script.avs"
    $VSScriptPath = Join-Path $Global:TempFolder "blank_vs_script.vpy"
    # 生成 AVS 内容（LWLibavVideoSource 需要双引号包裹路径）
    $blankAVSScript = "LWLibavVideoSource($quotedImport) # 自动生成的占位脚本，按需修改"
    # 生成 VapourSynth 内容（使用原始字符串 literal r"..." 以避免转义问题）
    # 如果 Get-QuotedPath 返回例如 "C:\path\file.mp4"，则 r$quotedImport 将成为 r"C:\path\file.mp4"
    $blankVSScript = @"
import vapoursynth as vs
core = vs.core
src = core.lsmas.LWLibavSource(source=r$quotedImport)
# 自动生成无滤镜脚本：按需在此处加入滤镜、裁切、帧率调整等
src.set_output()
"@

    try {
        Confirm-FileDelete $AVSScriptPath
        Confirm-FileDelete $VSScriptPath

        Show-Info "正在生成无滤镜脚本：`n $AVSScriptPath`n $VSScriptPath"
        Write-TextFile -Path $AVSScriptPath -Content $blankAVSScript -UseBOM $false
        Write-TextFile -Path $VSScriptPath -Content $blankVSScript -UseBOM $false
        Show-Success "已生成无滤镜脚本到用户目录。"

        # 验证换行符
        Show-Debug "验证脚本文件格式..."
        if (-not (Test-TextFileFormat -Path $AVSScriptPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $VSScriptPath)) {
            return
        }

        # 调用方根据上游类型选择使用哪个脚本
        return @{
            AVS = $AVSScriptPath
            VPY = $VSScriptPath
        }
    }
    catch {
        Show-Error "生成无滤镜脚本失败：$_"
        return $null
    }
}

# 主程序
function Main {
    Show-Border
    Write-Host ("ffprobe 源读取工具，导出 " + $Global:TempFolder + "temp_v_info(_is_mov).csv 供后续步骤调用") -ForegroundColor Cyan
    Show-Border
    Write-Host ""

    # 显示编码示例
    # Show-Info "常用编码命令示例："
    # Write-Host "ffmpeg -i [输入] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    # Write-Host "vspipe [脚本.vpy] --y4m - | x265.exe --y4m - -o"
    # Write-Host "avs2pipemod [脚本.avs] -y4mp | x265.exe --y4m - -o"
    # Write-Host ""

    # 根据管道上游程序选择源类型
    $sourceTypes = @{
        'A' = @{ Name = 'ffmpeg'; Ext = ''; Message = "任意源" }
        'B' = @{ Name = 'vspipe'; Ext = '.vpy'; Message = ".vpy 源" }
        'C' = @{ Name = 'avs2yuv'; Ext = '.avs'; Message = ".avs 源" }
        'D' = @{ Name = 'avs2pipemod'; Ext = '.avs'; Message = ".avs 源" }
        'E' = @{ Name = 'SVFI'; Ext = ''; Message = "视频源" }
    }

    # 获取源文件类型
    $selectedType = $null
    do {
        Show-Info "选择要启用的管道上游程序（确认源符合程序要求）："
        $sourceTypes.GetEnumerator() | Sort-Object Key | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value.Name)"
        }
        $choice = (Read-Host " 请输入选项").ToUpper()

        if ($sourceTypes.ContainsKey($choice)) {
            $selectedType = $sourceTypes[$choice]
            Show-Info $selectedType.Message
            break
        }
    }
    while ($true)
    
    # 获取上游程序代号（写入 CSV）；为 Avs2PipeMod 导入必须的 DLL
    $upstreamCode = $null
    $Avs2PipeModDLL = $null
    $OneLineShotArgsINI = $null
    $isScriptUpstream =
        $selectedType.Name -in @('vspipe', 'avs2yuv', 'avs2pipemod')

    switch ($selectedType.Name) {
        'ffmpeg'       { $upstreamCode = 'a' }
        'vspipe'       { $upstreamCode = 'b' }
        'avs2yuv'      { $upstreamCode = 'c' }
        'avs2pipemod'  {
            $upstreamCode = 'd'
            Show-Info "请指定 avisynth.dll 的路径..."

            do {
                $Avs2PipeModDLL = Select-File -Title "选择 avisynth.dll" -InitialDirectory ([Environment]::GetFolderPath('System')) -DllOnly
                if (-not $Avs2PipeModDLL) {
                    $placeholderScript = Read-Host "未选择 DLL。按 Enter 重试，输入 'q' 强制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $Avs2PipeModDLL)

            Show-Success "已记录 avisynth.dll 路径: $Avs2PipeModDLL"
        }
        'SVFI'         {
            $upstreamCode = 'e'
            Show-Info "请指定 SVFI 渲染配置 INI 文件的路径，`r`n      如 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"

            do {
                $OneLineShotArgsINI = Select-File -Title "选择 SVFI 渲染配置文件 (.ini)" -IniOnly
                if (-not $OneLineShotArgsINI) {
                    $placeholderScript = Read-Host "未选择 INI。按 Enter 重试，输入 'q' 强制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $OneLineShotArgsINI)
        }
        default        { $upstreamCode = 'a' }
    }

    # 定义变量
    $videoSource = $null # ffprobe 将分析这个视频文件
    $scriptSource = $null # 脚本文件路径，如果有则在导出的 CSV 中覆盖视频源
    $encodeImportSourcePath = $null

    # 如果上游是 vspipe / avs2yuv / avs2pipemod，提供生成无滤镜脚本选项
    if ($isScriptUpstream) {
        do {
            # 首先选择视频源文件（用于ffprobe分析）
            Show-Info "选择（脚本引用的）视频源文件（ffprobe 将分析此文件）"
            while ($null -eq $videoSource) {
                $videoSource = Select-File -Title "选择视频源文件（例如 .mp4/.mkv/.mov）"
                if ($null -eq $videoSource) { Show-Error "未选择视频文件" }
            }
        
            # 询问用户是否要生成无滤镜脚本
            $mode = Read-Host "输入 'y' 导入自定义脚本，输入 'n' 或 Enter 为视频源生成无滤镜脚本"
        
            if ($mode -eq 'y') { # 导入自定义脚本
                do {
                    $scriptSource = Select-File -Title "定位脚本文件（.avs/.vpy...）"
                    if (-not $scriptSource) {
                        Show-Error "未选择文件"
                        continue
                    }
                
                    # 验证文件扩展名
                    $ext = [IO.Path]::GetExtension($scriptSource).ToLower()
                    if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod') -and $ext -ne '.avs') {
                        Show-Error "对于 $($selectedType.Name)，需要 .avs 脚本文件"
                        $scriptSource = $null
                    }
                    elseif ($selectedType.Name -eq 'vspipe' -and $ext -ne '.vpy') {
                        Show-Error "对于 vspipe，需要 .vpy 脚本文件"
                        $scriptSource = $null
                    }
                }
                while (-not $scriptSource)
            
                Show-Success "已选择脚本文件: $scriptSource"
                # 注意：视频源 $videoSource 仍然用于 ffprobe
            }
            elseif ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'n') { # 生成无滤镜脚本
                $placeholderScript = Get-BlankAVSVSScript -videoSource $videoSource
                if (-not $placeholderScript) { 
                    Show-Error "生成无滤镜脚本失败，请重试"
                    continue
                }
            
                # 根据上游类型选择正确的脚本路径
                if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod')) {
                    $scriptSource = $placeholderScript.AVS
                }
                else { # vspipe
                    $scriptSource = $placeholderScript.VPY
                }
                
                Show-Success "已生成无滤镜脚本: $scriptSource"
            }
            else {
                Show-Warning "无效输入"
                continue
            }
            break
        }
        while ($true)

        $encodeImportSourcePath = $scriptSource
    }
    else { # ffmpeg、SVFI：视频源
        do {
            Show-Info "选择要分析的视频源文件"
            $videoSource = Select-File -Title "定位视频文件，如视频（.mp4/.mov/...）、RAW（.yuv/.y4m/...）"
            if (-not $videoSource) { 
                Show-Error "未选择文件" 
                continue
            }
            
            Show-Success "已选择视频源文件: $videoSource"
            break
        }
        while ($true)

        $encodeImportSourcePath = $videoSource
    }

    # 检测封装文件类型
    $isMOV = ([IO.Path]::GetExtension($videoSource).ToLower() -eq '.mov')

    # 报告封装文件类型
    if ($isMOV) {
        Show-Info "导入视频 $videoSource 的封装格式为 MOV"
    }
    else {
        Show-Info "导入视频 $videoSource 的封装格式非 MOV"
    }

    # 根据封装文件类型选用 ffprobe 命令、定义文件名
    $ffprobeArgs =
        if ($isMOV) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries', '-of', 'csv'
        )}
        else {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
            '-of', 'csv'
        )}
    # $ffprobeArgsDebug =
    #    if ($isMOV) {@(
    #        '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
    #        'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries', '-of', 'ini'
    #    )}
    #    else {@(
    #        '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
    #        'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
    #        '-of', 'ini'
    #    )}
    
    # 由于 ffprobe 读取不同源所产生的列数不一，导致读取额外插入的信息随机错位，因此需要独立的 CSV（s_info）来储存源信息
    $sourceCSVExportPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    $ffprobeCSVExportPath =
        if ($isMOV) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv"
        }
        else {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv"
        }
    # $ffprobeCSVExportPathDebug =
    #     if ($isMOV) {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov_debug.csv"
    #     }
    #     else {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_debug.csv"
    #     }

    # 若 CSV 已存在，要求手动确认后清理，避免覆盖
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv")
    Confirm-FileDelete $sourceCSVExportPath

    # 定位 ffprobe 程序
    Show-Info "定位 ffprobe.exe..."
    do {
        $ffprobePath =
            Select-File -Title "定位 ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
        if (-not (Test-Path -LiteralPath $ffprobePath)) {
            Show-Warning "找不到 ffprobe 可执行文件，请重试：$ffprobePath"
        }
    }
    while (-not (Test-Path -LiteralPath $ffprobePath))

    # 执行 ffprobe 并插入视频源路径
    try {
        $ffprobeOutputCSV = (& $ffprobePath @ffprobeArgs).Trim()
        # $ffprobeOutputCSVDebug = (& $ffprobePath @ffprobeArgsDebug).Trim()

        # 构建源 CSV 行
        $sourceInfoCSV = @"
"$encodeImportSourcePath",$upstreamCode,"$Avs2PipeModDLL","$OneLineShotArgsINI"
"@
        
        Write-TextFile -Path $ffprobeCSVExportPath -Content $ffprobeOutputCSV -UseBOM $true
        # [System.IO.File]::WriteAllLines($ffprobeCSVExportPathDebug, $ffprobeOutputCSVDebug)

        Write-TextFile -Path $sourceCSVExportPath -Content $sourceInfoCSV -UseBOM $true
        Show-Success "CSV 文件已生成：$ffprobeCSVExportPath`n$sourceCSVExportPath"

        # 验证换行符
        Show-Debug "验证 CSV 文件格式..."
        if (-not (Test-TextFileFormat -Path $ffprobeCSVExportPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $sourceCSVExportPath)) {
            return
        }
    }
    catch { throw "ffprobe 执行失败：$_" }

    Write-Host ""
    Show-Success "脚本执行完成！"
    Read-Host "按回车键退出"
}

# 异常处理
try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按回车键退出"
}