<#
.SYNOPSIS
    视频编码任务生成器
.DESCRIPTION
    生成用于视频编码的批处理文件，支持多种编码工具链组合，先前步骤已经录入所有上下游程序路径。本地化由繁化姬實現：https://zhconvert.org 
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# 加载共用代码
. "$PSScriptRoot\Common\Core.ps1"

# 需要结合视频数据统计的参数，注意管道参数已经在先前脚本完成，这里不写
$x264Params = [PSCustomObject]@{
    FPS = "" # 丢帧帧率用如 24000/1001 的字符串
    Resolution = ""
    TotalFrames = ""
    RAWCSP = "" # 位深、色彩空间
    Keyint = ""
    RCLookahead = ""
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
    SEICSP = ""
    PME = ""
    Pools = ""
    BaseParam = ""
    Input = "--input -"
    Output = ""
    OutputExtension = ".hevc"
}
$svtav1Params = [PSCustomObject]@{
    FPS = "" # 丢帧帧率用 --fps-num --fps-denom 而不是 --fps
    RAWCSP = "" # --color-format --input-depth
    Keyint = ""
    Resolution = ""
    TotalFrames = ""
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
}

function Get-EncodeOutputName {
    Param([Parameter(Mandatory=$true)][string]$pickOps)
    $encodeOutputFileName = $null

    switch ($pickOps) {
        a {
            Show-Info "选择文件以拷贝文件名..."
            do {
                $selection = Select-File -Title "选择文件以拷贝文件名"
                if (-not $selection) {
                    if ((Read-Host "未选中文件，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                        exit 1
                    }
                }
            }
            while (-not $selection)
            $fileNameTestResult = Test-FilenameValid($selection)
            return [io.path]::GetFileNameWithoutExtension($selection)
        }
        b {
            Show-Info "填写除后缀外的文件名..."
            Show-Warning " 两个方括号间必须用字符隔开"
            Show-Warning " 不要输入包括货币符、换行符的特殊符号"
            do {
                $encodeOutputFileName = Read-Host "填写除后缀外的文件名"
                $fileNameTestResult = Test-FilenameValid($encodeOutputFileName)
                if ((-not $fileNameTestResult) -or [string]::IsNullOrWhiteSpace($encodeOutputFileName)) {
                    if ((Read-Host "文件名含特殊字符或只有空值，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                        exit 1
                    }
                }
            }
            while ((-not $fileNameTestResult) -or [string]::IsNullOrWhiteSpace($encodeOutputFileName))
        }
        default {
            Show-Warning "未选择有效选项，返回空文件名"
            return ""
        }
    }
    Show-Success "导出文件名：$encodeOutputFileName"
    return $encodeOutputFileName
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

# 生成管道上游程序导入、下游程序导出命令（管道命令已经在先前脚本中写完，目录不存在则自动创建）
function Get-EncodingIOArgument {
    Param (
        [ValidateSet(
            'ffmpeg',
            'vspipe','vs',
            'avs2yuv','avsy','a2y',
            'avs2pipemod','avsp','a2p',
            'svfi','one_line_shot_args','olsarg','olsa','ols',
            'x264','h264','avc',
            'x265','h265','hevc',
            'svt-av1','svtav1','ivf'
        )][Parameter(Mandatory=$true)]$program,
        [string]$source, # 导入路径到文件（带或不带引号）
        [bool]$isImport = $true,
        [string]$outputFilePath, # 导出目录，不用于导入
        [string]$outputFileName, # 导出文件名，不用于导入
        [string]$outputExtension
    )
    # 隔行扫描相关参数
    $interlacedArg = ""
    if ($script:interlacedArgs.isInterlaced) {
        switch ($program) {
            # avs2pipemod: y4mp (progressive), y4mt (tff), y4mb (bff)
            { $_ -in @('avs2pipemod', 'avsp', 'a2p') } {
                $interlacedArg =
                    if ($script:interlacedArgs.isTFF) { "-y4mt" }
                    else { "-y4mb" }
            }
            { $_ -in @('x264', 'h264', 'avc') } {
                # x264: --tff, --bff
                $interlacedArg =
                    if ($script:interlacedArgs.isTFF) { "--tff" }
                    else { "--bff" }
            }
            { $_ -in @('x265', 'h265', 'hevc') } {
                # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
                $interlacedArg =
                    if ($script:interlacedArgs.isTFF) { "--interlace 1" }
                    else { "--interlace 2" }
            }
            # 其它程序忽略隔行扫描参数
        }
    }

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
    
    # 路径加引号（$quoteInput 已定义；勿删参数括号，否则 $outputExtension 会丢）
    $quotedOutput = Get-QuotedPath ($combinedOutputPath+$outputExtension)
    # 源扩展名拦截
    $sourceExtension = [System.IO.Path]::GetExtension($source)

    # 生成管道上游导入与下游导出参数
    if ($isImport) { # 导入模式
        switch -Wildcard ($program) {
            'ffmpeg' { 
                return "-i $quotedInput"
            }
            { $_ -in @('svfi', 'one_line_shot_args', 'ols', 'olsa') } { 
                return "--input $quotedInput"
            }
            # $sourceCSV.sourcePath 只有 .vpy 或 .avs（一个源），然而先前步骤允许选择多种上游程序
            # 因此必然会出现 .vpy 脚本输入出现在 AVS 程序，或反过来的情况
            # 尽管“自动生成占位脚本”功能会同时提供 .vpy 和 .avs 脚本，但用户选择输入自定义脚本就不会做这一步
            # 这个问题需要通过修改源的扩展名来缓解，但默认修改文件名后的源一定不存在，此时只警告用户然后继续
            { $_ -in @('vspipe', 'vs') } {
                if ($sourceExtension -ne '.vpy') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".vpy")
                    Show-Warning "vspipe 线路缺乏 .vpy 脚本源，尝试匹配新路径: $(Split-Path $newSource -Leaf)"
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "已成功切换源到 $newSource"
                        }
                    }
                    else {
                        Show-Warning "源 $newSource 不存在，vspipe 线路的导入需手动纠正"
                    }
                }
                # 返回输入路径和隔行扫描参数（avs2pipemod 线路下自动提供 $interlacedArg）
                if ($interlacedArg -ne "") {
                    return "$quotedInput $interlacedArg"
                }
                else { return "$quotedInput" }
            }
            { $_ -in @('avs2yuv', 'avsy', 'a2y', 'avs2pipemod', 'avsp', 'a2p') } {
                if ($sourceExtension -ne '.avs') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".avs")
                    Show-Warning ($_ + " 线路缺乏 .avs 脚本源，尝试匹配新路径: $(Split-Path $newSource -Leaf)")
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "已成功切换源到 $newSource"
                        }
                    }
                    else {
                        Show-Warning "源 $newSource 不存在，AviSynth 工具线路的导入需手动纠正"
                    }
                }
                # 返回输入路径和隔行扫描参数（avs2pipemod 线路下自动提供 $interlacedArg）
                if ($interlacedArg -ne "") {
                    return "$quotedInput $interlacedArg"
                }
                else { return "$quotedInput" }
            }
            { $_ -in @('x264', 'h264', 'avc') } {
                # 测试：x264 在 --output 参数前面添加 --tff/bff？
                if ($interlacedArg -ne "") {
                    return "- $interlacedArg"
                }
                else { return "-" }
            }
            { $_ -in @('x265', 'h265', 'hevc') } {
                if ($interlacedArg -ne "") {
                    return "$interlacedArg --input -"
                }
                else { return "--input -" }
            }
            { $_ -in @('svt-av1', 'svtav1', 'ivf') } { # SVT-AV1 从标准输入读取，原生不支持隔行
                return "-i -"
            }
        }
        break
    }
    else { # 导出模式
        switch -Wildcard ($program) {
            { $_ -in @('x264', 'h264', 'avc') } {
                return "--output $quotedOutput"
            }
            { $_ -in @('x265', 'h265', 'hevc') } {
                return "--output $quotedOutput"
            }
            { $_ -in @('svt-av1', 'svtav1', 'ivf') } {
                return "-b $($quotedOutput)"
            }
            default {
                throw "未识别的导出程序：$program"
            }
        }
    }
    throw "无法为程序 $program 生成 IO 参数"
}

# 获取基础参数，注意输入的“ - ”必须放在最后，需要确保不和 --output 参数构建冲突
function Get-x264BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserFGO
    )

    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableFGO = $false
    if ($askUserFGO -and -not $isHelp) {
        Write-Host ""
        Write-Host " 少数修改版（Mod）x264 支持基于高频信息量的率失真优化（Film Grain Optimization）" -ForegroundColor Cyan
        Write-Host " 用 x264.exe --fullhelp | findstr fgo 检测 --fgo 参数是否被支持" -ForegroundColor DarkGray
        if ((Read-Host " 输入 'y' 以启用 --fgo（提高画质），或 Enter 以禁用（不支持或无法确定则禁）") -match '^[Yy]$') {
            $enableFGO = $true
            Show-Info "启用 x264 参数 --fgo"
        }
        else { Show-Info "不用 x264 参数 --fgo" }
    }
    elseif (-not $isHelp) {
        Write-Host " 已跳过 --fgo 请柬..."
    }
    $fgo10 = if ($enableFGO) {" --fgo 10"} else {""}
    $fgo15 = if ($enableFGO) {" --fgo 15"} else {""}

    $default = if ($script:interlacedArgs.isInterlaced) {
        ("--bframes 14 --b-adapt 2 --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightp 0 --weightb --min-keyint 5 --ref 3 --crf 18 --chroma-qp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22" + $fgo10)
    }
    else {
        ("--bframes 14 --b-adapt 2 --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 5 --ref 3 --crf 18 --chroma-qp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22" + $fgo10)
    }
    
    switch ($pickOps) {
        # 通用 General Purpose，bframes 14
        a {return $default}
        # 素材 Stock Footage，bframes 12
        b {return ("--partitions all --bframes 12 --b-adapt 2 --me esa --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 1 --ref 3 --crf 16 --tune grain --trellis 2" + $fgo15)}
        helpzh {
            Write-Host ""
            Write-Host " 选择 x264 自定义预设——[a：通用 | b：剪辑素材]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
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
    Param ([Parameter(Mandatory=$true)]$pickOps)
    # TODO：添加 DJATOM? Mod 的深度自定义 AQ
    # $isHelp = $pickOps -in @('helpzh', 'helpen')
    $default = "--high-tier --preset slow --me umh --subme 5 --weightb --aq-mode 4 --bframes 5 --ref 3"

    switch ($pickOps) {
        # 通用 General Purpose，bframes 5
        a {return $default}
        # 录像 Movie，bframes 8
        b {return "--high-tier --ctu 64 --tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --rect --tskip --tskip-fast --me star --weightb --ref 4 --max-merge 5 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --b-intra --crf 21.8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1.1 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3"} 
        # 素材 Stock Footage，bframes 7
        c {return "--high-tier --ctu 32 --tskip --me star --max-merge 5 --early-skip --b-intra --no-open-gop --min-keyint 1 --ref 3 --fades --bframes 7 --b-adapt 2 --crf 17 --crqpoffs -3 --cbqpoffs -2 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --splitrd-skip --deblock -1:-1 --tune grain"}
        # 动漫 Anime，bframes 16
        d {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --tskip --tskip-fast --me umh --weightb --max-merge 5 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --deblock -1:0 --limit-sao --sao-non-deblock"}
        # 穷举法 Exhausive
        e {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 4 --limit-tu 1 --rect --amp --tskip --me star --weightb --max-merge 5 --ref 3 --no-open-gop --min-keyint 1 --fades --bframes 16 --b-adapt 2 --b-intra --crf 18.1 --crqpoffs -5 --cbqpoffs -2 --ipratio 1.67 --pbratio 1.33 --cu-lossless --psy-rdoq 2.5 --rdoq-level 2 --hevc-aq --aq-strength 1.4 --qg-size 8 --rd 5 --limit-refs 0 --rskip 2 --rskip-edge-threshold 3 --no-cutree --psy-rd 1.5 --rdpenalty 2 --deblock -2:-2 --limit-sao --sao-non-deblock --selective-sao 1"}
        helpzh {
            Write-Host ""
            Write-Host " 选择 x265 自定义预设——[a：通用 | b：录像 | c：剪辑素材 | d：动漫 | e：穷举法]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
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
        [switch]$askUserDLF
    )
    
    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableDLF2 = $false
    Write-Host ""
    if ($askUserDLF -and (-not $isHelp) -and ($pickOps -ne 'b')) {
        Write-Host " Get-svtav1BaseParam：少数修改版 SVT-AV1 编码器（如 SVT-AV1-Essential）支持高精度去块滤镜 --enable-dlf 2"  -ForegroundColor Cyan
        Write-Host " 用 SvtAv1EncApp.exe --help | findstr enable-dlf 即可检测`'2`'是否受支持" -ForegroundColor DarkGray
        if ((Read-Host " 输入 'y' 以启用 --enable-dlf 2（提高画质），或 Enter 使用常规去块滤镜（不支持或无法确定则禁）") -match '^[Yy]$') {
            $enableDLF2 = $true
            Show-Info "启用了 SVT-AV1 参数 --enable-dlf 2"
        }
        else { Show-Info "启用 SVT-AV1 参数 --enable-dlf 1" }
    }
    elseif (-not $isHelp) {
        Write-Host " 已跳过 --enable-dlf 2 请柬..."
    }
    $deblock = if ($enableDLF2) {"--enable-dlf 2"} else {"--enable-dlf 1"}

    $default = ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 --crf 30 --enable-qm 1 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 6 --progress 1 " + $deblock)
    switch ($pickOps) {
        # 画质 Quality
        a {return $default}
        # 压缩 Compression
        b {return ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 --crf 30 --sharpness 4 --progress 1 " + $deblock)}
        # 速度 Speed
        c {return "--preset 2 --scd 1 --scm 0 --enable-tf 2 --tf-strength 2 --crf 30 --tune 0 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 4 --progress 1"}
        helpzh {
            Write-Host ""
            Write-Host " 选择 SVT-AV1 自定义预设——[a：画质优先 | b：压缩优先 | c：速度优先]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
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
            break;
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

# 使用 Y4M 管道时能够自动获取 profile 参数，RAW 管道则直接指定 CSP、分辨率等参数即可，除非要实现硬件兼容才指定 Profile
function Get-x265SVTAV1Profile {
    # 注：由于 HEVC 本就支持有限的 CSP，因此其它 CSP 值皆为 else
    # 注：NV12：8bit 2 平面 YUV420；NV16：8bit 2 平面 YUV422
    Param (
        [Parameter(Mandatory=$true)]$CSVpixfmt, # i.e., yuv444p12le, yuv422p, nv12
        [bool]$isIntraOnly=$false,
        [bool]$isSVTAV1=$false
    )
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''

    # 解析色度采样格式和位深
    $chromaFormat = $null
    $depth = 8  # 默认 8bit
    
    # 解析位深
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    # elseif ($pixfmt -eq 'nv12' -or $pixfmt -eq 'nv16') {
    #     $depth = 8 # 同默认，判断直接注释
    # }
    
    # 解析 HEVC 色度采样
    if ($pixfmt -match '^yuv420' -or $pixfmt -eq 'nv12') {
        $chromaFormat = 'i420'
    }
    elseif ($pixfmt -match '^yuv422' -or $pixfmt -eq 'nv16') {
        $chromaFormat = 'i422'
    }
    elseif ($pixfmt -match '^yuv444') {
        $chromaFormat = 'i444'
    }
    elseif ($pixfmt -match '^(gray|yuv400)') {
        $chromaFormat = 'gray'
    }
    else { # 默认 4:2:0
        $chromaFormat = 'i420'
        Show-Warning "未知像素格式：$pixfmt，将使用默认值（4:2:0 8bit）"
    }

    # 解析 SVT-AV1 色度采样
    # - Main：        4:0:0（gray）-4:2:0，全采样最高 10bit
    # - High：        额外支持 4:4:4 采样
    # - Professional：额外支持 4:2:2 采样，全采样最高 12bit
    $svtav1Profile = 0 # 默认 main
    switch ($chromaFormat) {
        'i444' {
            if ($depth -eq 12) { $svtav1Profile = 2 } # Professional
            else { $svtav1Profile = 1 } # High
        }
        'i422' { $svtav1Profile = 2 } # Professional only
        'gray' {
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 } # Main（保守）
        }
        default { # i420
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 }
        }
    }

    # 检查位深
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "视频编码可能不支持 $depth bit 位深" # $depth = 8
    }

    # 检查 x265 实际支持的 profile 范围：
    # 8bit：main, main-intra，main444-8, main444-intra
    # 10bit：main10, main10-intra，main422-10, main422-10-intra，main444-10, main444-10-intra
    # 12 bit：main12, main12-intra，main422-12, main422-12-intra，main444-12, main444-12-intra
    $profileBase = ""
    $inputCsp = ""

    # 根据色度格式和位深度返回对应的 profile
    if ($isSVTAV1) {
        return ("--profile " + $svtav1Profile)
    }

    switch ($chromaFormat) {
        'i422' {
            if ($depth -eq 8) {
                Write-Warning "x265 不支持 main422-8，降级为 main (4:2:0)"
                $profileBase = "main"
            }
            else {
                $profileBase = "main422-$depth"
            }
        }
        'i444' { # 特殊：8-bit 4:4:4 的 intra profile 是 main444-intra，不是 main444-8-intra
            if ($depth -eq 8) {
                $profileBase = "main444-8"
            }
            else {
                $profileBase = "main444-$depth"
            }
        }
        'gray' { # 灰度图像可以用 main/main10/main12
            $inputCsp = "--input-csp i400"
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
        default { # i420 和其他
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
    }

   # 若使用 intra-only 编码，则添加 -intra 后缀
    if ($isIntraOnly) {
        if ($profileBase -eq "main444-8") {
            $profileBase = "main444-intra"
        }
        else {
            $profileBase = "$profileBase-intra"
        }
    }

    $result = "--profile $profileBase"
    if ($inputCsp) { $result += " $inputCsp" }
    return $result
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
        throw "参数异常，一次只能给一个编码器配置参数"
    }

    # 注意：值可以是“24000/1001”的字符串，需要处理（得到 23.976d）
    [double]$fps = ConvertTo-Fraction $fpsString

    $userSecond = $null # 用户指定秒
    if ($askUser) {
        if ($isx264) {
            Write-Host ""
            Show-Info "请指定 x264 的关键帧最大间隔秒（正整数，非帧数）"
        }
        elseif ($isx265) {
            Write-Host ""
            Show-Info "请指定 x265 的关键帧最大间隔秒数（正整数，非帧数）"
        }
        elseif ($isSVTAV1) {
            Write-Host ""
            Show-Info "请指定 SVT-AV1 的关键帧最大间隔秒数（正整数，非帧数）"
        }
        else {
            throw "未指定要配置最大关键帧间隔参数的编码器，无法执行"
        }
        
        $userSecond = $null
        do { # 默认多轨剪辑的关键帧间隔相当于 N 个视频轨的关键帧间隔之和，但实际解码占用涨跌非线性，所以设为两倍
            Write-Host " 1. 分辨率高于 2560x1440 则偏左选一格"
            Write-Host " 2. 画面内容简单，平面居多则偏右选一格"
            $userSecond =
                Read-Host " 大致范围：[低功耗/多轨剪辑：6-7 秒| 一般：8-10 秒| 高：11-13+ 秒]"
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

function Get-RateControlLookahead { # 1.8*fps
    Param (
        [Parameter(Mandatory=$true)]$fpsString,
        [Parameter(Mandatory=$true)][int]$bframes,
        [double]$second = 1.8
    )
    try {
        $frames = [math]::Round(((ConvertTo-Fraction $fpsString) * $second))
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
    Param (
        [Parameter(Mandatory=$true)]$CSVw,
        [Parameter(Mandatory=$true)]$CSVh
    )
    [int]$res = 0
    try {
        $width = [int]$CSVw
        $height = [int]$CSVh
        $res = $width * $height
    }
    catch {
        throw "无法解析视频分辨率：宽度=$CSVw, 高度=$CSVh"
    }
    if ($res -ge 8294400) { return "--merange 56" } # >=3840x2160
    elseif ($res -ge 3686400) { return "--merange 52" } # >=2560*1440
    elseif ($res -ge 2073600) { return "--merange 48" } # >=1920*1080
    elseif ($res -ge 921600) { return "--merange 40" } # >=1280*720
    else { return "--merange 36" }
}

function Get-x265Subme { # 24fps=3, 48fps=4, 60fps=5, ++=6
    Param ([Parameter(Mandatory=$true)]$fpsString, [bool]$getInteger=$false)
    $encoderFPS = ConvertTo-Fraction $fpsString
    $subme = 6
    if ($encoderFPS -lt 25) {$subme = 3}
    elseif ($encoderFPS -lt 49) {$subme = 4}
    elseif ($encoderFPS -lt 61) {$subme = 5}

    if ($getInteger) { return $subme }
    return ("--subme " + $subme)
}

# 核心数大于 36 时开启并行动态搜索
function Get-x265PME {
    if ([int](wmic cpu get NumberOfCores)[2] -gt 36) {
        return "--pme"
    }
    return ""
}

# 指定运行于特定 NUMA 节点，索引从 0 开始数；输出例：--pools -,+（双路下使用二号节点）
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
        Show-Info "检测到安装了 1 颗处理器，忽略 x265 参数 --pools"
        return ""
    }
}

# 问题：总帧数可以存在于 .I、.J、.AA-AJ 等范围，但位置随机（假值一定为 0）
function Get-FrameCount {
    Param (
        [Parameter(Mandatory=$true)]$ffprobeCSV, # 完整 CSV 对象
        [bool]$isSVTAV1=$false
    )
    
    # 定义所有可能包含总帧数的列名（I, AA, AB, AC, AD, AE, AF, AG, AH, AI, AJ）
    $frameCountColumns = @();
    # VOB 格式仅位于 J，同时 AA 等位置有无关数值，不可试
    if ($script:interlacedArgs.isVOB) {
        $frameCountColumns = @('J');
    }
    else {
        $frameCountColumns =
            @('I') + (65..74 | ForEach-Object { [char]$_ } | ForEach-Object { "A$_" })
    }

    # 遍历检查列，找到首个非零值
    foreach ($column in $frameCountColumns) {
        $frameCount = $ffprobeCSV.$column
        
        # 检查是否为数字且大于 0
        if ($frameCount -match "^\d+$" -and [int]$frameCount -gt 0) {
            if ($isSVTAV1) { 
                return "-n " + $frameCount 
            }
            return "--frames " + $frameCount
        }
    }
    
    # 如果所有列都没有找到有效帧数，返回空字符串
    return ""
}

function Get-InputResolution {
    Param (
        [Parameter(Mandatory=$true)][int]$CSVw,
        [Parameter(Mandatory=$true)][int]$CSVh,
        [bool]$isSVTAV1=$false
    )
    if ($isSVTAV1) {
        return "-w $CSVw -h $CSVh"
    }
    return "--input-res ${CSVw}x${CSVh}"
}

# 添加对 SVT-AV1 的丢帧帧率支持，丢帧帧率直接保留字符串
function Get-FPSParam {
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)]
        [ValidateSet("ffmpeg","x264","avc","x265","hevc","svtav1","SVT-AV1")]
        [string]$Target
    )

    # SVT-AV1 需要特殊处理：使用 --fps-num 和 --fps-denom 分开写
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
                default  { 
                    # 对于其他值，使用整数
                    try {
                        $intFps = [Math]::Round([double]$fpsString)
                    }
                    catch [System.Management.Automation.RuntimeException] {
                        throw "Get-FPSParam：输入了无法被转换为数字的帧率参数 fpsString"
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
        [Parameter(Mandatory=$true)]$CSVColorMatrix,
        [Parameter(Mandatory=$true)]$CSVTransfer,
        [Parameter(Mandatory=$true)]$CSVPrimaries,
        [ValidateSet("avc","x264","hevc","x265","av1","svtav1")][string]$Codec
    )
    $Codec = $Codec.ToLower()
    $result = @()
    
    # 处理 ColorMatrix
    if (($Codec -eq 'avc' -or $Codec -eq 'x264')) {
        if (($CSVColorMatrix -eq "unknown") -or ($CSVColorMatrix -eq "bt2020nc")) {
            $result += "--colormatrix undef" # x264 不写 unknown
        }
        else { # fcc，bt470bg，smpte170m，smpte240m，GBR，YCgCo，bt2020c，smpte2085，chroma-derived-nc，chroma-derived-c，ICtCp
            $result += "--colormatrix $CSVColorMatrix"
        }
    }
    elseif (($Codec -eq 'hevc') -or ($Codec -eq 'x265')) {
        if ($CSVColorMatrix -eq "bt2020nc") {
            $result += "--colormatrix unknown"
        }
        else { # 同 x264
            $result += "--colormatrix $CSVColorMatrix"
        }

    }
    elseif (($Codec -eq "av1") -or ($Codec -eq "svtav1")) {
        $c = switch ($CSVColorMatrix) {
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
                Show-Warning "未知矩阵格式：$CSVColorMatrix，使用默认（bt709）"
                1
            }
        }
        $result += "--matrix-coefficients $c"
    }
    
    # 处理 Transfer
    if (($Codec -eq 'avc' -or $Codec -eq 'x264')) {
        if ($CSVTransfer -eq "unknown") {
            # bt470m，bt470bg，smpte170m，smpte240m，linear，log100，log316，iec61966-2-4，bt1361e，iec61966-2-1，bt2020-10，bt2020-12，smpte2084，smpte428，arib-std-b67
            $result += "--transfer undef"
        }
        else {
            $result += "--transfer $CSVTransfer"
        }
    }
    elseif (($Codec -eq 'hevc') -or ($Codec -eq 'x265')) {
        $result += "--transfer $CSVTransfer"
    }
    elseif (($Codec -eq "av1") -or ($Codec -eq "svtav1")) {
        $t = switch ($CSVTransfer) {
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
                Show-Warning "未知传输特质：$CSVTransfer，使用默认（bt709）"
                1
            }
        }
        $result += "--transfer-characteristics $t"
    }

    # 处理 Color Primaries
    if (($Codec -eq 'avc') -or ($Codec -eq 'x264')) {

        if (($CSVPrimaries -eq "unknown") -or ($CSVPrimaries -eq "unspec")) {
            $result += "--colorprim undef"
        }
        else {
            $result += "--colorprim $CSVPrimaries"
        }

    }
    elseif (($Codec -eq 'hevc') -or ($Codec -eq 'x265')) {

        if (($CSVPrimaries -eq "unknown") -or ($CSVPrimaries -eq "unspec")) {
            $result += "--colorprim unknown"
        }
        else {
            $result += "--colorprim $CSVPrimaries"
        }

    }
    elseif (($Codec -eq "av1") -or ($Codec -eq "svtav1")) {

        $p = switch ($CSVPrimaries) {
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
                Show-Warning "未知三原色：$CSVPrimaries，使用默认（bt709）"
                1
            }
        }

        $result += "--color-primaries $p"
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
        )][Parameter(Mandatory=$true)]$CSVpixfmt)
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''
    return "-pix_fmt " + $pixfmt
}

function Get-RAWCSPBitDepth {
    Param (
        [Parameter(Mandatory=$true)]$CSVpixfmt,
        [bool]$isEncoderInput=$true,
        [bool]$isAvs2YuvInput=$false,
        [bool]$isSVTAV1=$false,
        [bool]$isAVSPlus=$false
    )
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''

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
    if ($pixfmt -match '^yuv420') {
        $chromaFormat = 'i420'
    }
    elseif ($pixfmt -match '^yuv422') {
        $chromaFormat = 'i422'
    }
    elseif ($pixfmt -match '^nv12') {
        $chromaFormat = 'nv12'
    }
    elseif ($pixfmt -match '^nv16') {
        $chromaFormat = 'nv16'
    }
    elseif ($pixfmt -match '^yuv444') {
        $chromaFormat = 'i444'
    }
    elseif ($pixfmt -match '^(gray|yuv400)') {
        $chromaFormat = 'i400'
    }
    else { # 默认 4:2:0
        if ($isEncoderInput) {
            $chromaFormat = 'i420'
            Show-Warning "[编码器] 未知像素格式：$pixfmt，将使用默认值（i420）"
        }
        else {
            $chromaFormat = 'AUTO'
            Show-Warning "[AviSynth] 未知像素格式：$pixfmt，将使用默认值（AUTO）"
        }
    }

    if ($isEncoderInput) {
        if ($isSVTAV1) { # --color-format，--input-depth
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
    }
    elseif ($isAvs2YuvInput) {
        # avs2yuv 0.30 放弃了对 AviSynth 的支持（仅AviSynth+），因此 -csp 参数被取消
        # avs2yuv 0.30 在测试中一直没有导出 Y4M 流，因此放弃支持，用更老的 0.26 版
        $cspMap = @{
            '420' = 'i420'
            '422' = 'i422'
            '444' = 'i444'
            '400' = 'i400'
        }
        $csp = $cspMap[$chromaFormat]
        if (-not $csp) { $csp = 'AUTO' }
        if ($isAVSPlus) {
            return "-depth $depth"
        }
        else {
            return "-csp $csp -depth $depth"
        }
    }
    return ""
}

# 由于自动生成的脚本源存在，因此文件名会变成 "blank_vs_script/blank_avs_script" 而非视频文件名。若匹配到则消除默认（Enter）选项
function Get-IsPlaceHolderSource {
    Param([Parameter(Mandatory=$true)][string]$defaultName)
    return [string]::IsNullOrWhiteSpace($defaultName) -or
        $defaultName -match '^(blank_.*|.*_script)$' -or
        -not (Test-Path -LiteralPath $sourceCSV.SourcePath)
}

# 简单通过排除法获取管道类型，因此如果添加只支持 RAW YUV 管道的上游工具需要修改
function Get-IsRAWSource ([string]$validateUpstreamCode) {
    return $validateUpstreamCode -eq 'e'
}

# 尽快判断文件为 VOB 格式（格式判断已被先前脚本确定），影响后续大量参数的 $ffprobeCSV 变量读法
function Set-IsVOB {
    [Parameter(Mandatory=$true)]
    [string]$ffprobeCsvPath # 用于检查文件名是否含 _vob
    if ([string]::IsNullOrWhiteSpace($ffprobeCsvPath)) {
        throw "Set-IsVOB：ffprobeCsvPath 参数为空，无法判断"
    }
    $script:interlacedArgs.isVOB = $ffprobeCsvPath -like "*_vob*"
}

function Set-InterlacedArgs {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$fieldOrderOrIsInterlacedFrame, # VOB：$ffprobe.H；其它：$ffprobeCsv.J
        [Parameter(Mandatory=$true)]
        [string]$topFieldFirst # $ffprobeCsv.K
    )
    # 初始化
    $script:interlacedArgs.isInterlaced = $false
    $script:interlacedArgs.isTFF = $false

    # 处理 VOB 格式
    if ($script:interlacedArgs.isVOB) {
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
            { [string]::IsNullOrWhiteSpace($fieldOrder) } {
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
    else {  # 非 VOB 格式，解析 interlaced_frame (0/1)
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
        $tff = $topFieldFirst.Trim()
        
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
    
    # 调试输出
    Show-Debug "Set-InterlacedArgs：隔行扫描：$($script:interlacedArgs.isInterlaced), 上场优先：$($script:interlacedArgs.isTFF)"
}

function Main {
    Show-Border
    Write-Host "参数计算与批处理注入工具" -ForegroundColor Cyan
    Show-Border
    Write-Host ""

    # 1. 自动查找最新的 ffprobe CSV，并读取视频信息
    $ffprobeCsvPath = 
        Get-ChildItem -Path $Global:TempFolder -Filter "temp_v_info*.csv" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 | 
        ForEach-Object { $_.FullName }

    if ($null -eq $ffprobeCsvPath) {
        Show-Error "未找到 ffprobe 生成的 CSV 文件；请运行步骤 3 脚本以补全"
        return
    }

    # 2. 查找源信息 CSV
    $sourceInfoCsvPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    if (-not (Test-Path $sourceInfoCsvPath)) {
        Show-Error "未找到专用信息 CSV 文件；请运行步骤 3 脚本以补全"
        return
    }

    Show-Info "正在读取 ffprobe 信息：$(Split-Path $ffprobeCsvPath -Leaf)..."
    Show-Info "正在读取源专用信息：$(Split-Path $sourceInfoCsvPath -Leaf)..."

    $ffprobeCSV =
        Import-Csv $ffprobeCsvPath -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA,AB,AC,AD,AE,AF,AG,AH,AI,AJ
    $sourceCSV =
        Import-Csv $sourceInfoCsvPath -Header SourcePath,UpstreamCode,Avs2PipeModDllPath,SvfiConfigInput,SvfiTaskId

    # 验证 CSV 数据
    if (-not $sourceCSV.SourcePath) { # 直接验证 CSV 项存在，不需要添加引号
        Show-Error "temp_s_info CSV 数据不完整，请重运行步骤 3 脚本"
        return
    }

    # 隔行扫描源支持
    # ffmpeg、vspipe、avs2yuv、svfi：忽略
    # avs2pipemod: y4mp, y4mt, y4mb (progressive, tff, bff)
    # x264: --tff, --bff
    # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
    # SVT-AV1: 原生不支持，报错并退出
    Show-Info "正在区分隔行扫描格式..."
    Set-IsVOB -ffprobeCsvPath $ffprobeCsvPath
    Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $ffprobeCSV.H -topFieldFirst $ffprobeCSV.J

    # 计算并赋值给对象属性
    Show-Info "正在优化编码参数（Profile、分辨率、动态搜索范围等）..."
    # $x265Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $false
    # $svtav1Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $true
    $x265Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C
    $svtav1Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C -isSVTAV1 $true
    $x265Params.MERange = Get-x265MERange -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C

    # Show-Debug "矩阵格式：$($ffprobeCSV.E)；传输特质：$($ffprobeCSV.F)；三原色：$($ffprobeCSV.G)"
    $svtav1Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec svtav1
    $x265Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x265
    $x264Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x264

    # VOB 格式的帧率信息位于 I
    if ($script:interlacedArgs.isVOB) {
        $ffmpegParams.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target ffmpeg
        $svtav1Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target svtav1
        $x265Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target x265
        $x264Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target x264

        $x265Params.Subme = Get-x265Subme -fpsString $ffprobeCSV.I
        [int]$x265SubmeInt = Get-x265Subme -fpsString $ffprobeCSV.I -getInteger $true
        Show-Debug "VOB 源的帧率为：$(ConvertTo-Fraction $ffprobeCSV.I)"
        $x264Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes 250 -askUser -isx264
        $x265Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes $x265SubmeInt -askUser -isx265
        $svtav1Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes 999 -askUser -isSVTAV1
        
        $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.I -bframes 250 # hack：借 bframes 做出建议最大值
        $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.I -bframes $x265SubmeInt
    }
    else {
        $ffmpegParams.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target ffmpeg
        $svtav1Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target svtav1
        $x265Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target x265
        $x264Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target x264

        $x265Params.Subme = Get-x265Subme -fpsString $ffprobeCSV.H
        [int]$x265SubmeInt = Get-x265Subme -fpsString $ffprobeCSV.H -getInteger $true
        Show-Debug "源视频的帧率为：$(ConvertTo-Fraction $ffprobeCSV.H)"
        $x264Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes 250 -askUser -isx264
        $x265Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes $x265SubmeInt -askUser -isx265
        $svtav1Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes 999 -askUser -isSVTAV1
        $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.H -bframes 250
        $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.H -bframes $x265SubmeInt
    }

    # VOB 的总帧数信息位于 J
    $x265Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $x264Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $svtav1Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $true
    # x265 线程管理
    $x265Params.PME = Get-x265PME
    $x265Params.Pools = Get-x265ThreadPool

    # 获取并配置色彩空间格式
    $avs2yuvVersionCode = 'a'
    if ($sourceCSV.UpstreamCode -eq 'c') {
        Write-Host ""
        Show-Info "选择使用的 avs2yuv(64).exe 类型："
        $avs2yuvVersionCode = Read-Host " [默认 Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
    }
    $ffmpegParams.CSP = Get-ffmpegCSP -CSVpixfmt $ffprobeCSV.D
    $svtav1Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $true
    $x265Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $x264Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $avsyuvParams.CSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $false -isAvs2YuvInput $true -isSVTAV1 $false -isAVSPlus ($avs2yuvVersionCode -eq 'a')

    # Avs2PipeMod 需要的 DLL
    $quotedDllPath = Get-QuotedPath $sourceCSV.Avs2PipeModDllPath
    $avsmodParams.DLLInput = "-dll $quotedDllPath"

    # SVFI 需要的配置文件以及 Task ID
    if (-not [string]::IsNullOrWhiteSpace($sourceCSV.SvfiConfigInput)) {
        $quotedSvfiConfig = Get-QuotedPath $sourceCSV.SvfiConfigInput
        $olsargParams.ConfigInput = "--config $quotedSvfiConfig --task-id $($sourceCSV.SvfiTaskId)"
        Show-Debug "olsargParams.ConfigInput: $($olsargParams.ConfigInput)"
    }
    else { $olsargParams.ConfigInput = "" }

    Write-Host ""
    Show-Info "配置编码结果导出路径、文件名..."
    $encodeOutputPath = Select-Folder -Description "选择压制结果的导出位置"

    # 1. 获取默认值（从源复制）
    Show-Debug "CSV SourcePath 原文为：$($sourceCSV.SourcePath)"
    
    $defaultName = [io.path]::GetFileNameWithoutExtension($sourceCSV.SourcePath)
    # 由于自动生成的脚本源存在，因此文件名会变成 "blank_vs_script/blank_avs_script" 而非视频文件名
    # 若匹配到这种文件名则消除默认（Enter）选项
    $isPlaceholderSource = Get-IsPlaceHolderSource -defaultName $defaultName
    $encodeOutputFileName = ""
    
    # 使用兼容 PowerShell 5.1 的写法算 displayName
    if (-not $isPlaceholderSource) {
        $encodeOutputFileName = $defaultName
        $displayName =
            if ($defaultName.Length -gt 17) {
                $defaultName.Substring(0, 18) + "..."
            }
            else { $defaultName }
    }
    else { # 警告：文件名里不写冒号
        $displayName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    }

    $encodeOutputNameCode =
        Read-Host " 指定压制结果的文件名——[a：从文件拷贝 | b：手写 | Enter：$displayName]"
    # 确保 if 关键字前后无特殊不可见字符
    if ($encodeOutputNameCode -eq 'a') { # 选择视频源文件
        Show-Info "选择一个文件以拷贝文件名..."
        do {
            $fileForName = Select-File -Title "选择一个文件以拷贝文件名"
            if (-not $fileForName) {
                if ((Read-Host " 未选择文件，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                    return
                }
            }
        }
        while (-not $fileForName)
        # 提取文件名
        $encodeOutputFileName = [io.path]::GetFileNameWithoutExtension($fileForName)
    }
    elseif ($encodeOutputNameCode -eq 'b') { # 手动输入
        $encodeOutputFileName = Read-Host " 请输入文件名（不含后缀）"
    }
    # 默认文件名
    # $displayName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH:mm' 时 $encodeOutputFileName 仍然为空
    if (-not $encodeOutputFileName -or $encodeOutputFileName -EQ "") {
        $encodeOutputFileName = $displayName
    }
    if (Test-FilenameValid -Filename $encodeOutputFileName) {
        Show-Success "最终文件名：$encodeOutputFileName"
    }
    else {
        Show-Error "文件名 $encodeOutputFileName 违反了 Windows 命名规范，请在生成的批处理中手动更改，否则编码会在最后的导出步骤失败"
    }

    # 由于默认给所有编码器生成参数，因此仅通知兼容性问题，而不是拒绝执行
    if ($script:interlacedArgs.isInterlaced -and
        $program -in @('x265', 'h265', 'hevc', 'svt-av1', 'svtav1', 'ivf')) {
        Show-Info "Get-EncodingIOArgument：SVT-AV1 原生不支持隔行扫描、x265 的隔行扫描编码是实验性功能（官方版）"
        Show-Info ("转逐行与 IVTC 滤镜教程：" + $script:interlacedArgs.toPFilterTutorial)
        Write-Host ""
    }

    Show-Info "生成管道上下游程序的 IO 参数 (Input/Output)..."
    # 1. 管道上游程序输入
    # 管道连接符由先前脚本生成的批处理控制，这里不写
    $ffmpegParams.Input = Get-EncodingIOArgument -program 'ffmpeg' -isImport $true -source $sourceCSV.SourcePath
    $vspipeParams.Input = Get-EncodingIOArgument -program 'vspipe' -isImport $true -source $sourceCSV.SourcePath
    $avsyuvParams.Input = Get-EncodingIOArgument -program 'avs2yuv' -isImport $true -source $sourceCSV.SourcePath
    $avsmodParams.Input = Get-EncodingIOArgument -program 'avs2pipemod' -isImport $true -source $sourceCSV.SourcePath
    $olsargParams.Input = Get-EncodingIOArgument -program 'svfi' -isImport $true -source $sourceCSV.SourcePath
    # 2. 管道下游程序（编码器）输入——需要根据隔行扫描判断参数，因此必用 Get-EncodingIOArgument
    $x264Params.Input = Get-EncodingIOArgument -program 'x264' -isImport $true -source $sourceCSV.SourcePath
    $x265Params.Input = Get-EncodingIOArgument -program 'x265' -isImport $true -source $sourceCSV.SourcePath
    $svtav1Params.Input = Get-EncodingIOArgument -program 'svtav1' -isImport $true -source $sourceCSV.SourcePath
    # 3. 管道下游程序输出
    $x264Params.Output = Get-EncodingIOArgument -program 'x264' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x264Params.OutputExtension
    $x265Params.Output = Get-EncodingIOArgument -program 'x265' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x265Params.OutputExtension
    $svtav1Params.Output = Get-EncodingIOArgument -program 'svtav1' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $svtav1Params.OutputExtension

    Show-Info "构建管道下游（编码器）基础参数.."
    $x264Params.BaseParam = Invoke-BaseParamSelection -CodecName "x264" -GetParamFunc ${function:Get-x264BaseParam} -ExtraParams @{ askUserFGO = $true }
    $x265Params.BaseParam = Invoke-BaseParamSelection -CodecName "x265" -GetParamFunc ${function:Get-x265BaseParam}
    $svtav1Params.BaseParam = Invoke-BaseParamSelection -CodecName "SVT-AV1" -GetParamFunc ${function:Get-svtav1BaseParam} -ExtraParams @{ askUserDLF = $true }

    Show-Info "拼接最终参数字符串..."
    # 这些字符串将直接注入到批处理的 "set 'xxx_params=...'" 中
    # 空参数可能会导致双空格出现，但路径、文件名里也可能有双空格，因此不过滤（-replace "  ", " "）
    # 1. 管道上游工具
    $ffmpegFinalParam = "$($ffmpegParams.FPS) $($ffmpegParams.Input) $($ffmpegParams.CSP)"
    $vspipeFinalParam = "$($vspipeParams.Input)"
    $avsyuvFinalParam = "$($avsyuvParams.Input) $($avsyuvParams.CSP)"
    $avsmodFinalParam = "$($avsmodParams.Input) $($avsmodParams.DLLInput)"
    $olsargFinalParam = "$($olsargParams.Input) $($olsargParams.ConfigInput)"
    # 2. x264（Input 必须放在最末尾）
    $x264FinalParam = "$($x264Params.Keyint) $($x264Params.SEICSP) $($x264Params.BaseParam) $($x264Params.Output) $($x264Params.Input)"
    # 3. x265
    $x265FinalParam = "$($x265Params.Keyint) $($x265Params.SEICSP) $($x265Params.RCLookahead) $($x265Params.MERange) $($x265Params.Subme) $($x265Params.PME) $($x265Params.Pools) $($x265Params.BaseParam) $($x265Params.Input) $($x265Params.Output)"
    # 4. SVT-AV1
    $svtav1FinalParam = "$($svtav1Params.Keyint) $($svtav1Params.SEICSP) $($svtav1Params.BaseParam) $($svtav1Params.Input) $($svtav1Params.Output)"

    $x264RawPipeApdx = "$($x264Params.FPS) $($x264Params.RAWCSP) $($x264Params.Resolution) $($x264Params.TotalFrames)"
    $x265RawPipeApdx = "$($x265Params.FPS) $($x265Params.RAWCSP) $($x265Params.Resolution) $($x265Params.TotalFrames)"
    $svtav1RawPipeApdx = "$($svtav1Params.FPS) $($svtav1Params.RAWCSP) $($svtav1Params.Resolution) $($svtav1Params.TotalFrames)"
    # N. RAW 管道兼容
    if (Get-IsRAWSource -validateUpstreamCode $sourceCSV.UpstreamCode) {
        $x264FinalParam = $x264RawPipeApdx + " " + $x264FinalParam
        $x265FinalParam = $x265RawPipeApdx + " " + $x265FinalParam
        $svtav1FinalParam = $svtav1RawPipeApdx + " " + $svtav1FinalParam
    }

    # 生成 ffmpeg, vspipe, avs2yuv, avs2pipemod 编码任务批处理
    Write-Host ""
    Show-Info "定位先前脚本生成的 encode_single.bat 模板..."
    $templateBatch = $null
    do {
        $templateBatch = Select-File -Title "选择 encode_single.bat 批处理" -BatOnly
        
        if (-not $templateBatch) {
            if ((Read-Host "未选择模板文件，按 Enter 重试，输入 'q' 强制退出") -eq 'q') {
                return
            }
        }
    }
    while (-not $templateBatch)

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
    # 若模板变更，则回退到在 @echo off 后面插入
    $newBatchContent = $batchContent

    # 字样匹配
    $englishAnchor = '(?msi)^REM\s+Parameter\s+examples\b'
    $chineseAnchor = '(?msi)^REM\s+参数示例\b'

    if ($batchContent -match $englishAnchor -or $batchContent -match $chineseAnchor) {
        # 顺序匹配英文模板、中文模板
        if ($batchContent -match $englishAnchor) {
            # 匹配从“REM 参数示例”到（但不包括）“REM 指定命令行”行的内容
            $pattern = '(?msi)^REM\s+Parameter\s+examples\b.*?^(?=REM\s+Specify\s+commandline\b)'
        }
        else {
            # 中文字样（保持兼容性）
            $pattern = '(?msi)^REM\s+参数示例\b.*?^(?=REM\s+指定本次所需编码命令\b)'
        }

        # 替换操作使用 [regex]::Replace 以确保 .NET 正则表达式的行为。
        $newBatchContent = [regex]::Replace($batchContent, $pattern, $paramsBlock)
    }
    else {
        Write-Warning "未在模板中找到参数占位符，将在文件头部追加参数。"
        $lines = [System.IO.File]::ReadAllLines($templateBatch, $Global:utf8BOM)

         # 在第3行（通常是 setlocal 之后）插入
        $insertIndex = 3

        # 使用 CRLF 或 LF 分割 paramsBlock 以安全地获取行。
        $paramsLines = [System.Text.RegularExpressions.Regex]::Split($paramsBlock, "\r?\n")

        # 使用插入的参数创建新行
        $newLines = $lines[0..($insertIndex-1)] + $paramsLines + $lines[$insertIndex..($lines.Count-1)]
        $newBatchContent = $newLines -join "`r`n"
    }

    # 保存最终文件
    $finalBatchPath = Join-Path (Split-Path $templateBatch) "encode_task_final.bat"
    Show-Debug "输出文件：$finalBatchPath"
    Write-Host ""
    
    try {
        Confirm-FileDelete $finalBatchPath
        Write-TextFile -Path $finalBatchPath -Content $newBatchContent -UseBOM $true

        # 验证换行符
        Show-Debug "验证批处理文件格式..."
        if (-not (Test-TextFileFormat -Path $finalBatchPath)) {
            return
        }
    
        Show-Success "任务生成成功！直接运行该批处理文件以开始编码。"
        Show-Info "若批处理运行后立即退出，则打开 CMD，运行导出错误到文本的命令，如：`r`n X:\encode_task_final.bat 2>Y:\error.txt"
    }
    catch {
        Show-Error "写入文件失败：$_"
    }
    pause
}

try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}