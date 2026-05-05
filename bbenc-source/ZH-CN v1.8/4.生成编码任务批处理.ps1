<#
.SYNOPSIS
    视频编码任务生成器
.DESCRIPTION
    生成用于视频编码的批处理文件，支持多种编码工具链组合，先前步骤已经录入所有上下游程序路径。本地化由繁化姬實現：https://zhconvert.org 
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.8
#>

# 加载共用代码
. "$PSScriptRoot\Common\Core.ps1"

# 需要结合视频数据统计的参数，管道参数已经在先前脚本完成，这里不写
$x264Params = [PSCustomObject]@{
    FPS = "" # 丢帧帧率用如 24000/1001 的字符串
    Resolution = ""
    TotalFrames = ""
    RAWCSP = "" # 位深、色彩空间
    Keyint = ""
    RCLookahead = ""
    RangeChromaLoc = ""
    SEICSP = "" # ColorMatrix、Transfer
    BaseParam = ""
    Input = "-"
    Output = ""
    OutputExtension = ".mp4"
}
$x265Params = [PSCustomObject]@{
    FPS = "" # 丢帧帧率用如 24000/1001 的字符串
    Resolution = ""
    TotalFrames = ""
    RAWCSP = ""
    Keyint = ""
    RCLookahead = ""
    MERange = ""
    Subme = ""
    RangeChromaLoc = ""
    SEICSP = ""
    PME = ""
    Pools = ""
    BaseParam = ""
    Input = "--input -"
    Output = ""
    OutputExtension = ".hevc"
}
$svtav1Params = [PSCustomObject]@{
    FPS = "" # 最优实践：丢帧帧率用 --fps-num --fps-denom 而不是 --fps
    RAWCSP = "" # --color-format --input-depth
    Keyint = ""
    Resolution = ""
    TotalFrames = ""
    RangeChromaLoc = ""
    SEICSP = "" # --matrix-coefficients --transfer-characteristics
    BaseParam = ""
    Input = "-i -"
    Output = ""
    OutputExtension = ".ivf"
}
$ffmpegParams = [PSCustomObject]@{
    Input = ""
    CSP = ""
    FPS = ""
    LogLevel = "-loglevel warning" # 隐藏进度以避免与编码器进度条打架
}
$vspipeParams = [PSCustomObject]@{
    Input = ""
}
$avsyuvParams = [PSCustomObject]@{
    Input = ""
    CSP = ""
}
$avsmodParams = [PSCustomObject]@{
    Input = ""
    DLLInput = ""
}
$olsargParams = [PSCustomObject]@{
    Input = ""
    ConfigInput = ""
}

# 隔行扫描格式支持
$interlacedArgs = [PSCustomObject]@{
    toPFilterTutorial = "https://iavoe.github.io/deint-ivtc-web-tutorial/HTML/index.html"
    isInterlaced = $false
    isTFF = $false
    isVOB = $false
    isMOV = $false
}

#region User Params
function Get-EncodeOutputName {
    Param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [bool]$IsPlaceholder = $false
    )

    # 1. 计算默认文件名（DefaultName）
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $finalDefaultName = $null
    
    if (-not $IsPlaceholder -and -not [string]::IsNullOrWhiteSpace($defaultNameBase)) {
        $finalDefaultName = $defaultNameBase
    }
    else {
        # 如果是占位符源（自动脚本）或源路径为空，使用时间戳作为默认名
        # 注意：文件名中不能包含冒号，因此用 HH-mm
        $finalDefaultName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    }

    # 2. 生成用于显示的显示文件名（DisplayName），过长则截断
    $displayPrompt = if ($finalDefaultName.Length -gt 18) { 
        $finalDefaultName.Substring(0, 18) + "..." 
    }
    else {  $finalDefaultName  }

    # 3. 交互循环
    while ($true) {
        Write-Host ''
        $inputOp = Read-Host " 指定压制结果的文件名——[a：从文件拷贝 | b：手写 | Enter：$displayPrompt]"

        # 3-1：直接 Enter（默认行为）
        if ([string]::IsNullOrWhiteSpace($inputOp)) {
            if (Test-FilenameValid -Filename $finalDefaultName) {
                Show-Success "使用默认文件名：$finalDefaultName"
                return $finalDefaultName
            }
            else {
                Show-Error "默认文件名包含非法字符，请选择其他方式。"
            }
        }
        elseif ($inputOp -eq 'a') { # 3-2：选项 a
            Show-Info "拷贝文件名..."
            $selectedFile = $null
            
            # 内层循环：直到选到文件或强制退出
            while (-not $selectedFile) {
                $selectedFile = Select-File -Title "选择一个文件以拷贝文件名"
                if (-not $selectedFile) {
                    $retry = Read-Host " 未选择文件，按 Enter 重试，输入 'q' 返回上级"
                    if ($retry -eq 'q') { break }
                }
            }

            if ($selectedFile) {
                $extractedName = [System.IO.Path]::GetFileNameWithoutExtension($selectedFile)
                # 既然是系统里已存在的文件名，通常是合法的，但为了保险依然验证
                if (Test-FilenameValid -Filename $extractedName) {
                    Show-Success "提取文件名：$extractedName"
                    return $extractedName
                }
            }
        }
        elseif ($inputOp -eq 'b') { # 3-3：选项 b
            Show-Info "手动输入..."
            Write-Host " 两个方括号间必须要有字符隔开，不要输入特殊符号"
            
            $manualName = $null
            while ($true) {
                $manualName = Read-Host " 填写或粘贴除后缀外的文件名（输入 'q' 返回上级）"
                if ($manualName -eq 'q') { break }

                if ([string]::IsNullOrWhiteSpace($manualName)) {
                    Show-Warning "文件名不能为空"
                    continue
                }
                if (Test-FilenameValid -Filename $manualName) {
                    Show-Success "设定文件名：$manualName"
                    return $manualName
                }
                else {
                    Show-Error "文件名包含非法字符，请重试"
                }
            }
        }
        else { # 3-4
            Show-Warning "选项无效，请输入 a、b 或按 Enter"
        }
    }
}

# 解析分数字符串并进行除法计算，用例：ConvertTo-Fraction -fraction "1/2"
function ConvertTo-Fraction {
    param([Parameter(Mandatory=$true)][string]$fraction)
    if ($fraction -match '^(\d+)/(\d+)$') {
        return [double]$matches[1] / [double]$matches[2]
    }
    elseif ($fraction -match '^\d+(\.\d+)?$') {
        return [double]$fraction
    }
    throw "ConvertTo-Fraction：无法解析帧率除法字符串：$fraction"
}

# 生成管道上游程序导入、下游程序导出命令（管道命令已经在先前脚本中写完，自动创建目录）
function Get-EncodingIOArgument {
    Param (
        [Parameter(ParameterSetName="ffmpeg")][switch]$isffmpeg,
        [Parameter(ParameterSetName="vspipe")][switch]$isVsPipe,
        [Parameter(ParameterSetName="avs2yuv")][switch]$isAvs2Yuv,
        [Parameter(ParameterSetName="avs2pipemod")][switch]$isAvs2Pipemod,
        [Parameter(ParameterSetName="svfi")][switch]$isSVFI,
        [Parameter(ParameterSetName="x264")][switch]$isx264,
        [Parameter(ParameterSetName="x265")][switch]$isx265,
        [Parameter(ParameterSetName="svtav1")][switch]$isSVTAV1,
        [string]$source, # 导入路径到文件（带或不带引号）
        [switch]$isImport,
        [string]$outputFilePath, # 导出目录，不用于导入
        [string]$outputFileName, # 导出文件名，不用于导入
        [string]$outputExtension,
        [switch]$showIvtcGuide
    )
    # 确保只有一个开关被激活
    $switchedOn = @(
        if ($isffmpeg) { 'ffmpeg' }
        if ($isvspipe) { 'vspipe' }
        if ($isavs2yuv) { 'avs2yuv' }
        if ($isavs2pipemod) { 'avs2pipemod' }
        if ($issvfi) { 'svfi' }
        if ($isx264) { 'x264' }
        if ($isx265) { 'x265' }
        if ($isSVTAV1) { 'svtav1' }
    )
    if ($switchedOn.Count -eq 0) {
        throw "Get-EncodingIOArgument：必须指定一个程序，如启用 -isffmpeg"
    }
    if ($switchedOn.Count -gt 1) {
        throw "Get-EncodingIOArgument：最多指定一个程序，当前指定了: $($switchedOn -join ', ')"
    }
    $program = $switchedOn[0]

    # 警告编码器在隔行源上的限制
    if (!$isImport -and !$isx264 -and $script:interlacedArgs.isInterlaced) {
        if ($isSVTAV1) { # Continue on error
            Show-Warning "Get-EncodingIOArgument: SVT-AV1 不支持隔行扫描源"
        }
        if ($isx265) {
            Show-Warning "Get-EncodingIOArgument: x265 隔行扫描编码支持是实验性功能"
        }
        if ($showIvtcGuide) {
            Show-Info ("转逐行与 IVTC 滤镜教程: " + $script:interlacedArgs.toPFilterTutorial)
            Write-Host ''
        }
    }

    # 隔行扫描相关参数
    $iArg = if (-not $script:interlacedArgs.isInterlaced) { "" }
        elseif ($isavs2pipemod) { # avs2pipemod: y4mp (progressive), y4mt (tff), y4mb (bff)
            if ($script:interlacedArgs.isTFF) { "-y4mt" } else { "-y4mb" }
        }
        elseif ($isx264) { # x264: --tff, --bff
            if ($script:interlacedArgs.isTFF) { "--tff" } else { "--bff" }
        }
        elseif ($isx265) { # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
            if ($script:interlacedArgs.isTFF) { "--interlace 1" } else { "--interlace 2" }
        }
        else { "" } # SVT-AV1 与 ffmpeg 不支持隔行，vspipe/avs2yuv/svfi 忽略

    # 验证输入文件（生成导入命令）
    $quotedInput = $null
    if ($isImport) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw "导入模式需要 source 参数"
        }
        if (-not (Test-Path -LiteralPath $source)) { # 默认文件名一定含有方括号
            throw "输入文件不存在：$source"
        }
        $quotedInput = Get-QuotedPath $source
    }
    else { # 导出模式必须给出导出文件名
        if ([string]::IsNullOrWhiteSpace($outputFileName)) {
            throw "导出（下游）模式需要 outputFileName 参数"
        }
    }
    
    # 组合输出路径（不做扩展名自动添加）
    $combinedOutputPath = $null
    if (-not [string]::IsNullOrWhiteSpace($outputFilePath)) {
        $quotedExport = Get-QuotedPath $outputFilePath
        if (-not (Test-Path -LiteralPath $quotedExport)) {
            New-Item -ItemType Directory -Path $outputFilePath -Force | Out-Null
        }
    }
    $combinedOutputPath =
        if ($outputFilePath) {
            Join-Path -Path $outputFilePath -ChildPath $outputFileName
        }
        else { $outputFileName }
    
    # 路径加引号（$quoteInput 已定义；勿删参数括号，否则扩展名会丢）
    $quotedOutput = Get-QuotedPath ($combinedOutputPath+$outputExtension)
    $sourceExtension = [System.IO.Path]::GetExtension($source)

    # 生成管道上游导入与下游导出参数
    if ($isImport) { # 导入模式
        switch -Wildcard ($program) {
            'ffmpeg' { return "-i $quotedInput" }
            'svfi' { return "--input $quotedInput" }
            # $sourceJson.sourcePath 只有 .vpy 或 .avs 单个源，而先前步骤允许选择多种上游程序
            # 因此必然会出现 .vpy 脚本输入出现在 AVS 程序，或反过来的情况
            # 尽管“自动生成占位脚本”功能会同时提供 .vpy 和 .avs 脚本，但用户选择输入自定义脚本就不会做这一步
            # 这个问题需要通过修改源的扩展名来缓解，但默认修改文件名后的源一定不存在，此时只警告用户然后继续
            'vspipe' {
                if ($sourceExtension -ne '.vpy') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".vpy")
                    Show-Debug "vspipe 线路缺乏 .vpy 脚本源，尝试匹配新路径: $(Split-Path $newSource -Leaf)"
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        Show-Success "已成功切换源到 $newSource"
                    }
                    else { Show-Debug "vspipe 线路的导入需手动纠正" }
                }
                # 返回输入路径和隔行扫描参数
                if ($iArg) { return "$quotedInput $iArg" }
                else { return $quotedInput }
            }
            { $_ -in @('avs2yuv', 'avs2pipemod') } {
                if ($sourceExtension -ne '.avs') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".avs")
                    Show-Debug ($_ + " 线路缺乏 .avs 脚本源，尝试匹配新路径: $(Split-Path $newSource -Leaf)")
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        Show-Success "已成功切换源到 $newSource"
                    }
                    else { Show-Debug ( $_ + " 线路的导入需手动纠正") }
                }
                # 返回输入路径和隔行扫描参数
                if ($iArg) { return "$quotedInput $iArg" }
                else { return $quotedInput }
            }
            'x264' { if ($iArg) { return "- $iArg" } else { return "-" } }
            'x265' { if ($iArg) { return "$iArg --input -" } else { return "--input -" } }
            'svtav1' { return "-i -" } # 原生不支持隔行
        }
        break
    }
    else { # 导出模式
        switch ($program) {
            'x264' { return "--output $quotedOutput" }
            'x265' { return "--output $quotedOutput" }
            'svtav1' { return "-b $quotedOutput" }
            default { throw "未识别的导出程序：$program" }
        }
    }
    throw "无法为程序 $program 生成 IO 参数"
}

# 获取基础参数
function Get-x264BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserCRF,
        [switch]$askUserFGO
    )

    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableFGO = $false
    if ($askUserFGO -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "修改版（Mod）x264 支持「基于高频信息量的率失真优化（Film Grain Optimization）」，建议开启"
        Write-Host " 用 x264.exe --fullhelp 检测 --fgo 参数是否存在" -ForegroundColor DarkGray
        $enableFGO =
            if ((Read-Host " 输入 'y' 以启用 --fgo（提高画质），或 Enter 以禁用（包括无法确定）") -match '^[Yy]$') {
                $true
            }
            else { $false }
        Write-Host $(if ($enableFGO) {" 启用 fgo" } else { " 禁用 fgo" })

    }
    elseif (-not $isHelp) {
        Write-Host " 已跳过 --fgo 请柬..."
    }
    $fgo10 = if ($enableFGO) {" --fgo 10"} else { "" }
    $fgo15 = if ($enableFGO) {" --fgo 15"} else { "" }

    $crfParam = "--crf 23" # else default
    if ($askUserCRF -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "配置 x264 码率调谐常量（CRF）正整数"

        while ($true) {
            $crf = Read-Host " [13-16：超清 | 18-20：高清 | 21-24：流媒体 | 0：无损 | Enter：x264 默认（23）]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " 使用默认 CRF：23"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " 输入值非正整数，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 0 -or $crfInt -gt 51) {
                $choice = Read-Host " 输入值超出 0-51 范围，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            $crfParam = "--crf $crf"
            break
        }
    }

    $default = if ($script:interlacedArgs.isInterlaced) {
        ("--bframes 14 --b-adapt 2 --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightp 0 --weightb --min-keyint 5 --ref 3 $crfParam --chroma-qp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22" + $fgo10)
    }
    else {
        ("--bframes 14 --b-adapt 2 --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 5 --ref 3 $crfParam --chroma-qp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22" + $fgo10)
    }
    
    switch ($pickOps) {
        # 通用 General Purpose，bframes 14
        a {return $default}
        # 素材 Stock Footage，bframes 12
        b {return ("--partitions all --bframes 12 --b-adapt 2 --me esa --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 1 --ref 3 $crfParam --tune grain --trellis 2" + $fgo15)}
        helpzh {
            Write-Host ''
            Write-Host " 选择 x264 自定义预设——[a：通用 | b：剪辑素材]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ''
            Write-Host " Select a custom preset for x264——[a: general purpose | b: stock footage]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-x264BaseParam：使用编码器默认参数"
            return $default
        }
    }
}

# 获取基础参数：ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | x265.exe [Get-...] [Get-x265BaseParam] --y4m --input - --output ".\out.hevc"
function Get-x265BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserCRF
    )
    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $default = "--high-tier --preset slow --me umh --weightb --aq-mode 4 --bframes 5 --ref 3"

    $crfParam = "--crf 28" # else default
    if ($askUserCRF -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "配置 x265 码率调谐常量（CRF）正整数"

        while ($true) {
            $crf = Read-Host " [17-20：超清 | 21-25：高清 | 26-30：流媒体 | 0：无损 | Enter：x265 默认（28）]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " 使用默认 CRF：28"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " 输入值非正整数，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 0 -or $crfInt -gt 51) {
                $choice = Read-Host " 输入值超出 0-51 范围，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            $crfParam = "--crf $crf"
            break
        }
    }

    switch ($pickOps) {
        # 通用 General Purpose，bframes 5
        a {return $default}
        # 录像 Movie，bframes 8
        b {return "--high-tier --ctu 64 --tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --rect --tskip --tskip-fast --me star --weightb --ref 4 --max-merge 5 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --b-intra $crfParam --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1.1 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3"} 
        # 素材 Stock Footage，bframes 7
        c {return "--high-tier --ctu 32 --tskip --me star --max-merge 5 --early-skip --b-intra --no-open-gop --min-keyint 1 --ref 3 --fades --bframes 7 --b-adapt 2 $crfParam --crqpoffs -3 --cbqpoffs -2 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --splitrd-skip --deblock -1:-1 --tune grain"}
        # 动漫 Anime，bframes 16
        d {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --tskip --tskip-fast --me umh --weightb --max-merge 5 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --bframe-bias 20 --constrained-intra --b-intra $crfParam --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --deblock -1:0 --limit-sao --sao-non-deblock"}
        # 穷举法 Exhausive
        e {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 4 --limit-tu 1 --rect --amp --tskip --me star --weightb --max-merge 5 --ref 3 --no-open-gop --min-keyint 1 --fades --bframes 16 --b-adapt 2 --b-intra $crfParam --crqpoffs -5 --cbqpoffs -2 --ipratio 1.67 --pbratio 1.33 --cu-lossless --psy-rdoq 2.5 --rdoq-level 2 --hevc-aq --aq-strength 1.4 --qg-size 8 --rd 5 --limit-refs 0 --rskip 2 --rskip-edge-threshold 3 --no-cutree --psy-rd 1.5 --rdpenalty 2 --deblock -2:-2 --limit-sao --sao-non-deblock --selective-sao 1"}
        helpzh {
            Write-Host ''
            Write-Host " 选择 x265 自定义预设——[a：通用 | b：录像 | c：剪辑素材 | d：动漫 | e：穷举法]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ''
            Write-Host " Select a custom preset for x265——[a: general purpose | b: film | c: stock footage | d: anime | e: exhausive]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-x265BaseParam：使用编码器默认参数"
            return $default
        }
    }
}

# 获取基础参数：ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | SvtAv1EncApp.exe -i - [Get-svtav1BaseParam] -b ".\out.ivf"
function Get-svtav1BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserCRF,
        [switch]$askUserDLF
    )
    
    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableDLF2 = $false
    Write-Host ''
    if ($askUserDLF -and (-not $isHelp) -and ($pickOps -ne 'b')) {
        Write-Host " 修改版 SVT-AV1 编码器（如 SVT-AV1-Essential）支持高精度去块滤镜 --enable-dlf 2"  -ForegroundColor Cyan
        Write-Host " 用 SvtAv1EncApp.exe --help 检测值`'2`'是否受支持" -ForegroundColor DarkGray
        $enableDLF2 =
            if ((Read-Host " 输入 'y' 以启用（提高画质），或 Enter 以禁用（包括无法确定）") -match '^[Yy]$') {
                $true
            }
            else { $false }
        Write-Host $(if ($enableDLF2) { " 启用 dlf2" } else { " 禁用 dlf2" })
    }
    elseif (-not $isHelp) {
        Write-Host " 已跳过 --enable-dlf 2 请柬..."
    }
    $deblock = if ($enableDLF2) {"--enable-dlf 2"} else {"--enable-dlf 1"}

    $crfParam = "--crf 35" # else default
    if ($askUserCRF -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "配置 SVT-AV1 码率调谐常量（CRF）正整数"

        while ($true) {
            $crf = Read-Host " [28-32：超清 | 33-36：高清 | 37-40：流媒体 | 1：无损 | Enter：SVT-AV1 默认（35）]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " 使用默认 CRF：35"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " 输入值非正整数，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 1 -or $crfInt -gt 70) {
                $choice = Read-Host " 输入值超出 1-70 范围，按 Enter 重试或输入 'q' 强制退出"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            $crfParam = "--crf $crf"
            break
        }
    }

    $default = ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 $crfParam --enable-qm 1 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 6 --progress 1 " + $deblock)
    switch ($pickOps) {
        # 画质 Quality
        a {return $default}
        # 压缩 Compression
        b {return ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 $crfParam --sharpness 4 --progress 1 " + $deblock)}
        # 速度 Speed
        c {return "--preset 2 --scd 1 --scm 0 --enable-tf 2 --tf-strength 2 $crfParam --tune 0 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 4 --progress 1"}
        helpzh {
            Write-Host ''
            Write-Host " 选择 SVT-AV1 自定义预设——[a：画质优先 | b：压缩优先 | c：速度优先]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ''
            Write-Host " Select a custom preset for SVT-AV1——[a: HQ | b: High compression | c: High speed]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-svtav1BaseParam：使用编码器默认参数"
            return $default
        }
    }
}

# 交互式获取编码器基础预设参数
function Invoke-BaseParamSelection {
    Param (
        [Parameter(Mandatory=$true)][string]$CodecName, # 仅用于显示
        [Parameter(Mandatory=$true)][scriptblock]$GetParamFunc, # 对应的获取函数
        [hashtable]$ExtraParams = @{}
    )

    $selectedParam = ""
    do {
        & $GetParamFunc -pickOps "helpzh"
        
        $selection = (Read-Host " 指定一份 $CodecName 自定义预设，输入 'q' 忽略（沿用编码器内置默认）").ToLower()

        if ($selection -eq 'q') { # $selectedParam = "" # 已经是默认值，不用再赋值
            break
        }
        elseif ($selection -notmatch "^[a-z]$") {
            if ((Read-Host " 无法识别选项，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                exit 1
            }
            continue
        }

        # 根据用户输入获取基础参数
        $selectedParam = & $GetParamFunc -pickOps $selection @ExtraParams
    }
    while (-not $selectedParam)

    if ($selectedParam) {
        Show-Success "已定义 $CodecName 基础参数：$selectedParam"
    }
    else { Show-Info "$CodecName 将使用编码器默认参数" }

    return $selectedParam
}

# 获取关键帧间隔，默认 10*fps，直接适用于 x264
function Get-Keyint { 
    Param (
        [Parameter(Mandatory=$true)]$fpsString,
        [int]$bframes,
        [int]$second = 10,
        [switch]$askUser,
        [switch]$isx264,
        [switch]$isx265,
        [switch]$isSVTAV1
    )
    if (($isx264 -and $isx265) -or ($isx264 -and $isSVTAV1) -or ($isx265 -and $isSVTAV1)) {
        throw "Get-Keyint：参数异常，一次只能给一个编码器配置参数"
    }

    # 注意：值可以是“24000/1001”的字符串，需要处理（得到 23.976d）
    [double]$fps = ConvertTo-Fraction $fpsString

    $userSecond = $null # 用户指定秒
    if ($askUser) {
        if ($isx264) {
            Write-Host ''
            Show-Info "请指定 x264 的最大关键帧间隔秒"
            Write-Host " 正整数，非帧数，如：11 代表 11 秒" -ForegroundColor DarkGray
        }
        elseif ($isx265) {
            Write-Host ''
            Show-Info "请指定 x265 的最大关键帧间隔秒数"
            Write-Host " 正整数，非帧数，如：12 代表 12 秒" -ForegroundColor DarkGray
        }
        elseif ($isSVTAV1) {
            Write-Host ''
            Show-Info "请指定 SVT-AV1 的最大关键帧间隔秒数"
            Write-Host " 正整数，非帧数，如：13 代表 13 秒" -ForegroundColor DarkGray
        }
        else {
            throw "未指定要配置最大关键帧间隔参数的编码器，无法执行"
        }
        Write-Host ''
        
        $userSecond = $null
        do { # 默认多轨剪辑的的解码占用为关键帧间隔取和，但实际情况下，解码占用取决于硬件解码器的数量，所以仅设为两倍
            Write-Host " 1. 分辨率高于 2560x1440 则偏左选一格"
            Write-Host " 2. 画面内容简单，平面居多则偏右选一格"
            $userSecond =
                Read-Host " 大致范围：[低功耗/多轨剪辑：6-7 | 一般（不确定则用）：8-10 | 高：11-13+ ]"
            if ($userSecond -notmatch "^\d+$") {
                if ((Read-Host " 未输入正整数，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                    exit 1
                }
            }
        }
        while ($userSecond -notmatch "^\d+$")
        $second = $userSecond
    }

    try {
        $keyint = [math]::Round(($fps * $second))

        # 关键帧间隔必须大于连续 B 帧，但这与 SVT-AV1 无关
        if ($isSVTAV1) {
            Show-Success "已配置 SVT-AV1 最大关键帧间隔：${second} 秒"
            return "--keyint ${second}s"
        }

        $keyint = 
            if ($bframes -lt $keyint) { # 蠢到没边但实现了把 $bframes 当做上限的 hack
                [math]::max($keyint, $bframes)
            }
            elseif ($bframes -ge $keyint) {
                [math]::min($keyint, $bframes)
            }

        if ($isx264) {
            Show-Success "已配置 x264 最大关键帧间隔：${keyint} 帧"
        }
        elseif ($isx265) {
            Show-Success "已配置 x265 最大关键帧间隔：${keyint} 帧"
        }
        return "--keyint " + $keyint
    }
    catch {
        Show-Warning "无法读取视频帧率信息，关键帧间隔（Keyint）将使用编码器默认"
        return ""
    }
}

# 指定运行于特定 NUMA 节点，索引从 0 开始数；例：--pools -,+（双路下使用二号节点）
function Get-x265ThreadPool {
    Param ([int]$atNthNUMA=0) # 直接输入，一般情况下用不到

    $nodes = Get-CimInstance Win32_Processor # | Select-Object Availability
    [int]$procNodes = ($nodes | Measure-Object).Count
    
    # 统计可用处理器
    if ($procNodes -lt 1) { $procNodes = 1 }

    # 验证参数
    if ($atNthNUMA -lt 0 -or $atNthNUMA -gt ($procNodes - 1)) {
        throw "NUMA 节点索引不能大于可用节点索引，且不能为负"
    }

    Write-Output ""
    if ($procNodes -gt 1) {
        if ($atNthNUMA -eq 0) {
            do {
                $inputValue = Read-Host "检测到 $procNodes 处 NUMA 节点，请指定使用一处节点（范围：0-$($procNodes-1)）"
                if ([string]::IsNullOrWhiteSpace($inputValue)) {
                    if ((Read-Host "未输入值，按 Enter 重试，输入 'q' 强制退出") -eq 'q') { exit }
                }
                elseif ($inputValue -notmatch '^\d+$') {
                    if ((Read-Host "$inputValue 输入了非整数，按 Enter 重试，输入 'q' 强制退出") -eq 'q') { exit }
                }
                elseif (($inputValue -lt 0) -or ($inputValue -gt ($procNodes - 1))) {
                    if ((Read-Host "NUMA 节点不存在，按 Enter 重试，输入 'q' 强制退出") -eq 'q') { exit }
                }
            }
            while ($inputValue -notmatch '^\d+$' -or ($inputValue -lt 0) -or ($inputValue -gt ($procNodes - 1)))
            $atNthNUMA = [int]$inputValue
        }

        $poolParam = "--pools "
        for ($i=0; $i -lt $procNodes; $i++) {
            if ($i -eq $atNthNUMA) { $poolParam += "+," }
            else { $poolParam += "-," }
        }
        return $poolParam.TrimEnd(',')
    }
    else {
        Show-Success "检测到安装了 1 颗处理器，忽略 x265 参数 --pools"
        return ""
    }
}
#endregion

#region Auto params
function Get-RateControlLookahead { # 1.8*fps
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)][int]$bframes,
        [double]$durationSecond = 1.8
    )
    try {
        $frames = [math]::Round(((ConvertTo-Fraction $fpsString) * $durationSecond))
        # 必须大于 --bframes
        $frames = [math]::max($frames, $bframes+1)
        return "--rc-lookahead $frames"
    }
    catch {
        Show-Warning "Get-RateControlLookahead：无法读取视频帧率信息，率控制前瞻距离（RC Lookahead）将使用编码器默认"
        return ""
    }
}

function Get-x265MERange {
    Param ([Parameter(Mandatory=$true)]$w, [Parameter(Mandatory=$true)]$h)
    [int]$res = 0
    try {
        $width = [int]$w
        $height = [int]$h
        $res = $width * $height
    }
    catch {
        throw "无法解析视频分辨率：宽度=$w, 高度=$h"
    }
    if ($res -ge 8294400) { return "--merange 56" } # >=3840x2160
    elseif ($res -ge 3686400) { return "--merange 52" } # >=2560*1440
    elseif ($res -ge 2073600) { return "--merange 48" } # >=1920*1080
    elseif ($res -ge 921600) { return "--merange 40" } # >=1280*720
    else { return "--merange 36" }
}

# 根据视频帧率给出 x265 子像素搜索参数值
function Get-x265SubmotionEstimation { # 24fps=3, 48fps=4, 60fps=5, ++=6
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [switch]$stripParameterName
    )
    $fps = ConvertTo-Fraction $fpsString
    $subme = 6
    if ($fps -lt 25) {$subme = 3}
    elseif ($fps -lt 49) {$subme = 4}
    elseif ($fps -lt 61) {$subme = 5}

    if ($stripParameterName) { return $subme }
    return ("--subme " + $subme)
}

# 判断核心数大于 36 时开启并行动态搜索
function Get-x265PME {
    if ([int](wmic cpu get NumberOfCores)[2] -gt 36) {
        return "--pme"
    }
    return ""
}

# 总帧数可能出现在非常规字段，需要导入整个 JSON 检查
function Get-FrameCount {
    Param (
        [Parameter(Mandatory=$true)]$vidStream,
        [switch]$isSVTAV1,
        [switch]$showWarning
    )
    if ($null -eq $vidStream) {
        throw "无法解析 ffprobe JSON 或找不到视频流信息，建议重新运行步骤 3 脚本"
    }
    # 尝试 nb_frames 字段、tags 中的 NUMBER_OF_FRAMES
    $frameCount =
        if ($vidStream.nb_frames -and $vidStream.nb_frames -ne 'N/A') {
            $vidStream.nb_frames
        }
        elseif ($vidStream.tags.NUMBER_OF_FRAMES) {
            $vidStream.tags.NUMBER_OF_FRAMES
        }
        else { $null }

    if ($frameCount -match '^\d+$' -and [int]$frameCount -gt 0) {
        if ($isSVTAV1) { return "-n $frameCount" }
        else { return "--frames $frameCount" }
    }

    if ($showWarning) { # 从外部控制只显示一次
        Show-Warning 'Get-FrameCount：视频总帧数数据不存在或被删除，将无法估计编码进度与 ETA'
    }
    return ""
}

function Get-InputResolution {
    Param (
        [Parameter(Mandatory=$true)][int]$w,
        [Parameter(Mandatory=$true)][int]$h,
        [bool]$isSVTAV1=$false
    )
    if ($null -eq $w -or $null -eq $h) {
        throw "Get-InputResolution：视频元数据缺少帧大小（宽高）信息"
    }
    if ($isSVTAV1) { return "-w $w -h $h" }
    return "--input-res ${w}x${h}"
}

# 添加对 SVT-AV1 的丢帧帧率支持，丢帧帧率直接保留字符串
function Get-FPSParam {
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)]
        [ValidateSet("ffmpeg","x264","avc","x265","hevc","svtav1","SVT-AV1")]
        [string]$Target
    )
    if ([string]::IsNullOrWhiteSpace($fpsString)) {
        throw "Get-FPSParam：视频元数据缺少帧率信息"
    }
    # SVT-AV1 特殊处理：使用 --fps-num 和 --fps-denom 分开写
    if ($Target -in @("svtav1", "SVT-AV1")) {
        if ($fpsString -match '^(\d+)/(\d+)$') {
            # 若是分数格式（如 24000/1001）
            return "--fps-num $($matches[1]) --fps-denom $($matches[2])"
        }
        else { # 直接输入了小数：转换为分数
            switch ($fpsString) {
                "23.976" { return "--fps-num 24000 --fps-denom 1001" }
                "29.97"  { return "--fps-num 30000 --fps-denom 1001" }
                "59.94"  { return "--fps-num 60000 --fps-denom 1001" }
                default  { # 其他值使用整数
                    try {
                        $intFps = [Math]::Round([double]$fpsString)
                    }
                    catch [System.Management.Automation.RuntimeException] {
                        throw "Get-FPSParam：帧率参数 fpsString 无法被转换为数字：$fpsString"
                    }
                    return "--fps $intFps" 
                }
            }
        }
    }
    
    # x264、x265、ffmpeg 都可以直接使用分数字符串或小数
    switch ($Target) {
        "ffmpeg" { return "-r $fpsString" }
        default  { return "--fps $fpsString" }
    }
}

# 获取矩阵格式、传输特质、三原色
function Get-ColorSpaceSEI {
    Param (
        [Parameter(Mandatory=$true)]$ColorMatrix,
        [Parameter(Mandatory=$true)]$Transfer,
        [Parameter(Mandatory=$true)]$Primaries,
        [switch]$isx264,
        [switch]$isx265,
        [switch]$isSVTAV1
    )
    $result = @()
    if (($isx264 -and $isx265) -or ($isx264 -and $isSVTAV1) -or ($isx265 -and $isSVTAV1)) {
        throw "Get-ColorSpaceSEI：参数异常，一次只能给一个编码器配置参数"
    }
    
    if ($isx264) {
        # Colormatrix
        if (($ColorMatrix -eq "unknown") -or ($ColorMatrix -eq "bt2020nc")) {
            $result += "--colormatrix undef" # x264 不写 unknown
        }
        else { # fcc，bt470bg，smpte170m，smpte240m，GBR，YCgCo，bt2020c，smpte2085，chroma-derived-nc，chroma-derived-c，ICtCp
            $result += "--colormatrix $ColorMatrix"
        }

        # Transfer
        if ($Transfer -eq "unknown") {
            # bt470m，bt470bg，smpte170m，smpte240m，linear，log100，log316，iec61966-2-4，bt1361e，iec61966-2-1，bt2020-10，bt2020-12，smpte2084，smpte428，arib-std-b67
            $result += "--transfer undef"
        }
        else {
            $result += "--transfer $Transfer"
        }

        # Color Primaries
        if (($Primaries -eq "unknown") -or ($Primaries -eq "unspec")) {
            $result += "--colorprim undef"
        }
        else {
            $result += "--colorprim $Primaries"
        }
    }
    elseif ($isx265) {
        # Colormatrix
        if ($ColorMatrix -eq "bt2020nc") {
            $result += "--colormatrix unknown"
        }
        else { # ==x264
            $result += "--colormatrix $ColorMatrix"
        }

        # Transfer
        $result += "--transfer $Transfer"

        # Color Primaries
        if (($Primaries -eq "unknown") -or ($Primaries -eq "unspec")) {
            $result += "--colorprim unknown"
        }
        else {
            $result += "--colorprim $Primaries"
        }
    }
    elseif ($isSVTAV1) {
        # Color Matrix
        $c = switch ($ColorMatrix) {
            identity     { 0 }
            bt709        { 1 }
            unspec       { 2 }
            fcc          { 4 }
            bt470bg      { 5 }
            bt601        { 6 }
            smpte240m    { 7 }
            ycgco        { 8 }
            "bt2020-ncl" { 9 }
            "bt2020-cl"  { 10 }
            smpte2085    { 11 }
            "chroma-ncl" { 12 }
            "chroma-cl"  { 13 }
            ictcp        { 14 }
            default { 
                Show-Warning "Get-ColorSpaceSEI：未知矩阵格式：$ColorMatrix，使用默认（bt709）"
                1
            }
        }
        $result += "--matrix-coefficients $c"

        # Transfer
        $t = switch ($Transfer) {
            bt709           { 1 }
            unspec          { 2 }
            bt470m          { 4 }
            bt470bg         { 5 }
            bt601           { 6 }
            smpte240m       { 7 }
            linear          { 8 }
            log100          { 9 }
            "log100-sqrt10" { 10 }
            "iec61966-2-4"  { 11 }
            "iec61966-2-1"  { 13 }
            "bt2020-10"     { 14 }
            "bt2020-12"     { 15 }
            smpte2084       { 16 }
            smpte428        { 17 }
            hlg             { 18 }
            default { 
                Show-Warning "Get-ColorSpaceSEI：未知传输特质：$Transfer，使用默认（bt709）"
                1
            }
        }
        $result += "--transfer-characteristics $t"

        # Color Primaries
        $p = switch ($Primaries) {
            bt709      { 1 }
            unspec     { 2 }
            unknown    { 2 }
            bt470m     { 4 }
            bt470bg    { 5 }
            bt601      { 6 }
            smpte240m  { 7 }
            film       { 8 }
            bt2020     { 9 }
            xyz        { 10 }
            smpte431   { 11 }
            smpte432   { 12 }
            ebu3213    { 22 }
            default {
                Show-Warning "Get-ColorSpaceSEI：未知三原色：$Primaries，使用默认（bt709）"
                1
            }
        }
        $result += "--color-primaries $p"
    }
    else {
        Show-Warning "Get-ColorSpaceSEI：未指定编码器，跳过色彩矩阵，传输特质与三原色参数配置"
        return ""
    }

    return ($result -join " ")
}

# 输入已经是 ffmpeg CSP 了
function Get-ffmpegCSP {
    Param ([ValidateSet(
            "yuv420p","yuv420p10le","yuv420p12le",
            "yuv422p","yuv422p10le","yuv422p12le",
            "yuv444p","yuv444p10le","yuv444p12le",
            "gray","gray10le","gray12le",
            "nv12","nv16"
        )][Parameter(Mandatory=$true)]$PixelFormat)
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $PixelFormat -replace '^-pix_fmt\s+', ''
    return "-pix_fmt " + $pixfmt
}

function Get-EncoderAVSRawCSPBits {
    Param (
        [Parameter(Mandatory=$true)]$PixelFormat,
        [bool]$isEncoderInput=$true,
        [bool]$isAvs2YuvInput=$false,
        [bool]$isSVTAV1=$false,
        [bool]$isAVSPlus=$true # 与 main 定义的默认值一致
    )
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $PixelFormat -replace '^-pix_fmt\s+', ''
    $chromaFormat = $null
    $depth = 8

    # 解析并检查位深
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "视频编码可能不支持 $depth bit 位深" # $depth = 8
    }

    # 解析色度采样
    $chromaFormat = switch -Regex ($pixfmt) {
        '^yuv420'        { 'i420' }
        '^yuv422'        { 'i422' }
        '^nv12'          { 'nv12' }
        '^nv16'          { 'nv16' }
        '^yuv444'        { 'i444' }
        '^(gray|yuv400)' { 'i400' }
        default {
            Show-Warning "[编码器/AviSynth] 未知像素格式：$pixfmt，将使用默认值"
            if ($isEncoderInput) { 'i420' } else { 'AUTO' }
        }
    }

    if ($isEncoderInput) {
        if ($isSVTAV1) { # --color-format，--input-depth
            if ($depth -eq 12) {
                Show-Warning "Get-EncoderAVSRawCSPBits: 检测到与 SVT-AV1 不兼容的 12bit 源视频位深，若先前指定该编码器则重做步骤 2"
                Write-Host ("─" * 50)
            }

            # SVT-AV1 使用数字枚举的 --color-format
            $svtColorMap = @{
                'i400' = 0
                'gray' = 0
                'i420' = 1
                'nv12' = 1
                'i422' = 2
                'nv16' = 2
                'i444' = 3
            }
            $svtColor = $svtColorMap[$chromaFormat]
            if ($null -eq $svtColor) {
                Show-Warning "[SVT-AV1] 未知色度格式：$chromaFormat，回退到 yuv420"
                $svtColor = 1
            }
            return "--color-format $svtColor --input-depth $depth"
        }
        else { # x265 使用 --input-csp 和 --input-depth
            $cspMap = @{
                '420' = 'i420'
                '422' = 'i422'
                '444' = 'i444'
                '400' = 'i400'
            }
            $csp = $cspMap[$chromaFormat]
            if (-not $csp) { $csp = 'i420' }
            return "--input-csp $csp --input-depth $depth"
        }
    } # elseif ($isAvs2YuvInput) {
    else { # avs2yuv 0.30 仅支持 AviSynth+，因此 -csp 参数被取消
        $cspMap = @{
            '420' = 'i420'
            '422' = 'i422'
            '444' = 'i444'
            '400' = 'i400'
        }
        $csp = $cspMap[$chromaFormat]
        if (-not $csp) { $csp = 'AUTO' }
        if ($isAVSPlus) { return "-depth $depth" }
        else { return "-csp $csp -depth $depth" }
    }
    return ""
}

function Set-InterlacedArgs {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$fieldOrderOrIsInterlacedFrame,
        [string]$tffAttribute
    )
    # 初始化
    $script:interlacedArgs.isInterlaced = $false
    $script:interlacedArgs.isTFF = $false

    # 处理 VOB、MOV 格式
    if ($script:interlacedArgs.isMOV -or $script:interlacedArgs.isVOB) {
        $fieldOrder = $fieldOrderOrIsInterlacedFrame.ToLower().Trim()
        
        switch -Regex ($fieldOrder) {
            '^progressive$' {
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            '^(tt|bt)$' { # tt：上场优先显示、bt：下编上播
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $true
            }
            '^(bb|tb)$' { # bb：下场优先显示、tb：上编下播
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $false
            }
            '^unknown$' {
                Show-Warning "Set-InterlacedArgs: VOB field_order 为 'unknown'，将视为逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            {[string]::IsNullOrWhiteSpace($fieldOrder)} {
                Show-Warning "Set-InterlacedArgs: VOB field_order 为空，将视为逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            default {
                Show-Warning "Set-InterlacedArgs: VOB field_order='$fieldOrder' 无法解析，将视为逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
        }
    }
    else { # 非 VOB、MOV 格式，解析 interlaced_frame (0/1)
        $interlacedFrame = $fieldOrderOrIsInterlacedFrame.Trim()
        
        if ([string]::IsNullOrWhiteSpace($interlacedFrame)) {
            Show-Warning "Set-InterlacedArgs: interlaced_frame 为空，将视作逐行"
            $script:interlacedArgs.isInterlaced = $false
        }
        else {
            try {
                $interlacedInt = [int]::Parse($interlacedFrame)
                $script:interlacedArgs.isInterlaced = ($interlacedInt -eq 1)
            }
            catch {
                Show-Warning "Set-InterlacedArgs: 无法解析 interlaced_frame='$interlacedFrame'，将视作逐行"
                $script:interlacedArgs.isInterlaced = $false
            }
        }
        
        # 解析 top_field_first (-1/0/1)
        $tff = $tffAttribute.Trim()
        
        if ([string]::IsNullOrWhiteSpace($tff)) {
            if ($script:interlacedArgs.isInterlaced) {
                Show-Warning "Set-InterlacedArgs: 场序未知且视频为隔行，将视作上场优先"
                $script:interlacedArgs.isTFF = $true
            }
            else {
                $script:interlacedArgs.isTFF = $false
            }
        }
        else {
            try {
                $tffInt = [int]::Parse($tff)
                # 1 = top-first, 0/-1 = bottom-first
                switch ($tffInt) {
                    1 { $script:interlacedArgs.isTFF = $true }
                    0 { $script:interlacedArgs.isTFF = $false }
                    -1 { $script:interlacedArgs.isTFF = $true } 
                    default {
                        Show-Warning "Set-InterlacedArgs: top_field_first 值异常 '$tffInt'，将视作上场优先"
                        $script:interlacedArgs.isTFF = $true
                    }
                }
            }
            catch {
                Show-Warning "Set-InterlacedArgs: 无法解析 top_field_first='$tff'，默认上场优先"
                $script:interlacedArgs.isTFF = $true
            }
        }
    }
    
    Show-Debug "Set-InterlacedArgs—隔行扫描：$($script:interlacedArgs.isInterlaced), 上场优先：$($script:interlacedArgs.isTFF)"
}

function Get-RangeChromaLocation {
    <#
    .SYNOPSIS
        Build encoder color-range / chroma-location arguments from ffprobe metadata.
    .DESCRIPTION
        Returns a space-separated argument string for x264 / x265 / SVT-AV1.
        - Range: tv / pc
        - ChromaLocation: ffprobe-style values such as left / center / topleft / top / bottomleft / bottom / unknown
        ffmpeg support is not added since it can do this automatically
        All string input will be converted to lowercase
        IMPORTANT: ffprobe 'center' (JPEG) is closest, but not equivalent to SVT-AV1's colocated
    #>
    Param (
        [Parameter(Mandatory=$true)][string]$PixelFormat,
        [Parameter(Mandatory=$true)][string]$Range,
        [Parameter(Mandatory=$true)][string]$ChromaLocation,
        [switch]$isx264,
        [switch]$isx265,
        [switch]$issvtav1,
        [switch]$showWarning # Use different function call to prevent console error spam
    )
    $result = @()
    if ((@($isx264, $isx265, $issvtav1) | Where-Object { $_ }).Count -ne 1) {
        throw "Get-RangeChromaLocation：参数异常，一次只能且至少给一个工具配置参数"
    }

    # Lowercase
    $PixelFormat = ([string]$PixelFormat).ToLowerInvariant().Trim()
    $Range = ([string]$Range).ToLowerInvariant().Trim()
    $ChromaLocation = ([string]$ChromaLocation).ToLowerInvariant().Trim()

    # Range
    if (-not [string]::IsNullOrWhiteSpace($Range) -and
        $Range -notin @('tv', 'pc', 'unknown')) {
        if ($showWarning) {
            Show-Warning "Get-RangeChromaLocation：元数据 color_range 异常，将忽略色彩范围参数设置：$Range"
        }
    }
    else {
        if ($isx264) {
            if ($Range -eq 'pc') { $result += '--fullrange' }
        }
        elseif ($isx265) {
            if ($Range -eq 'pc') { $result += '--range full' }
            elseif ($Range -eq 'tv') { $result += '--range limited' }
        }
        elseif ($issvtav1) {
            if ($Range -eq 'pc') { $result += '--color-range 1' }
            elseif ($Range -eq 'tv') { $result += '--color-range 0' }
        }
    }

    # Chroma location
    $ChromaSampleDepth = Get-ChromaSubsamplingDepth $PixelFormat
    if ($ChromaSampleDepth -eq -2) {
        if ($showWarning) {
            Show-Warning "Get-RangeChromaLocation——色彩空间参数异常，将忽略色彩范围参数设置：$PixelFormat"
        }
        return ($result -join ' ')

    }
    if ($ChromaSampleDepth -le 0) {
        if ($showWarning) {
            Show-Info "Get-RangeChromaLocation——源视频不含色度采样压缩（RGB/灰阶/4:4:4），无需指定采样点位"
        }
        return ($result -join ' ')
    }

    if ($isx264 -or $isx265) {
        $cl = switch ($ChromaLocation) {
            'left'       { 0; break }
            'center'     { 1; break }
            'topleft'    { 2; break }
            'top'        { 3; break }
            'bottomleft' { 4; break }
            'bottom'     { 5; break }
            'unknown'    { $null; break }
            'unspecified'{ $null; break }
            default      { $null; break }
        }
        if ($null -eq $cl) {
            if (-not $quiet -and $ChromaLocation -notin @('', 'unknown', 'unspecified', 'bottom')) {
                Show-Warning "Get-RangeChromaLocation——非常规色度采样点位：$ChromaLocation，将忽略"
            }
        }
        else {
            $result += "--chromaloc $cl"
        }
    }
    elseif ($issvtav1) {
        # SVT-AV1 chroma-sample-position mapping based on actual FFmpeg internal mapping:
        # AVCHROMA_LOC_LEFT (1)     -> EB_CSP_VERTICAL
        # AVCHROMA_LOC_CENTER (2)   -> EB_CSP_COLOCATED  
        # AVCHROMA_LOC_TOPLEFT (3)  -> EB_CSP_TOPLEFT
        # AVCHROMA_LOC_TOP (4)      -> EB_CSP_TOP
        $cl = switch ($ChromaLocation) {
            'left'       { 'vertical'; break }
            'center'     { 'colocated'; break } # Correct but maybe misaligned
            'topleft'    { 'topleft'; break }
            'top'        { 'top'; break }
            'bottomleft' { $null; break }
            'bottom'     { $null; break }
            'unknown'    { 'unknown'; break }
            'unspecified'{ $null; break }
            default      { $null; break }
        }
        if ($ChromaLocation -in @('bottomleft', 'bottom')) {
            if ($showWarning) {
                Show-Warning "Get-RangeChromaLocation——SVT-AV1 不支持底部、左下的色度采样点位：$ChromaLocation，将跳过参数值指定"
            }
        }
        elseif ($cl -eq 'colocated') {
            if ($showWarning) {
                Show-Warning "Get-RangeChromaLocation——色度采样点位可能未对齐（ffmpeg/ffprobe→center 对应 SVT-AV1 colocated），如有准确对齐需求，建议将源视频恢复到 4:4:4 色度采样再编码"
            }
        }

        if ($null -ne $cl) {
            $result += "--chroma-sample-position $cl"
        }
    }

    return ($result -join " ")
}
#endregion

#region Identify
function Get-ChromaSubsamplingDepth {
    <#
    .SYNOPSIS
        Detect depth of chroma subsampling, returns int as depth
    .DESCRIPTION
        Less chroma info equals bigger depth number. Input will be converted to lowercase
    .PARAMETER PixelFormat
        ffmpeg or ffprobe analyzed color space profile (CSP) string, such as yuv420p, nv12
    .OUTPUTS
        -2: Unknown
        -1: Not luma-chroma format
        0:  No sampling (4:4:4)
        1:  4:2:2 (half horizontal chroma res)
        2:  4:2:0 (half horizontal and vertical chroma res)
        3:  4:1:1 (quarter horizontal chroma res)
        4:  4:1:0 (quarter horizontal and vertical chroma res)
    .EXAMPLE
        Get-ChromaSubsamplingDepth 'yuv420p'
        return: 2
    #>
    param([string]$PixelFormat)
    $fmt = $PixelFormat.ToLower()

    $isRgbOrGray = $fmt -match '^(rgb|bgr|gbrp|gbrap|rgba|bgra|argb|abgr|gray|mono|pal|bayer|xyz)'
    if ($isRgbOrGray) { return -1 } # RGB / BGR / mono
    
    $is444 = $fmt -match '444' -or $fmt -match '^nv24|^p410|^p416|^y410|^xv30|^xv36|^vuyx|^vyu444'
    if ($is444) { return 0 } # 4:4:4

    if ($fmt -match '422' -or
        $fmt -match '^yuyv|^uyvy|^yvyu|^nv16|^p210|^p216|^y210|^y212|^y216' -or
        $fmt -match '^yuva422') { return 1 } # 4:2:2

    if ($fmt -match '420' -or
        $fmt -match '^nv12|^p010|^p012|^p016' -or
        $fmt -match '^yuva420') { return 2 } # 4:2:0

    if ($fmt -match '411' -or
        $fmt -match '^uyyvyy411') { return 3 } # 4:1:1

    if ($fmt -match '410') { return 4 } # 4:1:0
    return -2
}

# 由于自动生成的脚本源存在，因此文件名会变成 "blank_vs_script/blank_avs_script" 而非视频文件名。若匹配到则消除默认（Enter）选项
function Get-IsPlaceHolderSource {
    Param(
        [Parameter(Mandatory=$true)][string]$defaultName,
        [Parameter(Mandatory=$true)]$sourceJson
    )
    return [string]::IsNullOrWhiteSpace($defaultName) -or
        $defaultName -match '^(blank_.*|.*_script)$' -or
        -not (Test-Path -LiteralPath $sourceJson.SourcePath)
}

# 简单通过排除法获取管道类型，因此如果添加只支持 RAW YUV 管道的上游工具需要修改
function Get-IsRAWSource ([string]$validateUpstreamCode) {
    return $validateUpstreamCode -eq 'e'
}

# 尽快判断文件是否为 VOB 格式（格式判断已被先前脚本确定），影响后续大量参数的 $ffprobeJson 变量读法
function Set-IsVOB {
    Param([Parameter(Mandatory=$true)][string]$ffprobeJsonPath)
    if ([string]::IsNullOrWhiteSpace($ffprobeJsonPath)) {
        throw "Set-IsVOB：ffprobeJsonPath 参数为空，无法判断"
    }
    $script:interlacedArgs.isVOB = $ffprobeJsonPath -like "*_vob*"
}

# 尽快判断文件是否为 MOV 格式（格式判断已被先前脚本确定），影响后续大量参数的 $ffprobeJson 变量读法
function Set-IsMOV {
    Param([Parameter(Mandatory=$true)][string]$ffprobeJsonPath)
    if ([string]::IsNullOrWhiteSpace($ffprobeJsonPath)) {
        throw "Set-IsMOV：ffprobeJsonPath 参数为空，无法判断"
    }
    $script:interlacedArgs.isMOV = $ffprobeJsonPath -like "*_mov*"
}
#endregion

# 拼接对象中非空的属性
function Join-Params ($Object, $PropertyOrder) {
    $values = foreach ($prop in $PropertyOrder) { 
        $val = $Object.$prop
        # Validation
        switch ($val) {
            $null { continue }
            { $_ -is [bool] } { 
                Show-Warning "Join-Params: 属性 '$prop' 是布尔值（$val），将忽略该项"
                continue
            }
            { $_ -is [string] -and [string]::IsNullOrWhiteSpace($_) } { continue }
            default { [string]$val }
        }
    }
    return $values -join ' '
}

#region Main
function Main {
    $toolsJson = Join-Path $Global:TempFolder "tools.json"   

    Show-Border
    Write-Host "参数计算与批处理注入工具" -ForegroundColor Cyan
    Show-Border
    Write-Host ''

    Show-Info "正在读取步骤 3 的视频分析结果..."
    # 1. 自动查找最新的 ffprobe json，并读取视频信息
    $ffprobeJsonPath = 
        Get-ChildItem -Path $Global:TempFolder -Filter "temp_v_info*.json" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 | 
        ForEach-Object { $_.FullName }

    if ($null -eq $ffprobeJsonPath) {
        throw "未找到 ffprobe 生成的 JSON 文件；请运行步骤 3 脚本以补全"
    }
    # 2. 查找源信息 json
    $sourceJsonPath = Join-Path $Global:TempFolder "temp_s_info.json"
    if (-not (Test-Path $sourceJsonPath)) {
        throw "未找到源专用信息 JSON 文件；请运行步骤 3 脚本以补全"
    }

    $ffprobeJson = Read-JsonFile $ffprobeJsonPath
    if ($null -eq $ffprobeJson) {
        throw "无法解析 ffprobe JSON 或找不到视频流信息，请运行步骤 3 脚本以补全"
    }
    if (-not $ffprobeJson.PSObject.Properties.Name -contains 'width') {
        throw "ffprobe JSON 格式不正确，请运行步骤 3 脚本以补全"
    }
    $sourceJson = Read-JsonFile $sourceJsonPath
    if ($null -eq $ffprobeJson) {
        throw "无法解析源专用 JSON 或找不到信息，请运行步骤 3 脚本以补全"
    }
    if (-not $sourceJson.SourcePath) { # 检查视频/VS/AVS 源有值即可
        throw "temp_s_info.json 数据不完整，请运行步骤 3 脚本以补全"
    }
    # 视频流（通常是 streams 数组中 codec_type 为 video 的项）
    $videoStream = $ffprobeJson.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    # 定位首帧（用于获取隔行扫描等动态信息）
    $firstFrame = $ffprobeJson.frames[0]
    if ($null -eq $videoStream) {
        throw "JSON 中未找到视频流信息"
    }
    Write-Host ("─" * 50)

    # 隔行扫描源支持
    # ffmpeg、vspipe、avs2yuv、svfi：忽略
    # avs2pipemod: y4mp, y4mt, y4mb (progressive, tff, bff)
    # x264: --tff, --bff
    # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
    # SVT-AV1：原生不支持
    Show-Info "正在区分隔行扫描格式..."
    Set-IsVOB -ffprobeJsonPath $ffprobeJsonPath
    Set-IsMOV -ffprobeJsonPath $ffprobeJsonPath
    if ($script:interlacedArgs.isMOV -and $script:interlacedArgs.isVOB) {
        Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $videoStream.field_order
    }
    else {
        Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $firstFrame.interlaced_frame -tffAttribute $firstFrame.top_field_first
    }
    Write-Host ("─" * 50)
    
    # 计算并赋值给对象属性
    Show-Info "正在优化编码参数..."
    # $x265Params.Profile = Get-x265SVTAV1Profile -PixelFormat $videoStream.pix_fmt -isIntraOnly $false -isSVTAV1 $false
    # $svtav1Params.Profile = Get-x265SVTAV1Profile -PixelFormat $videoStream.pix_fmt -isIntraOnly $false -isSVTAV1 $true
    $x265Params.Resolution = Get-InputResolution -w $videoStream.width -h $videoStream.height
    $svtav1Params.Resolution = Get-InputResolution -w $videoStream.width -h $videoStream.height -isSVTAV1 $true
    $x265Params.MERange = Get-x265MERange -w $videoStream.width -h $videoStream.height

    # Show-Debug "矩阵格式：$($videoStream.color_space)；传输特质：$($videoStream.color_transfer)；三原色：$($videoStream.color_primaries)"
    $x264Params.SEICSP = Get-ColorSpaceSEI -ColorMatrix $videoStream.color_space -Transfer $videoStream.color_transfer -Primaries $videoStream.color_primaries -isx264
    $x265Params.SEICSP = Get-ColorSpaceSEI -ColorMatrix $videoStream.color_space -Transfer $videoStream.color_transfer -Primaries $videoStream.color_primaries -isx265
    $svtav1Params.SEICSP = Get-ColorSpaceSEI -ColorMatrix $videoStream.color_space -Transfer $videoStream.color_transfer -Primaries $videoStream.color_primaries -isSVTAV1

    $x265Params.TotalFrames = Get-FrameCount -vidStream $videoStream
    $x264Params.TotalFrames = Get-FrameCount -vidStream $videoStream
    $svtav1Params.TotalFrames = Get-FrameCount -vidStream $videoStream -isSVTAV1 -showWarning

    # x265 线程管理
    $x265Params.PME = Get-x265PME
    $x265Params.Pools = Get-x265ThreadPool

    # avs2yuv 设置
    $isAvsPlus = $true
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Success "检测到配置文件（$($savedConfig.SaveDate)），正在加载..."
            if ($null -ne $savedConfig.IsAvsPlus) {
                $isAvsPlus = $savedConfig.IsAvsPlus 
            }
        }
        catch { Show-Info "配置文件损坏或不存在，将使用默认值（AviSynth+）作为 avs2yuv 的运行环境，建议重新运行步骤 2 脚本" }
    }
    
    # 色彩空间格式
    $ffmpegParams.CSP = Get-ffmpegCSP -PixelFormat $videoStream.pix_fmt
    $avsyuvParams.CSP = Get-EncoderAVSRawCSPBits -PixelFormat $videoStream.pix_fmt -isEncoderInput $false -isAvs2YuvInput $true -isSVTAV1 $false -isAVSPlus $isAvsPlus
    $x264Params.RAWCSP = Get-EncoderAVSRawCSPBits -PixelFormat $videoStream.pix_fmt -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $x265Params.RAWCSP = Get-EncoderAVSRawCSPBits -PixelFormat $videoStream.pix_fmt -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $svtav1Params.RAWCSP = Get-EncoderAVSRawCSPBits -PixelFormat $videoStream.pix_fmt -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $true

    $x264Params.RangeChromaLoc = Get-RangeChromaLocation -PixelFormat $videoStream.pix_fmt -Range $videoStream.color_range -ChromaLocation $videoStream.chroma_location -isx264 -showWarning
    $x265Params.RangeChromaLoc = Get-RangeChromaLocation -PixelFormat $videoStream.pix_fmt -Range $videoStream.color_range -ChromaLocation $videoStream.chroma_location -isx265 -showWarning
    $svtav1Params.RangeChromaLoc = Get-RangeChromaLocation -PixelFormat $videoStream.pix_fmt -Range $videoStream.color_range -ChromaLocation $videoStream.chroma_location -issvtav1 -showWarning

    $ffmpegParams.FPS = Get-FPSParam -fpsString $videoStream.avg_frame_rate -Target ffmpeg
    $svtav1Params.FPS = Get-FPSParam -fpsString $videoStream.avg_frame_rate -Target svtav1
    $x265Params.FPS = Get-FPSParam -fpsString $videoStream.avg_frame_rate -Target x265
    $x264Params.FPS = Get-FPSParam -fpsString $videoStream.avg_frame_rate -Target x264
    $x265Params.Subme = Get-x265SubmotionEstimation -fpsString $videoStream.avg_frame_rate
    [int]$x265SubmeInt = Get-x265SubmotionEstimation -fpsString $videoStream.avg_frame_rate -stripParameterName
    $x264Params.Keyint = Get-Keyint -fpsString $videoStream.avg_frame_rate -bframes 250 -askUser -isx264
    $x265Params.Keyint = Get-Keyint -fpsString $videoStream.avg_frame_rate -bframes $x265SubmeInt -askUser -isx265
    $svtav1Params.Keyint = Get-Keyint -fpsString $videoStream.avg_frame_rate -bframes 999 -askUser -isSVTAV1
    $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $videoStream.avg_frame_rate -bframes 250
    $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $videoStream.avg_frame_rate -bframes $x265SubmeInt

    Write-Host ("─" * 50)

    # Avs2PipeMod 需要的 DLL
    $quotedDllPath = Get-QuotedPath $sourceJson.Avs2PipeModDllPath
    $avsmodParams.DLLInput = "-dll $quotedDllPath"

    # SVFI 需要的配置文件及 Task ID
    $olsargParams.ConfigInput =
        if (![string]::IsNullOrWhiteSpace($sourceJson.SvfiInputConf)) {
            "--config $(Get-QuotedPath $sourceJson.SvfiInputConf) --task-id $($sourceJson.SvfiTaskId)"
        }
        else { '' }

    Write-Host ''
    Show-Info "配置编码结果导出路径、文件名..."
    $encodeOutputPath = Select-Folder -Description "选择压制结果的导出位置"
    # 1. 获取源文件名（用于传递给函数）
    $sourcePathRaw = $sourceJson.SourcePath
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($sourcePathRaw)
    # 2. 判断是否为占位符脚本源
    $isPlaceholder = Get-IsPlaceHolderSource -defaultName $defaultNameBase -sourceJson $sourceJson
    # 3. 获取最终文件名（所有交互、验证、重试都在函数内完成）
    $encodeOutputFileName = Get-EncodeOutputName -SourcePath $sourcePathRaw -IsPlaceholder $isPlaceholder

    Show-Info "生成管道上下游程序的 IO 参数 (Input/Output)..."
    # 1. 管道上游程序输入
    # 管道连接符由先前脚本生成的批处理控制，这里不写
    $ffmpegParams.Input = Get-EncodingIOArgument -isffmpeg -isImport -source $sourceJson.SourcePath
    $vspipeParams.Input = Get-EncodingIOArgument -isVsPipe -isImport -source $sourceJson.SourcePath
    $avsyuvParams.Input = Get-EncodingIOArgument -isAvs2Yuv -isImport -source $sourceJson.SourcePath
    $avsmodParams.Input = Get-EncodingIOArgument -isAvs2Pipemod -isImport -source $sourceJson.SourcePath
    $olsargParams.Input = Get-EncodingIOArgument -isSVFI -isImport -source $sourceJson.SourcePath
    # 2. 管道下游程序（编码器）输入——需要根据隔行扫描判断参数，因此必用 Get-EncodingIOArgument
    $x264Params.Input = Get-EncodingIOArgument -isx264 -isImport -source $sourceJson.SourcePath
    $x265Params.Input = Get-EncodingIOArgument -isx265 -isImport -source $sourceJson.SourcePath
    $svtav1Params.Input = Get-EncodingIOArgument -isSVTAV1 -isImport -source $sourceJson.SourcePath
    # 3. 管道下游程序输出
    $x264Params.Output = Get-EncodingIOArgument -isx264 -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x264Params.OutputExtension
    $x265Params.Output = Get-EncodingIOArgument -isx265 -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x265Params.OutputExtension
    $svtav1Params.Output = Get-EncodingIOArgument -isSVTAV1 -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $svtav1Params.OutputExtension -showIvtcGuide

    Write-Host ("─" * 50)

    Show-Info "构建管道下游（编码器）基础参数..."
    $x264Params.BaseParam = Invoke-BaseParamSelection -CodecName "x264" -GetParamFunc ${function:Get-x264BaseParam} -ExtraParams @{ askUserFGO = $true; askUserCRF = $true }
    $x265Params.BaseParam = Invoke-BaseParamSelection -CodecName "x265" -GetParamFunc ${function:Get-x265BaseParam} -ExtraParams @{ askUserCRF = $true }
    $svtav1Params.BaseParam = Invoke-BaseParamSelection -CodecName "SVT-AV1" -GetParamFunc ${function:Get-svtav1BaseParam} -ExtraParams @{ askUserDLF = $true; askUserCRF = $true }

    Show-Info "拼接最终参数字符串..."
    # 这些字符串将直接注入到批处理的 "set 'xxx_params=...'" 中
    # 空参数可能会导致双空格出现，但路径、文件名里也可能有双空格，因此不过滤（-replace "  ", " "）
    # 1. 管道上游工具
    $ffmpegFinalParam = Join-Params $ffmpegParams @('FPS', 'Input', 'CSP', 'LogLevel')
    $vspipeFinalParam = Join-Params $vspipeParams @('Input')
    $avsyuvFinalParam = Join-Params $avsyuvParams @('Input', 'CSP')
    $avsmodFinalParam = Join-Params $avsmodParams @('Input', 'DLLInput')
    $olsargFinalParam = Join-Params $olsargParams @('Input', 'ConfigInput')
    # 2. x264（Input 必须在最末尾），x265，SVT-AV1
    $x264FinalParam = Join-Params $x264Params @('Keyint', 'SEICSP', 'RangeChromaLoc', 'RCLookahead', 'BaseParam', 'Output', 'Input')
    $x265FinalParam = Join-Params $x265Params @('Keyint', 'SEICSP', 'RangeChromaLoc', 'RCLookahead', 'MERange', 'Subme', 'PME', 'Pools', 'BaseParam', 'Input', 'Output')
    $svtav1FinalParam = Join-Params $svtav1Params @('Keyint', 'SEICSP', 'RangeChromaLoc', 'BaseParam', 'Input', 'Output')
    # 3. Raw 管道附加参数
    $x264RawPipeApdx = Join-Params $x264Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    $x265RawPipeApdx = Join-Params $x265Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    $svtav1RawPipeApdx = Join-Params $svtav1Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    # 4. RAW 管道兼容
    if (Get-IsRAWSource -validateUpstreamCode $sourceJson.UpstreamCode) {
        $x264FinalParam = "$x264RawPipeApdx $x264FinalParam"
        $x265FinalParam = "$x265RawPipeApdx $x265FinalParam"
        $svtav1FinalParam = "$svtav1RawPipeApdx $svtav1FinalParam"
    }

    # 生成 ffmpeg, vspipe, avs2yuv, avs2pipemod 编码任务批处理
    Write-Host ''
    Show-Info "定位先前脚本生成的 encode_template.bat 模板..."
    $templateBatch = $null
    while (-not $templateBatch) {
        $templateBatch = Select-File -Title "选择 encode_template.bat 批处理" -BatOnly
        
        if (-not $templateBatch) {
            if ((Read-Host "未选择模板文件，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                return
            }
        }
    }

    # 读取模板
    $batchContent = [System.io.File]::ReadAllText($templateBatch, $Global:utf8BOM)

    # 准备要注入的参数块
    # 一次性设置所有工具的参数，批处理执行时只用到它需要的部分
    $paramsBlock = @"
REM ========================================================
REM [自动注入] 详细编码参数（$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')）
REM ========================================================
set ffmpeg_params=$ffmpegFinalParam
set vspipe_params=$vspipeFinalParam
set avs2yuv_params=$avsyuvFinalParam
set avs2pipemod_params=$avsmodFinalParam
set svfi_params=$olsargFinalParam

set x264_params=$x264FinalParam

set x265_params=$x265FinalParam

set svtav1_params=$svtav1FinalParam

REM ========================================================
REM [自动注入] RAW 管道辅助参数（手动添加）
REM ========================================================
REM x264_appendix=$x264RawPipeApdx
REM x265_appendix=$x265RawPipeApdx
REM svtav1_appendix=$svtav1RawPipeApdx


"@

    # 查找替换锚点
    # 策略：找到 "REM 参数示例" 行，替换为参数块
    # 若模板变更，则直接停止执行
    $newBatchContent = $batchContent

    # 字样匹配
    $enAnchor = '(?msi)^REM\s+Parameter\s+examples\b'
    $zhcnAnchor = '(?msi)^REM\s+参数示例\b'
    $zhtwAnchor = '(?msi)^REM\s+參數範例\b'

    if ($batchContent -match $enAnchor) {
        $pattern = '(?msi)^REM\s+Parameter\s+examples\b.*?^(?=REM\s+Specify\s+commandline\b)'
    }
    elseif ($batchContent -match $zhcnAnchor) {
        $pattern = '(?msi)^REM\s+参数示例\b.*?^(?=REM\s+指定本次所需编码命令\b)'
    }
    elseif ($batchContent -match $zhtwAnchor) {
        $pattern = '(?msi)^REM\s+參數範例\b.*?^(?=REM\s+指定本次所需編碼命令\b)'
    }
    else {
        throw "未在步骤 2 生成的模板中找到参数占位符，请重新运行步骤 2 脚本"
    }
    # 替换操作使用 [regex]::Replace 以确保 .NET 正则表达式的行为。
    $newBatchContent = [regex]::Replace($batchContent, $pattern, $paramsBlock)

    # 保存最终文件
    $finalBatchPath = Join-Path (Split-Path $templateBatch) "encode_task_final.bat"
    Show-Debug "输出文件：$finalBatchPath"
    Write-Host ''
    
    try {
        Confirm-FileDelete $finalBatchPath
        Write-TextFile -Path $finalBatchPath -Content $newBatchContent -UseBOM $true

        # 验证换行符
        Show-Debug "验证批处理文件格式..."
        if (-not (Test-TextFileFormat -Path $finalBatchPath)) {
            return
        }
    
        Show-Success "任务生成成功！"
        Write-Host ''
        
        Write-Host ("─" * 50)
        
        Show-Info "批处理文件使用说明："
        Write-Host "1. 直接运行该 encode_task_final.bat 以开始编码。"
        Write-Host "2. 只要编码工具不变，就可以保留 encode_template.bat，"
        Write-Host "   以便下次编码跳过步骤 2，直接在本步骤导入 encode_template.bat"
        Write-Host "3. 你可以手动更改 encode_template.bat 中的命令来切换上下游编码工具链"
        Write-Host ("─" * 50)
    }
    catch { Show-Error $_ }
    pause
}
#endregion

try { Main }
catch {
    Show-Error $_
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}