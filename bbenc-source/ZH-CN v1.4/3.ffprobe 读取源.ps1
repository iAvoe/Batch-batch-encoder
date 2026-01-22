<#
.SYNOPSIS
    ffprobe 视频源分析脚本
.DESCRIPTION
    分析源视频并导出到 %USERPROFILE%\temp_v_info(_is_mov).csv: 总帧数，宽，高，色彩空间，传输特定等。繁体本地化由繁化姬实现：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# 若同时检测到 temp_v_info_is_mov.csv 与 temp_v_info.csv，则使用其中创建日期最新的文件
# $ffprobeCSV.A：stream (or not stream)
#            .B：width
#            .C：height  
#            .D：pixel format (pix_fmt)
#            .E：color_space
#            .F：color_transfer
#            .G：color_primaries
#            .H：avg_frame_rate | VOB：field_order
#            .I：MOV：nb_frames | VOB：avg_frame_rate | first frame count field (others)
#            .J：interlaced_frame | VOB：nb_frames
#            .K：top_field_first | VOB：N/A
#            .AA：NUMBER_OF_FRAMES-eng（仅用于非 MOV 格式）
# $sourceCSV.SourcePath：视频源路径（可以是 .avs/.vpy 源）
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
    # 文件夹：C:\Program Files (x86)\AviSynth+\plugins64+\ 中必须有 libvslsmashsource.dll
    $blankAVSScript = "LWLibavVideoSource($quotedImport) # 自动生成的占位脚本，按需修改"
    # 生成 VapourSynth 内容（使用原始字符串 literal r"..." 以避免转义问题）
    # 若 Get-QuotedPath 返回例如 "C:\path\file.mp4"，则 r$quotedImport 将成为 r"C:\path\file.mp4"
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
        Show-Error ("生成无滤镜脚本失败：" + $_)
        return $null
    }
}

function Get-NonSquarePixelWarning {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource
    )

    if (-not (Test-Path $ffprobePath)) {
        throw "Test-VideoContainerFormat：ffprobe.exe 不存在（$ffprobePath）"
    }
    if (-not (Test-Path $videoSource)) {
        throw "Test-VideoContainerFormat：输入视频不存在（$videoSource）"
    }
    $quotedVideoSource = Get-QuotedPath $videoSource

    try { # 使用 JSON 输入分析
        $ffprobeJson = & $ffprobePath -v quiet -hide_banner -select_streams v:0 -show_entries stream=sample_aspect_ratio -print_format json $quotedVideoSource 2>$null
        
        if ($LASTEXITCODE -eq 0) { # ffprobe 正常退出，分析结果存在
            $streamInfo = $ffprobeJson | ConvertFrom-Json
            # 只获取第一个视频流的 SAR
            $sampleAspectRatio = $streamInfo.streams[0].sample_aspect_ratio.Trim()

            if ($sampleAspectRatio -notlike "1:1") {
                Show-Warning "源 $videoSource 的宽高比（SAR）非 1:1（$sampleAspectRatio 的长方形像素）"
                Write-Host " 本软件暂无处理（编码为方形像素，致画面缩宽），" -ForegroundColor Yellow
                Write-Host " 请手动为生成的批处理命令指定播放 SAR 或添加矫正滤镜组" -ForegroundColor Yellow
            }
        }
        else { # ffprobe 失败
            throw "Get-NonSquarePixelWarning：ffprobe 执行或 JSON 解析失败"
        }
    }
    catch {
        throw ("Get-NonSquarePixelWarning - 检测失败：" + $_)
    }
}

# 利用 ffprobe 检测真实的视频文件封装格式，无视后缀名（封装格式用大写字母表示）
function Test-VideoContainerFormat {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource
    )

    if (-not (Test-Path $ffprobePath)) {
        throw "Test-VideoContainerFormat：ffprobe.exe 不存在（$ffprobePath）"
    }
    if (-not (Test-Path $videoSource)) {
        throw "Test-VideoContainerFormat：输入视频不存在（$videoSource）"
    }
    $quotedVideoSource = Get-QuotedPath $videoSource

    try { # 使用 JSON 输入分析
        $ffprobeJson = & $ffprobePath -hide_banner -v quiet -show_format -print_format json $quotedVideoSource 2>null

        if ($LASTEXITCODE -eq 0) { # ffprobe 正常退出，分析结果存在
            $formatInfo = $ffprobeJson | ConvertFrom-Json
            $formatName = $formatInfo.format.format_name

            # VOB 格式检测
            if ($formatName -match "mpeg") {
                # 进一步检测
                $ffprobeText = & $ffprobePath -hide_banner $quotedVideoSource 2>&1
                # 文件名含 VTS_ 字样（不确定是否全是大写，因此不用 cmatch）
                # $hasVTSFileName = $filename -match "^VTS_"
                # 元数据含 dvd_nav 字样（大概率是 VOB）
                $hasDVD = $false
                # 元数据含 mpeg2video 字样（大概率是 VOB）
                $hasMPEG2 = $false

                foreach ($line in $ffprobeText) {
                    if ($line -match "mpeg2video") {
                        $hasMPEG2 = $true
                    }
                    if ($line -match "dvd_nav") {
                        $hasDVD = $true
                    }
                }

                # VOB 通常包含 DVD 导航包或特定的流结构
                if ($hasDVD -or $hasMPEG2) {
                    Show-Info "Test-VideoContainerFormat：检测到 VOB 格式（DVD 视频）"
                    return "VOB"
                }
                elseif ($hasMPEG2) {
                    Show-Warning "Test-VideoContainerFormat：源使用 MPEG2 编码，将视作 VOB 格式（DVD 视频）"
                    return "VOB"
                }
                elseif ($hasDVD) {
                    Show-Warning "Test-VideoContainerFormat：源非 MPEG2 编码，但含有 DVD 导航标识，将视作 VOB 格式（DVD 视频）"
                    return "VOB"
                }
                else {
                     Show-Warning "Test-VideoContainerFormat：源非 MPEG2 编码，且无 DVD 导航标识，将视作一般封装格式"
                    return "std"
                }
            }
            elseif ($formatName -match "mov|mp4|m4a|3gp|3g2|mj2") {
                if ($formatName -match "qt" -or $ext -eq ".mov") {
                    Show-Info "Test-VideoContainerFormat：检测到 MOV 格式"
                    return "MOV"
                }
                else {
                    Show-Info "Test-VideoContainerFormat：检测到 MP4 格式"
                    return "MP4"
                }
            }
            elseif ($formatName -match "matroska") {
                Show-Info "Test-VideoContainerFormat：检测到 MKV 格式"
                return "MKV"
            }
            elseif ($formatName -match "webm") {
                Show-Info "Test-VideoContainerFormat：检测到 WebM 格式"
                return "WebM"
            }
            elseif ($formatName -match "avi") {
                Show-Info "Test-VideoContainerFormat：检测到 AVI 格式"
                return "AVI"
            }
            elseif ($formatName -match "ivf") {
                Show-Info "Test-VideoContainerFormat：检测到 ivf 格式"
                return "ivf"
            }
            elseif ($formatName -match "hevc") {
                Show-Info "Test-VideoContainerFormat：检测到 hevc 格式"
                return "hevc"
            }
            elseif ($formatName -match "h264" -or $formatName -match "avc") {
                Show-Info "Test-VideoContainerFormat：检测到 avc 格式"
                return "avc"
            }
            return $formatName
        }
        else { # ffprobe 失败
            throw "Test-VideoContainerFormat：ffprobe 执行或 JSON 解析失败"
        }
    }
    catch {
        throw ("Test-VideoContainerFormat：检测失败" + $_)
    }
}

#region Main
function Main {
    Show-Border
    Show-info ("ffprobe 源读取工具，导出 " + $Global:TempFolder + "temp_v_info(_is_mov).csv 以备用")
    Show-Border
    Write-Host ""

    # 根据管道上游程序选择源类型
    $sourceTypes = @{
        'A' = @{ Name = 'ffmpeg'; Ext = ''; Message = "任意源" }
        'B' = @{ Name = 'vspipe'; Ext = '.vpy'; Message = ".vpy 源" }
        'C' = @{ Name = 'avs2yuv'; Ext = '.avs'; Message = ".avs 源" }
        'D' = @{ Name = 'avs2pipemod'; Ext = '.avs'; Message = ".avs 源" }
        'E' = @{ Name = 'SVFI'; Ext = ''; Message = ".ini 源" } 
    }

    # 获取源文件类型
    $selectedType = $null
    do {
        Show-Info "选择先前脚本所用的管道上游程序（确认源符合程序要求）："
        $sourceTypes.GetEnumerator() | Sort-Object Key | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value.Name)"
        }
        $choice = (Read-Host " 请输入选项（A/B/C/D/E）").ToUpper()

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
        'ffmpeg'      { $upstreamCode = 'a' }
        'vspipe'      { $upstreamCode = 'b' }
        'avs2yuv'     { $upstreamCode = 'c' }
        'avs2pipemod' {
            $upstreamCode = 'd'
            Show-Info "指定 AviSynth.dll 的路径..."
            Write-Host " 在 AviSynth+ 仓库（https://github.com/AviSynth/AviSynthPlus/releases）中，"
            Write-Host " 下载 AviSynthPlus_x.x.x_yyyymmdd-filesonly.7z，即可获取 DLL"
            do {
                $Avs2PipeModDLL = Select-File -Title "选择 avisynth.dll" -InitialDirectory ([Environment]::GetFolderPath('System')) -DllOnly
                if (-not $Avs2PipeModDLL) {
                    $placeholderScript = Read-Host "未选择 DLL。按 Enter 重试，输入 'q' 强制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $Avs2PipeModDLL)
            Show-Success "已记录 AviSynth.dll 路径：$Avs2PipeModDLL"
        }
        'SVFI'        {
            $upstreamCode = 'e'
            Show-Info "正在检测 SVFI 渲染配置 INI 可能的路径..."
            $foundPath = Get-PSDrive -PSProvider FileSystem | ForEach-Object { 
                $p = "$($_.Root)SteamLibrary\steamapps\common\SVFI\Configs"
                if (Test-Path $p) { $p }
            } | Select-Object -First 1

            Show-Info "请指定 SVFI 渲染配置 INI 文件的路径"
            Write-Host " 如 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"

            do {
                if ($foundPath) { # 尝试自动定位到的 SVFI 路径（Select-File 能自动回退到 Desktop）
                    Show-Success "已定位候选路径：$foundPath"
                    $OneLineShotArgsINI = Select-File -Title "选择 SVFI 渲染配置文件（.ini）" -IniOnly -InitialDirectory $foundPath
                }
                else { # DIY
                    $OneLineShotArgsINI = Select-File -Title "选择 SVFI 渲染配置文件（.ini）" -IniOnly
                }

                if (-not $OneLineShotArgsINI -or -not (Test-Path -LiteralPath $OneLineShotArgsINI)) {
                    $placeholderScript = Read-Host " INI 路径不存在；按 Enter 重试，输入 'q' 强制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $OneLineShotArgsINI -or -not (Test-Path -LiteralPath $OneLineShotArgsINI))
        }
        default       { $upstreamCode = 'a' }
    }

    # 定义 IO 变量
    $videoSource = $null # ffprobe 将分析这个视频文件
    $scriptSource = $null # 脚本文件路径，如果有则在导出的 CSV 中覆盖视频源
    $encodeImportSourcePath = $null
    $svfiTaskId = $null

    # vspipe / avs2yuv / avs2pipemod：提供生成无滤镜脚本选项
    if ($isScriptUpstream) {
        do {
            # 选择视频源文件（ffprobe 分析）
            Show-Info "选择（脚本引用的）视频源文件（ffprobe 将分析此文件）"
            while ($null -eq $videoSource) {
                $videoSource = Select-File -Title "选择视频源文件（例如 .mp4/.mkv/.mov）"
                if ($null -eq $videoSource) { Show-Error "未选择视频文件" }
            }
        
            # 询问用户是否要生成无滤镜脚本
            $mode = Read-Host "输入 'y' 导入自定义脚本，输入 'n' 或 Enter 为视频源生成无滤镜脚本"
        
            if ($mode -eq 'y') { # 导入自定义脚本
                Show-Warning "由于脚本支持的导入源路径的种类繁多，如先定义路径变量或直接写入、`r`n 不同解析器、多种字面意义符搭配不同字符串引号、多视频源等条件组合起来过于复杂，`r`n 因此请自行检查脚本中的视频源是否真实存在`r`n"
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
            
                Show-Success "已选择脚本文件：$scriptSource"
                # 注意：视频源 $videoSource 仍然用于 ffprobe
            }
            # 生成无滤镜脚本
            elseif ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'n') {
                Show-Warning "AviSynth(+) 默认不自带 LSMASHSource.dll（视频导入滤镜）请保证该文件存在，"
                Write-Host " AVS 安装路径为：C:\Program Files (x86)\AviSynth+\plugins64+\" -ForegroundColor Yellow
                Write-Host " 下载并解压 64bit 版：https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works/releases`r`n" -ForegroundColor Magenta
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
                
                Show-Success "已生成无滤镜脚本：$scriptSource"
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
    # SVFI：从 INI 文件中读取视频路径，以及 task_id
    elseif ($OneLineShotArgsINI -and (Test-Path -LiteralPath $OneLineShotArgsINI)) { 
        # SVFI ini 文件中的视频路径（实际上内容为单行）：gui_inputs="{
        #     \"inputs\": [{
        #         \"task_id\": \"必须获取并赋值到 CSV\",
        #         \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\视频.mp4\",
        #         \"is_surveillance_folder\": false
        #     }]
        # }"
        # 读取文件并找到 gui_inputs 行，如：
        # gui_inputs="{\"inputs\": [{\"task_id\": \"798_2aa174\", \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\[Airota][Yuru Yuri\\u3001][OVA][BDRip 1080p AVC AAC][CHS].mp4\", \"is_surveillance_folder\": false}]}"
        Show-Info " 将尝试从 SVFI 渲染配置 INI 中读取视频源路径..."

        try { # 读取 INI 并查找 gui_inputs 行
            $iniContent = Get-Content -LiteralPath $OneLineShotArgsINI -Raw -ErrorAction Stop
            $pattern = 'gui_inputs\s*=\s*"((?:[^"\\]|\\.)*)"'
            $guiInputsMatch = [regex]::Match($iniContent, $pattern)
            if (-not $guiInputsMatch.Success) {
                Show-Error "在 SVFI INI 文件中未找到 gui_inputs 字段，请重新用 SVFI 生成 INI 文件"
                Read-Host "按 Enter 退出"
                return
            }

            # 提取含路径的 JSON 字符串（移除外层 gui_inputs="..."）
            $jsonString = $guiInputsMatch.Groups[1].Value
            $jsonString = $jsonString -replace '\\"', '"'
            $jsonString = $jsonString -replace '\\\\', '\\'
            Show-Debug "JSON 解析结果：$jsonString"

            # 转译 JSON 并提取视频源路径到 PowerShell 变量
            try {
                $jsonObject = $jsonString | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $jsonObject.inputs -or ($jsonObject.inputs.Count -eq 0)) {
                    Show-Error "SVFI INI 文件中缺少视频源导入（input）语句，请重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }

                # 获取首个输入文件的路径
                Show-Success "成功检测到导入语句"
                Show-Warning "将导入其中的首个视频源，忽略其它视频源"
                $jsonSource = $jsonObject.inputs[0].input_path
                if ([string]::IsNullOrWhiteSpace($jsonSource)) {
                    Show-Error "SVFI INI 文件中的导入语句指向空路径，请重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
                $svfiTaskId = $jsonObject.inputs[0].task_id
                if ([string]::IsNullOrWhiteSpace($svfiTaskId)) {
                    Show-Error "SVFI INI 文件中的 task_id 语句损坏，请重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
                Show-Success "从 SVFI INI 中解析到 Task ID: $svfiTaskId"

                $videoSource = Convert-IniPath -iniPath $jsonSource # FileUtils.ps1 函数
                Show-Success "从 SVFI INI 中解析到视频源：$videoSource"

                # 验证视频文件是否存在
                if (-not (Test-Path -LiteralPath $videoSource)) {
                    Show-Error "视频文件已不存在：$videoSource，请重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
            }
            catch {
                Show-Error "解析 JSON 失败：$_"
                Show-Debug "原始 JSON 字符串：$jsonString"
                Read-Host "按 Enter 退出"
                return
            }
        }
        catch {
            Show-Error "读取 SVFI INI 文件失败：$_"
            Read-Host "按 Enter 退出"
            return
        }

        $encodeImportSourcePath = $videoSource
    }
    else { # ffmpeg：视频源
        do {
            Show-Info "选择要分析的视频源文件"
            $videoSource = Select-File -Title "定位视频文件，如视频（.mp4/.mov/...）、RAW（.yuv/.y4m/...）"
            if (-not $videoSource) { 
                Show-Error "未选择文件" 
                continue
            }
            Show-Success "已选择视频源文件：$videoSource"
            break
        }
        while ($true)

        $encodeImportSourcePath = $videoSource
    }

    # 定位 ffprobe 程序
    Show-Info "定位 ffprobe.exe..."
    do {
        $ffprobePath =
            Select-File -Title "定位 ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
        if (-not (Test-Path -LiteralPath $ffprobePath)) {
            Show-Warning "找不到 ffprobe 可执行文件，请重试"
        }
    }
    while (-not (Test-Path -LiteralPath $ffprobePath))

    # 检测非方形像素源
    Get-NonSquarePixelWarning -ffprobePath $ffprobePath -videoSource $videoSource

    # 检测封装文件类型
    $realFormatName = Test-VideoContainerFormat -ffprobePath $ffprobePath -videoSource $videoSource
    $isMOV = ($realFormatName -like "MOV")
    $isVOB = ($realFormatName -like "VOB")
    # if ($isMOV) { Show-Debug "导入视频 $videoSource 的封装格式为 MOV" }
    # elseif ($isVOB -like "VOB") { Show-Debug "导入视频 $videoSource 的封装格式为 VOB" }
    # else { Show-Debug "导入视频 $videoSource 的封装格式非 MOV、VOB" }

    # 根据封装文件类型选用 ffprobe 命令、定义文件名
    $ffprobeArgs =
        if ($isMOV) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,interlaced_frame,top_field_first', '-of', 'csv'
        )}
        elseif ($isVOB) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,field_order', '-of', 'csv'
        )}
        else {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,interlaced_frame,top_field_first:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
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
        elseif ($isVOB) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.csv"
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
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv")
    Confirm-FileDelete $sourceCSVExportPath

    # 执行 ffprobe 并插入视频源路径
    try {
        $ffprobeOutputCSV = (& $ffprobePath @ffprobeArgs).Trim()
        # $ffprobeOutputCSVDebug = (& $ffprobePath @ffprobeArgsDebug).Trim()

        # 构建源 CSV 行
        $sourceInfoCSV = @"
"$encodeImportSourcePath",$upstreamCode,"$Avs2PipeModDLL","$OneLineShotArgsINI","$svfiTaskId"
"@

        Write-TextFile -Path $ffprobeCSVExportPath -Content $ffprobeOutputCSV -UseBOM $true
        # [System.IO.File]::WriteAllLines($ffprobeCSVExportPathDebug, $ffprobeOutputCSVDebug)

        Write-TextFile -Path $sourceCSVExportPath -Content $sourceInfoCSV -UseBOM $true
        Show-Success "CSV 文件已生成：`r`n $ffprobeCSVExportPath`r`n $sourceCSVExportPath"

        # 验证换行符
        Show-Debug "验证 CSV 文件格式..."
        if (-not (Test-TextFileFormat -Path $ffprobeCSVExportPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $sourceCSVExportPath)) {
            return
        }
    }
    catch { throw ("ffprobe 执行失败：" + $_) }

    Write-Host ""
    Show-Success "脚本执行完成！"
    Read-Host "按 Enter 退出"
}
#endregion

try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}