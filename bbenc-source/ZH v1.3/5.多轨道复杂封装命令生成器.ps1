<#
.SYNOPSIS
    基于 ffmpeg、ffprobe 的多轨道复杂封装命令生成器
.DESCRIPTION
    封装对过视音频、字幕字体批处理的工具，运行批处理即可完成封装操作
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# 加载共用代码，工具链组合全局变量
. "$PSScriptRoot\Common\Core.ps1"

# 调用 ffprobe 获取指定流的信息，直接返回对象，不写临时文件
function Get-StreamMetadata {

    param (
        [string]$FFprobePath,
        [string]$FilePath,
        [string]$StreamType # v, a, s, t
    )

    if (-not (Test-Path $FilePath)) { return $null }

    # 构造参数：输出 CSV 格式，无 Header
    # 对应原脚本逻辑：stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags=
    # 注意：ffprobe CSV 输出顺序严格对应 show_entries 的顺序
    $argsList = @(
        "-i", $FilePath,
        "-select_streams", $StreamType,
        "-v", "error",
        "-hide_banner",
        "-show_entries", "stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags=",
        "-of", "csv=p=0" 
    )

    try {
        # 直接执行并捕获输出（消除 Invoke-Expression 和 临时文件）
        $csvOutput = & $FFprobePath $argsList
        
        if ([string]::IsNullOrWhiteSpace($csvOutput)) { return $null }

        # 解析 CSV。原脚本 Header 为 A,B,C,D
        # A=stream(固定), B=codec_name, C=codec_tag_string, D=avg_frame_rate
        $data = $csvOutput | ConvertFrom-Csv -Header "Type", "CodecName", "CodecTag", "FrameRate"
        return $data
    }
    catch {
        Show-Error "FFprobe 执行失败: $_"
        return $null
    }
}

# 分析文件类型和流，生成 ffmpeg 参数
function Get-StreamArgs {
    param (
        [string]$FFprobePath,
        [string]$FilePath,
        [int]$MapIndex,
        [bool]$IsFirstVideo
    )

    $ext = [IO.Path]::GetExtension($FilePath).ToLower()
    $argsResult = @()
    $hasVideo = $false

    # 场景定义
    # 场景甲：容器格式 (含视频)
    $isContainerVideo = $ext -match "\.(mkv|mp4|mov|f4v|flv|avi|m3u|mxv)$"
    # 场景乙：容器格式 (纯音轨、字幕)
    $isContainerAudio = $ext -match "\.(m4a|mka|mks)$"
    
    Show-Debug "正在分析文件: $FilePath (类型: $ext)"

    if ($isContainerVideo) {
        # 甲
        Show-Info "识别为视频封装容器，将生成视频流、音轨、字幕轨与字体添加命令..."
        
        # 1. 视频流
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        if ($vData) {
            $codec = if ($vData.CodecTag -and $vData.CodecTag -ne "0" -and $vData.CodecTag -ne "") { $vData.CodecTag } else { $vData.CodecName }
            
            if ($codec -match "(hevc|h265|avc|h264|cfhd|ap4x|apcn|hev1|vp09|vp9)") {
                Show-Success "发现视频流: $codec"
                if ($codec -match "ap4x|apcn") { Show-Warning "ProRes 视频流仅 MOV/MXF 支持" }
                if ($codec -match "vp9|vp09") { Show-Warning "VP9 视频流建议使用 MKV/WebM" }
            } else {
                Show-Warning "未知或潜在不兼容视频流: $codec"
            }

            if ($IsFirstVideo) {
                $fr = $vData.FrameRate
                $argsResult += "-r $fr -c:v copy"
                $hasVideo = $true
            } else {
                Show-Warning "检测到多余视频流，已跳过 (仅保留第一个导入的视频)"
            }
        }

        # 2. 音频流
        $aData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a"
        if ($aData) {
            $codec = if ($aData.CodecTag -and $aData.CodecTag -ne "0" -and $aData.CodecTag -ne "") { $aData.CodecTag } else { $aData.CodecName }
            if ($codec) {
                Show-Success "发现音频流: $codec"
                if ($codec -match "ape") { Show-Error "无封装格式支持 APE 音频"; exit 1 }
                $argsResult += "-c:a copy"
            }
        }

        # 3. 字幕流
        $sData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s"
        if ($sData) {
            Show-Success "发现字幕流: $($sData.CodecName)"
            $argsResult += "-c:s copy"
        }

        # 4. 字体流
        $tData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "t"
        if ($tData) {
            Show-Success "发现字体附件"
            $argsResult += "-c:t copy"
        }

    }
    elseif ($isContainerAudio) {
        # 乙
        Show-Info "识别为音频/字幕容器，将生成音轨、字幕轨与字体添加命令..."
        
        # 音频
        $aData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a"
        if ($aData) {
             $codec = if ($aData.CodecTag -and $aData.CodecTag -ne "0" -and $aData.CodecTag -ne "") { $aData.CodecTag } else { $aData.CodecName }
             Show-Success "发现音频流: $codec"
             $argsResult += "-c:a copy"
        }
        
        # 字幕 & 字体
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") { $argsResult += "-c:s copy" }
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "t") { $argsResult += "-c:t copy" }

    }
    else {
        # 丙
        Show-Info "识别为单文件流，将调用 ffprobe 进行额外分析..."

        # 尝试检测视频
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"

        # 非视频：尝试检测音频
        $aData = if (-not $vData) { Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a" } else { $null }
        
        if ($vData) {
            # 视频单流处理
            $codec = $vData.CodecName
            Show-Success "视频流: $codec"
            if ($IsFirstVideo) {
                $fr = $vData.FrameRate
                $argsResult += "-r $fr -c:v copy"
                $hasVideo = $true
            }
        }
        elseif ($aData) {
            # 音频单流处理
            $codec = $aData.CodecName
            Show-Success "音频流: $codec"
            $argsResult += "-c:a copy"
        }
        elseif ($ext -match "\.(srt|ass|ssa)$") {
            # 字幕文件
            Show-Success "字幕文件: $ext"
            $argsResult += "-c:s copy"
        }
        elseif ($ext -match "\.(ttf|ttc|otf)$") {
            # 字体文件
            Show-Success "字体文件: $ext"
            $argsResult += "-c:t copy"
        }
        else {
            Show-Error "无法识别的文件流类型: $ext"
            return $null
        }
    }

    if ($argsResult.Count -eq 0) {
        Show-Error "该文件没有产生任何有效的封装参数: $FilePath"
        return $null
    }

    # 返回对象
    return [PSCustomObject]@{
        ArgumentsString = $argsResult -join " "
        ContainsVideo   = $hasVideo
    }
}

function Main {
    # 标题与说明
    Show-Border
    Show-Info "基于 ffmpeg 的多轨道复杂封装命令生成器 v2.0"
    Write-Host " 提示：导出所有内容命令参考：" -ForegroundColor Gray
    Write-Host " ffmpeg -dump_attachment:t `"out.ttf`" -i input.mkv" -ForegroundColor Gray
    Show-Border
    Write-Host ""

    # 初始化路径
    Show-Info "步骤 1/4: 选择工作路径"
    Show-Info "选择导出封装批处理路径..."
    $exptPath = Select-Folder -Description "选择导出封装批处理的文件夹"
    Show-Info "选择封装结果路径..."
    $muxPath  = Select-Folder -Description "选择封装结果的文件夹"
    
    Show-Info "步骤 2/4: 定位工具"
    Show-Info "选择 ffprobe.exe"
    $fprbPath = Select-File -Title "选择 ffprobe.exe" -ExeOnly
    
    # 循环导入文件
    Show-Info "步骤 3/4: 导入素材 (循环)"
    
    $inputsAgg = ""   # 所有的 -i "path"
    $mapsAgg   = ""   # 所有的 -map xArgs
    $mapIndex  = 0
    $needVideo = $true # 是否需要寻找主视频轨道
    $loop      = $true

    while ($loop) {
        $strmPath = Select-File -Title "选择要封装的源文件 (第 $($mapIndex+1) 个)"
        
        # 调用核心分析函数
        $result =
            Get-StreamArgs -FFprobePath $fprbPath -FilePath $strmPath -MapIndex $mapIndex -IsFirstVideo $needVideo
        
        if ($result) {
            # 累加 -i 参数
            $inputsAgg += " -i `"$strmPath`""
            
            # 累加 -map 参数 (注意 ffmpeg 语法: -map 0:v -c:v copy ...)
            # 原脚本逻辑简单地将生成的 args 附加在 map index 后面
            # 实际上更严谨的写法应该是 -map $i $args，但在 copy 模式下原逻辑是成立的
            $mapsAgg += " -map $mapIndex $($result.ArgumentsString)"
            
            Show-Info "已添加: $($result.ArgumentsString)"

            # 如果已经添加了主视频，后续不再添加 -c:v copy
            if ($result.ContainsVideo) {
                $needVideo = $false
            }
            
            $mapIndex++
        }

        # 询问是否继续
        $choice = Read-Host "`r`n是否继续导入更多文件? (y/n)"
        if ($choice -ne "y") { $loop = $false }
    }

    # 3. 输出重置

    Show-Info "步骤 4/4: 配置输出"

    # 3-1. 确定文件名
    $defaultName = [IO.Path]::GetFileNameWithoutExtension($strmPath) + "_mux"
    $outName = Read-Host "请输入输出文件名 (留空默认: $defaultName)"
    if ([string]::IsNullOrWhiteSpace($outName)) { $outName = $defaultName }
    
    # 3-2. 简单校验文件名
    if (-not (Test-FilenameValid $outName)) {
        Show-Warning "文件名包含非法字符，已自动修正"
        $invalid = [IO.Path]::GetInvalidFileNameChars()
        foreach ($c in $invalid) { $outName = $outName.Replace($c, '_') }
    }

    # 3-3. 选择封装容器 & ffmpeg 路径
    Write-Host "`r`n选择封装容器:"
    Write-Host " [A] MP4 (适合通用)"
    Write-Host " [B] MOV (适合编辑)"
    Write-Host " [C] MKV (万能，支持封装字体/ASS)"
    Write-Host " [D] MXF (专业)"
    
    $containerExt = ""
    do {
        switch (Read-Host "请输入选项 (A/B/C/D)") {
            'a' { $containerExt = ".mp4" }
            'b' { $containerExt = ".mov" }
            'c' { $containerExt = ".mkv" }
            'd' { $containerExt = ".mxf" }
            default { Write-Warning "无效选项" }
        }
    }
    while ($containerExt -eq "")

    $fmpgPath =
        Select-File -Title "请选择 ffmpeg.exe" -ExeOnly -InitialDirectory ([IO.Path]::GetDirectoryName($fprbPath))

    # 3-4. 生成命令与后期检查
    
    # 组合最终命令
    # 结构: ffmpeg.exe inputs maps output
    $finalOutput = Join-Path $muxPath ($outName + $containerExt)
    $cmdLine = "& `"$fmpgPath`" $inputsAgg $mapsAgg `"$finalOutput`""

    # 兼容性检查与自动修复
    if ($containerExt -in ".mp4", ".mov", ".mxf") {
        if ($cmdLine -match "-c:t copy") {
            Show-Warning "检测到字体流 (-c:t copy)，但 MP4/MOV/MXF 不支持。"
            $fix = Read-Host "输入 'd' 删除字体流，输入 'm' 强制改为 MKV，其他键忽略"
            if ($fix -eq 'd') { $cmdLine = $cmdLine.Replace("-c:t copy", "") }
            elseif ($fix -eq 'm') { 
                $containerExt = ".mkv"
                $cmdLine = $cmdLine.Replace(".mp4", ".mkv").Replace(".mov", ".mkv").Replace(".mxf", ".mkv")
                Show-Success "已切换为 MKV"
            }
        }
    }

    if ($containerExt -in ".mp4", ".mov") {
        if ($cmdLine -match "-c:s copy") {
            Show-Warning "检测到字幕流 (-c:s copy)，MP4/MOV 对多轨/ASS支持不佳。"
            $fix = Read-Host "输入 'd' 删除，'t' 转为 mov_text (仅第一轨)，其他键忽略"
            if ($fix -eq 'd') { $cmdLine = $cmdLine.Replace("-c:s copy", "") }
            elseif ($fix -eq 't') { $cmdLine = $cmdLine.Replace("-c:s copy", "-c:s:0 mov_text") }
        }
    }

    # 5. 写入文件
    
    # 生成文件名
    $batFilename = "Generate_Mux_Command.bat.txt"
    $batPath = Join-Path $exptPath $batFilename

    # 写入 Bat 文件内容（去除 PowerShell 的 & 调用符，转为 CMD 格式）
    $cmdContent = $cmdLine.TrimStart('& ') 
    # 确保 ffmpeg 路径带引号（虽然 $fmpgPath 变量里可能没带，但上面组合时加了）
    # 简单优化：如果 inputsAgg 前面有空格则保留
    
    Show-Border
    Write-TextFile -Path $batPath -Content $cmdContent -UseBOM $false
    
    Show-Success "任务完成！"
    Show-Info "命令已保存至: $batPath"
    Show-Info "请手动打开该文件，检查并删除末尾的 .txt 后缀运行。"
    Write-Host "提示：如果音画不同步，请在 -map 和 -c 之间添加 -itoffset <秒> 参数" -ForegroundColor DarkGray
    
    Pause
}

# 异常处理
try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按回车键退出"
}