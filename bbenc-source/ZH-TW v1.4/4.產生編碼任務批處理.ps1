<#
.SYNOPSIS
    影片編碼任務生成器
.DESCRIPTION
    生成用於影片編碼的批處理文件，支持多種編碼工具鏈組合，先前步驟已經輸入所有上下遊程序路徑。在地化由繁化姬實現：https://zhconvert.org 
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# 載入共用代碼
. "$PSScriptRoot\Common\Core.ps1"

# 需要結合影片數據統計的參數，注意管道參數已經在先前腳本完成，這裡不寫
$x264Params = [PSCustomObject]@{
    FPS = "" # 丟幀幀率用如 24000/1001 的字串
    Resolution = ""
    TotalFrames = ""
    RAWCSP = "" # 位深、色彩空間
    Keyint = ""
    RCLookahead = ""
    SEICSP = "" # ColorMatrix、Transfer
    BaseParam = ""
    Input = "-"
    Output = ""
    OutputExtension = ".mp4"
}
$x265Params = [PSCustomObject]@{
    FPS = "" # 丟幀幀率用如 24000/1001 的字串
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
    FPS = "" # 最優實踐：丟幀幀率用 --fps-num --fps-denom 而不是 --fps
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

# 隔行掃描格式支持
$interlacedArgs = [PSCustomObject]@{
    toPFilterTutorial = "https://iavoe.github.io/deint-ivtc-web-tutorial/HTML/index.html"
    isInterlaced = $false
    isTFF = $false
    isVOB = $false
}

function Get-EncodeOutputName {
    Param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [bool]$IsPlaceholder = $false
    )

    # 1. 計算默認檔案名（DefaultName）
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $finalDefaultName = $null
    
    if (-not $IsPlaceholder -and -not [string]::IsNullOrWhiteSpace($defaultNameBase)) {
        $finalDefaultName = $defaultNameBase
    }
    else {
        # 如果是占位符源（自動腳本）或源路徑為空，使用時間戳作為默認名
        # 注意：檔案名中不能包含冒號，因此用 HH-mm
        $finalDefaultName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    }

    # 2. 生成用於顯示的顯示檔案名（DisplayName），過長則截斷
    $displayPrompt = if ($finalDefaultName.Length -gt 18) { 
        $finalDefaultName.Substring(0, 18) + "..." 
    }
    else {  $finalDefaultName  }

    # 3. 交互循環
    while ($true) {
        Write-Host ""
        $inputOp = Read-Host " 指定壓制結果的檔案名——[a：從文件拷貝 | b：手寫 | Enter：$displayPrompt]"

        # 3-1：直接 Enter（默認行為）
        if ([string]::IsNullOrWhiteSpace($inputOp)) {
            if (Test-FilenameValid -Filename $finalDefaultName) {
                Show-Success "使用默認檔案名：$finalDefaultName"
                return $finalDefaultName
            }
            else {
                Show-Error "默認檔案名包含非法字元，請選擇其他方式。"
            }
        }
        elseif ($inputOp -eq 'a') { # 3-2：選項 a
            Show-Info "拷貝檔案名..."
            $selectedFile = $null
            
            # 內層循環：直到選到文件或強制退出
            while (-not $selectedFile) {
                $selectedFile = Select-File -Title "選擇一個文件以拷貝檔案名"
                if (-not $selectedFile) {
                    $retry = Read-Host " 未選擇文件，按 Enter 重試，輸入 'q' 返回上級"
                    if ($retry -eq 'q') { break }
                }
            }

            if ($selectedFile) {
                $extractedName = [System.IO.Path]::GetFileNameWithoutExtension($selectedFile)
                # 既然是系統裡已存在的檔案名，通常是合法的，但為了保險依然驗證
                if (Test-FilenameValid -Filename $extractedName) {
                    Show-Success "提取檔案名：$extractedName"
                    return $extractedName
                }
            }
        }
        elseif ($inputOp -eq 'b') { # 3-3：選項 b
            Show-Info "手動輸入..."
            Show-Warning "兩個方括號間必須要有字元隔開，不要輸入特殊符號"
            
            $manualName = $null
            while ($true) {
                $manualName = Read-Host " 填寫或黏貼除後綴外的檔案名（輸入 'q' 返回上級）"
                if ($manualName -eq 'q') { break }

                if ([string]::IsNullOrWhiteSpace($manualName)) {
                    Show-Warning "檔案名不能為空"
                    continue
                }
                if (Test-FilenameValid -Filename $manualName) {
                    Show-Success "設定檔案名：$manualName"
                    return $manualName
                }
                else {
                    Show-Error "檔案名包含非法字元，請重試"
                }
            }
        }
        else { # 3-4
            Show-Warning "選項無效，請輸入 a、b 或按 Enter"
        }
    }
}

# 解析分數字串並進行除法計算，用例：ConvertTo-Fraction -fraction "1/2"
function ConvertTo-Fraction {
    param([Parameter(Mandatory=$true)][string]$fraction)
    if ($fraction -match '^(\d+)/(\d+)$') {
        return [double]$matches[1] / [double]$matches[2]
    }
    elseif ($fraction -match '^\d+(\.\d+)?$') {
        return [double]$fraction
    }
    throw "ConvertTo-Fraction：無法解析幀率除法字串：$fraction"
}

# 生成管道上遊程序導入、下遊程序導出命令（管道命令已經在先前腳本中寫完，自動創建目錄）
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
        [string]$source, # 導入路徑到文件（帶或不帶引號）
        [bool]$isImport = $true,
        [string]$outputFilePath, # 導出目錄，不用於導入
        [string]$outputFileName, # 導出檔案名，不用於導入
        [string]$outputExtension
    )
    # 隔行掃描相關參數
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
            # 其它程序忽略隔行掃描參數
        }
    }

    # 驗證輸入文件（生成導入命令）
    $quotedInput = $null
    if ($isImport) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw "導入模式需要 source 參數"
        }
        if (-not (Test-Path -LiteralPath $source)) { # 默認檔案名一定含有方括號
            throw "輸入文件不存在：$source"
        }
        $quotedInput = Get-QuotedPath $source
    }
    else { # 導出模式必須給出導出檔案名
        if ([string]::IsNullOrWhiteSpace($outputFileName)) {
            throw "導出（下游）模式需要 outputFileName 參數"
        }
    }
    
    # 組合輸出路徑（不做副檔名自動添加）
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
    
    # 路徑加引號（$quoteInput 已定義；勿刪參數括號，否則副檔名會丟）
    $quotedOutput = Get-QuotedPath ($combinedOutputPath+$outputExtension)
    $sourceExtension = [System.IO.Path]::GetExtension($source)

    # 生成管道上游導入與下游導出參數
    if ($isImport) { # 導入模式
        switch -Wildcard ($program) {
            'ffmpeg' { 
                return "-i $quotedInput"
            }
            { $_ -in @('svfi', 'one_line_shot_args', 'ols', 'olsa') } { 
                return "--input $quotedInput"
            }
            # $sourceCSV.sourcePath 只有 .vpy 或 .avs 單個源，而先前步驟允許選擇多種上遊程序
            # 因此必然會出現 .vpy 腳本輸入出現在 AVS 程序，或反過來的情況
            # 儘管“自動生成占位腳本”功能會同時提供 .vpy 和 .avs 腳本，但用戶選擇輸入自訂腳本就不會做這一步
            # 這個問題需要透過修改源的副檔名來紓解，但默認修改檔案名後的源一定不存在，此時只警告用戶然後繼續
            { $_ -in @('vspipe', 'vs') } {
                if ($sourceExtension -ne '.vpy') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".vpy")
                    Show-Warning "vspipe 線路缺乏 .vpy 腳本源，嘗試匹配新路徑: $(Split-Path $newSource -Leaf)"
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "已成功切換源到 $newSource"
                        }
                    }
                    else {
                        Show-Warning "源 $newSource 不存在，vspipe 線路的導入需手動糾正"
                    }
                }
                # 返回輸入路徑和隔行掃描參數
                #（avs2pipemod 線路下自動提供 $interlacedArg）
                if ($interlacedArg -ne "") {
                    return "$quotedInput $interlacedArg"
                }
                else { return "$quotedInput" }
            }
            { $_ -in @('avs2yuv', 'avsy', 'a2y', 'avs2pipemod', 'avsp', 'a2p') } {
                if ($sourceExtension -ne '.avs') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".avs")
                    Show-Warning ($_ + " 線路缺乏 .avs 腳本源，嘗試匹配新路徑: $(Split-Path $newSource -Leaf)")
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "已成功切換源到 $newSource"
                        }
                    }
                    else {
                        Show-Warning ("源 $newSource 不存在，" + $_ + " 工具線路的導入需手動糾正")
                    }
                }
                # 返回輸入路徑和隔行掃描參數
                if ($interlacedArg -ne "") {
                    return "$quotedInput $interlacedArg"
                }
                else { return "$quotedInput" }
            }
            { $_ -in @('x264', 'h264', 'avc') } {
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
            { $_ -in @('svt-av1', 'svtav1', 'ivf') } { # SVT-AV1 原生不支持隔行
                return "-i -"
            }
        }
        break
    }
    else { # 導出模式
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
                throw "未識別的導出程序：$program"
            }
        }
    }
    throw "無法為程序 $program 生成 IO 參數"
}

# 獲取基礎參數
function Get-x264BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserFGO
    )

    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableFGO = $false
    if ($askUserFGO -and -not $isHelp) {
        Write-Host ""
        Write-Host " 少數修改版（Mod）x264 支持基於高頻資訊量的率失真最佳化（Film Grain Optimization）" -ForegroundColor Cyan
        Write-Host " 用 x264.exe --fullhelp | findstr fgo 檢測 --fgo 參數是否被支援" -ForegroundColor DarkGray
        if ((Read-Host " 輸入 'y' 以啟用 --fgo（提高畫質），或 Enter 以禁用（不支持或無法確定則禁）") -match '^[Yy]$') {
            $enableFGO = $true
            Show-Info "啟用 x264 參數 --fgo"
        }
        else { Show-Info "不用 x264 參數 --fgo" }
    }
    elseif (-not $isHelp) {
        Write-Host " 已跳過 --fgo 請柬..."
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
            Write-Host " 選擇 x264 自訂預設——[a：通用 | b：剪輯素材]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
            Write-Host " Select a custom preset for x264——[a: general purpose | b: stock footage]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-x264BaseParam：使用編碼器默認參數"
            return $default
        }
    }
}

# 獲取基礎參數：ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | x265.exe [Get-...] [Get-x265BaseParam] --y4m --input - --output ".\out.hevc"
function Get-x265BaseParam {
    Param ([Parameter(Mandatory=$true)]$pickOps)
    # TODO：添加 DJATOM? Mod 的深度自訂 AQ
    # $isHelp = $pickOps -in @('helpzh', 'helpen')
    $default = "--high-tier --preset slow --me umh --subme 5 --weightb --aq-mode 4 --bframes 5 --ref 3"

    switch ($pickOps) {
        # 通用 General Purpose，bframes 5
        a {return $default}
        # 錄影 Movie，bframes 8
        b {return "--high-tier --ctu 64 --tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --rect --tskip --tskip-fast --me star --weightb --ref 4 --max-merge 5 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --b-intra --crf 21.8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1.1 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3"} 
        # 素材 Stock Footage，bframes 7
        c {return "--high-tier --ctu 32 --tskip --me star --max-merge 5 --early-skip --b-intra --no-open-gop --min-keyint 1 --ref 3 --fades --bframes 7 --b-adapt 2 --crf 17 --crqpoffs -3 --cbqpoffs -2 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --splitrd-skip --deblock -1:-1 --tune grain"}
        # 動漫 Anime，bframes 16
        d {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --tskip --tskip-fast --me umh --weightb --max-merge 5 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --deblock -1:0 --limit-sao --sao-non-deblock"}
        # 窮舉法 Exhausive
        e {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 4 --limit-tu 1 --rect --amp --tskip --me star --weightb --max-merge 5 --ref 3 --no-open-gop --min-keyint 1 --fades --bframes 16 --b-adapt 2 --b-intra --crf 18.1 --crqpoffs -5 --cbqpoffs -2 --ipratio 1.67 --pbratio 1.33 --cu-lossless --psy-rdoq 2.5 --rdoq-level 2 --hevc-aq --aq-strength 1.4 --qg-size 8 --rd 5 --limit-refs 0 --rskip 2 --rskip-edge-threshold 3 --no-cutree --psy-rd 1.5 --rdpenalty 2 --deblock -2:-2 --limit-sao --sao-non-deblock --selective-sao 1"}
        helpzh {
            Write-Host ""
            Write-Host " 選擇 x265 自訂預設——[a：通用 | b：錄影 | c：剪輯素材 | d：動漫 | e：窮舉法]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
            Write-Host " Select a custom preset for x265——[a: general purpose | b: film | c: stock footage | d: anime | e: exhausive]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-x265BaseParam：使用編碼器默認參數"
            return $default
        }
    }
}

# 獲取基礎參數：ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | SvtAv1EncApp.exe -i - [Get-svtav1BaseParam] -b ".\out.ivf"
function Get-svtav1BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserDLF
    )
    
    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableDLF2 = $false
    Write-Host ""
    if ($askUserDLF -and (-not $isHelp) -and ($pickOps -ne 'b')) {
        Write-Host " Get-svtav1BaseParam：少數修改版 SVT-AV1 編碼器（如 SVT-AV1-Essential）支持高精度去塊濾鏡 --enable-dlf 2"  -ForegroundColor Cyan
        Write-Host " 用 SvtAv1EncApp.exe --help | findstr enable-dlf 即可檢測`'2`'是否受支援" -ForegroundColor DarkGray
        if ((Read-Host " 輸入 'y' 以啟用 --enable-dlf 2（提高畫質），或 Enter 使用常規去塊濾鏡（不支持或無法確定則禁）") -match '^[Yy]$') {
            $enableDLF2 = $true
            Show-Info "啟用了 SVT-AV1 參數 --enable-dlf 2"
        }
        else { Show-Info "啟用 SVT-AV1 參數 --enable-dlf 1" }
    }
    elseif (-not $isHelp) {
        Write-Host " 已跳過 --enable-dlf 2 請柬..."
    }
    $deblock = if ($enableDLF2) {"--enable-dlf 2"} else {"--enable-dlf 1"}

    $default = ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 --crf 30 --enable-qm 1 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 6 --progress 1 " + $deblock)
    switch ($pickOps) {
        # 畫質 Quality
        a {return $default}
        # 壓縮 Compression
        b {return ("--preset 2 --scd 1 --enable-tf 2 --tf-strength 2 --crf 30 --sharpness 4 --progress 1 " + $deblock)}
        # 速度 Speed
        c {return "--preset 2 --scd 1 --scm 0 --enable-tf 2 --tf-strength 2 --crf 30 --tune 0 --enable-variance-boost 1 --variance-boost-curve 2 --variance-boost-strength 2 --variance-octile 2 --sharpness 4 --progress 1"}
        helpzh {
            Write-Host ""
            Write-Host " 選擇 SVT-AV1 自訂預設——[a：畫質優先 | b：壓縮優先 | c：速度優先]" -ForegroundColor Yellow
            return
        }
        helpen {
            Write-Host ""
            Write-Host " Select a custom preset for SVT-AV1——[a: HQ | b: High compression | c: High speed]" -ForegroundColor Yellow
            return
        }
        default {
            Show-Info "Get-svtav1BaseParam：使用編碼器默認參數"
            return $default
        }
    }
}

# 互動式獲取編碼器基礎預設參數
function Invoke-BaseParamSelection {
    Param (
        [Parameter(Mandatory=$true)][string]$CodecName, # 僅用於顯示
        [Parameter(Mandatory=$true)][scriptblock]$GetParamFunc, # 對應的獲取函數
        [hashtable]$ExtraParams = @{}
    )

    $selectedParam = ""
    do {
        & $GetParamFunc -pickOps "helpzh"
        
        $selection = (Read-Host " 指定一份 $CodecName 自訂預設，輸入 'q' 忽略（沿用編碼器內建默認）").ToLower()

        if ($selection -eq 'q') { # $selectedParam = "" # 已經是預設值，不用再賦值
            break;
        }
        elseif ($selection -notmatch "^[a-z]$") {
            if ((Read-Host " 無法識別選項，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') {
                exit 1
            }
            continue
        }

        # 根據用戶輸入獲取基礎參數
        $selectedParam = & $GetParamFunc -pickOps $selection @ExtraParams
    }
    while (-not $selectedParam)

    if ($selectedParam) {
        Show-Success "已定義 $CodecName 基礎參數：$selectedParam"
    }
    else { Show-Info "$CodecName 將使用編碼器默認參數" }

    return $selectedParam
}

# 獲取關鍵幀間隔，默認 10*fps，直接適用於 x264
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
        throw "參數異常，一次只能給一個編碼器配置參數"
    }

    # 注意：值可以是“24000/1001”的字串，需要處理（得到 23.976d）
    [double]$fps = ConvertTo-Fraction $fpsString

    $userSecond = $null # 用戶指定秒
    if ($askUser) {
        if ($isx264) {
            Write-Host ""
            Show-Info "請指定 x264 的關鍵幀最大間隔秒（正整數，非幀數）"
        }
        elseif ($isx265) {
            Write-Host ""
            Show-Info "請指定 x265 的關鍵幀最大間隔秒數（正整數，非幀數）"
        }
        elseif ($isSVTAV1) {
            Write-Host ""
            Show-Info "請指定 SVT-AV1 的關鍵幀最大間隔秒數（正整數，非幀數）"
        }
        else {
            throw "未指定要配置最大關鍵幀間隔參數的編碼器，無法執行"
        }
        
        $userSecond = $null
        do { # 默認多軌剪輯的的解碼占用為關鍵幀間隔取和，但實際情況下，解碼占用取決於硬體解碼器的數量，所以僅設為兩倍
            Write-Host " 1. 解析度高於 2560x1440 則偏左選一格"
            Write-Host " 2. 畫面內容簡單，平面居多則偏右選一格"
            $userSecond =
                Read-Host " 大致範圍：[低功耗/多軌剪輯：6-7 秒| 一般：8-10 秒| 高：11-13+ 秒]"
            if ($userSecond -notmatch "^\d+$") {
                if ((Read-Host " 未輸入正整數，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') {
                    exit 1
                }
            }
        }
        while ($userSecond -notmatch "^\d+$")
        $second = $userSecond
    }

    try {
        $keyint = [math]::Round(($fps * $second))

        # 關鍵幀間隔必須大於連續 B 幀，但這與 SVT-AV1 無關
        if ($isSVTAV1) {
            Show-Success "已配置 SVT-AV1 最大關鍵幀間隔：${second} 秒"
            return "--keyint ${second}s"
        }

        $keyint = 
            if ($bframes -lt $keyint) { # 蠢到沒邊但實現了把 $bframes 當做上限的 hack
                [math]::max($keyint, $bframes)
            }
            elseif ($bframes -ge $keyint) {
                [math]::min($keyint, $bframes)
            }

        if ($isx264) {
            Show-Success "已配置 x264 最大關鍵幀間隔：${keyint} 幀"
        }
        elseif ($isx265) {
            Show-Success "已配置 x265 最大關鍵幀間隔：${keyint} 幀"
        }
        return "--keyint " + $keyint
    }
    catch {
        Show-Warning "無法讀取影片幀率資訊，關鍵幀間隔（Keyint）將使用編碼器默認"
        return ""
    }
}

function Get-RateControlLookahead { # 1.8*fps
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)][int]$bframes,
        [double]$second = 1.8
    )
    try {
        $frames = [math]::Round(((ConvertTo-Fraction $fpsString) * $second))
        # 必須大於 --bframes
        $frames = [math]::max($frames, $bframes+1)
        return "--rc-lookahead $frames"
    }
    catch {
        Show-Warning "Get-RateControlLookahead：無法讀取影片幀率資訊，率控制前瞻距離（RC Lookahead）將使用編碼器默認"
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
        throw "無法解析影片解析度：寬度=$CSVw, 高度=$CSVh"
    }
    if ($res -ge 8294400) { return "--merange 56" } # >=3840x2160
    elseif ($res -ge 3686400) { return "--merange 52" } # >=2560*1440
    elseif ($res -ge 2073600) { return "--merange 48" } # >=1920*1080
    elseif ($res -ge 921600) { return "--merange 40" } # >=1280*720
    else { return "--merange 36" }
}

function Get-x265Subme { # 24fps=3, 48fps=4, 60fps=5, ++=6
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [bool]$getInteger=$false
    )
    $encoderFPS = ConvertTo-Fraction $fpsString
    $subme = 6
    if ($encoderFPS -lt 25) {$subme = 3}
    elseif ($encoderFPS -lt 49) {$subme = 4}
    elseif ($encoderFPS -lt 61) {$subme = 5}

    if ($getInteger) { return $subme }
    return ("--subme " + $subme)
}

# 核心數大於 36 時開啟並行動態搜索
function Get-x265PME {
    if ([int](wmic cpu get NumberOfCores)[2] -gt 36) {
        return "--pme"
    }
    return ""
}

# 指定運行於特定 NUMA 節點，索引從 0 開始數；例：--pools -,+（雙路下使用二號節點）
function Get-x265ThreadPool {
    Param ([int]$atNthNUMA=0) # 直接輸入，一般情況下用不到

    $nodes = Get-CimInstance Win32_Processor # | Select-Object Availability
    [int]$procNodes = ($nodes | Measure-Object).Count
    
    # 統計可用處理器
    if ($procNodes -lt 1) { $procNodes = 1 }

    # 驗證參數
    if ($atNthNUMA -lt 0 -or $atNthNUMA -gt ($procNodes - 1)) {
        throw "NUMA 節點索引不能大於可用節點索引，且不能為負"
    }

    Write-Output ""
    if ($procNodes -gt 1) {
        if ($atNthNUMA -eq 0) {
            do {
                $inputValue = Read-Host "檢測到 $procNodes 處 NUMA 節點，請指定使用一處節點（範圍：0-$($procNodes-1)）"
                if ([string]::IsNullOrWhiteSpace($inputValue)) {
                    if ((Read-Host "未輸入值，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') { exit }
                }
                elseif ($inputValue -notmatch '^\d+$') {
                    if ((Read-Host "$inputValue 輸入了非整數，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') { exit }
                }
                elseif (($inputValue -lt 0) -or ($inputValue -gt ($procNodes - 1))) {
                    if ((Read-Host "NUMA 節點不存在，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') { exit }
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
        Show-Info "檢測到安裝了 1 顆處理器，忽略 x265 參數 --pools"
        return ""
    }
}

# 問題：總幀數可以存在於 .I、.J、.AA-AJ 等範圍，但位置隨機（假值一定為 0）
function Get-FrameCount {
    Param (
        [Parameter(Mandatory=$true)]$ffprobeCSV, # 完整 CSV 對象
        [bool]$isSVTAV1=$false
    )
    
    # 定義所有可能包含總幀數的列名（I, AA, AB, AC, AD, AE, AF, AG, AH, AI, AJ）
    $frameCountColumns = @();
    # VOB 格式僅位於 J，同時 AA 等位置有無關數值，不可試
    if ($script:interlacedArgs.isVOB) {
        $frameCountColumns = @('J');
    }
    else {
        $frameCountColumns =
            @('I') + (65..74 | ForEach-Object { [char]$_ } | ForEach-Object { "A$_" })
    }

    # 遍歷檢查列，找到首個非零值
    foreach ($column in $frameCountColumns) {
        $frameCount = $ffprobeCSV.$column
        
        # 檢查是否為數字且大於 0
        if ($frameCount -match "^\d+$" -and [int]$frameCount -gt 0) {
            if ($isSVTAV1) { 
                return "-n " + $frameCount 
            }
            return "--frames " + $frameCount
        }
    }
    return "" # 找不到
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

# 添加對 SVT-AV1 的丟幀幀率支持，丟幀幀率直接保留字串
function Get-FPSParam {
    Param (
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)]
        [ValidateSet("ffmpeg","x264","avc","x265","hevc","svtav1","SVT-AV1")]
        [string]$Target
    )
    # SVT-AV1 特殊處理：使用 --fps-num 和 --fps-denom 分開寫
    if ($Target -in @("svtav1", "SVT-AV1")) {
        if ($fpsString -match '^(\d+)/(\d+)$') {
            # 若是分數格式（如 24000/1001）
            return "--fps-num $($matches[1]) --fps-denom $($matches[2])"
        }
        else { # 直接輸入了小數：轉換為分數
            switch ($fpsString) {
                "23.976" { return "--fps-num 24000 --fps-denom 1001" }
                "29.97"  { return "--fps-num 30000 --fps-denom 1001" }
                "59.94"  { return "--fps-num 60000 --fps-denom 1001" }
                default  { # 其他值使用整數
                    try {
                        $intFps = [Math]::Round([double]$fpsString)
                    }
                    catch [System.Management.Automation.RuntimeException] {
                        throw "Get-FPSParam：幀率參數 fpsString 無法被轉換為數字：$fpsString"
                    }
                    return "--fps $intFps" 
                }
            }
        }
    }
    
    # x264、x265、ffmpeg 都可以直接使用分數字串或小數
    switch ($Target) {
        "ffmpeg" { return "-r $fpsString" }
        default  { return "--fps $fpsString" }
    }
}

# 獲取矩陣格式、傳輸特質、三原色
function Get-ColorSpaceSEI {
    Param (
        [Parameter(Mandatory=$true)]$CSVColorMatrix,
        [Parameter(Mandatory=$true)]$CSVTransfer,
        [Parameter(Mandatory=$true)]$CSVPrimaries,
        [ValidateSet("avc","x264","hevc","x265","av1","svtav1")][string]$Codec
    )
    $Codec = $Codec.ToLower()
    $result = @()
    
    # 處理 ColorMatrix
    if (($Codec -eq 'avc' -or $Codec -eq 'x264')) {
        if (($CSVColorMatrix -eq "unknown") -or ($CSVColorMatrix -eq "bt2020nc")) {
            $result += "--colormatrix undef" # x264 不寫 unknown
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
                Show-Warning "未知矩陣格式：$CSVColorMatrix，使用默認（bt709）"
                1
            }
        }
        $result += "--matrix-coefficients $c"
    }
    
    # 處理 Transfer
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
                Show-Warning "未知傳輸特質：$CSVTransfer，使用默認（bt709）"
                1
            }
        }
        $result += "--transfer-characteristics $t"
    }

    # 處理 Color Primaries
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
                Show-Warning "未知三原色：$CSVPrimaries，使用默認（bt709）"
                1
            }
        }

        $result += "--color-primaries $p"
    }
    
    return ($result -join " ")
}

# 輸入已經是 ffmpeg CSP 了
function Get-ffmpegCSP {
    Param ([ValidateSet(
            "yuv420p","yuv420p10le","yuv420p12le",
            "yuv422p","yuv422p10le","yuv422p12le",
            "yuv444p","yuv444p10le","yuv444p12le",
            "gray","gray10le","gray12le",
            "nv12","nv16"
        )][Parameter(Mandatory=$true)]$CSVpixfmt)
    # 移除可能的 "-pix_fmt " 前綴（儘管實際情況不會遇到）
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
    # 移除可能的 "-pix_fmt " 前綴（儘管實際情況不會遇到）
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''
    $chromaFormat = $null
    $depth = 8

    # 解析並檢查位深
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "影片編碼可能不支持 $depth bit 位深" # $depth = 8
    }

    # 解析色度採樣
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
    else { # 默認 4:2:0
        if ($isEncoderInput) {
            $chromaFormat = 'i420'
            Show-Warning "[編碼器] 未知像素格式：$pixfmt，將使用預設值（i420）"
        }
        else {
            $chromaFormat = 'AUTO'
            Show-Warning "[AviSynth] 未知像素格式：$pixfmt，將使用預設值（AUTO）"
        }
    }

    if ($isEncoderInput) {
        if ($isSVTAV1) { # --color-format，--input-depth
            # SVT-AV1 使用數字枚舉的 --color-format
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
        # avs2yuv 0.30 放棄了對 AviSynth 的支持（僅AviSynth+），因此 -csp 參數被取消
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

# 由於自動生成的腳本源存在，因此檔案名會變成 "blank_vs_script/blank_avs_script" 而非影片檔案名。若匹配到則消除默認（Enter）選項
function Get-IsPlaceHolderSource {
    Param([Parameter(Mandatory=$true)][string]$defaultName)
    return [string]::IsNullOrWhiteSpace($defaultName) -or
        $defaultName -match '^(blank_.*|.*_script)$' -or
        -not (Test-Path -LiteralPath $sourceCSV.SourcePath)
}

# 簡單通過排除法獲取管道類型，因此如果添加只支持 RAW YUV 管道的上游工具需要修改
function Get-IsRAWSource ([string]$validateUpstreamCode) {
    return $validateUpstreamCode -eq 'e'
}

# 盡快判斷檔案是否為 VOB 格式（格式判斷已被先前腳本確定），影響後續大量參數的 $ffprobeCSV 變數讀法
function Set-IsVOB {
    [Parameter(Mandatory=$true)][string]$ffprobeCsvPath
    if ([string]::IsNullOrWhiteSpace($ffprobeCsvPath)) {
        throw "Set-IsVOB：ffprobeCsvPath 參數為空，無法判斷"
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

    # 處理 VOB 格式
    if ($script:interlacedArgs.isVOB) {
        $fieldOrder = $fieldOrderOrIsInterlacedFrame.ToLower().Trim()
        
        switch -Regex ($fieldOrder) {
            '^progressive$' {
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            '^(tt|bt)$' { # tt：上場優先顯示、bt：下編上播
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $true
            }
            '^(bb|tb)$' { # bb：下場優先顯示、tb：上編下播
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $false
            }
            '^unknown$' {
                Show-Warning "Set-InterlacedArgs: VOB field_order 為 'unknown'，將視為逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            { [string]::IsNullOrWhiteSpace($fieldOrder) } {
                Show-Warning "Set-InterlacedArgs: VOB field_order 為空，將視為逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            default {
                Show-Warning "Set-InterlacedArgs: VOB field_order='$fieldOrder' 無法解析，將視為逐行"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
        }
    }
    else { # 非 VOB 格式，解析 interlaced_frame (0/1)
        $interlacedFrame = $fieldOrderOrIsInterlacedFrame.Trim()
        
        if ([string]::IsNullOrWhiteSpace($interlacedFrame)) {
            Show-Warning "Set-InterlacedArgs: interlaced_frame 為空，將視作逐行"
            $script:interlacedArgs.isInterlaced = $false
        }
        else {
            try {
                $interlacedInt = [int]::Parse($interlacedFrame)
                $script:interlacedArgs.isInterlaced = ($interlacedInt -eq 1)
            }
            catch {
                Show-Warning "Set-InterlacedArgs: 無法解析 interlaced_frame='$interlacedFrame'，將視作逐行"
                $script:interlacedArgs.isInterlaced = $false
            }
        }
        
        # 解析 top_field_first (-1/0/1)
        $tff = $topFieldFirst.Trim()
        
        if ([string]::IsNullOrWhiteSpace($tff)) {
            if ($script:interlacedArgs.isInterlaced) {
                Show-Warning "Set-InterlacedArgs: 場序未知且影片為隔行，將視作上場優先"
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
                        Show-Warning "Set-InterlacedArgs: top_field_first 值異常 '$tffInt'，將視作上場優先"
                        $script:interlacedArgs.isTFF = $true
                    }
                }
            }
            catch {
                Show-Warning "Set-InterlacedArgs: 無法解析 top_field_first='$tff'，默認上場優先"
                $script:interlacedArgs.isTFF = $true
            }
        }
    }
    
    Show-Debug "Set-InterlacedArgs：隔行掃描：$($script:interlacedArgs.isInterlaced), 上場優先：$($script:interlacedArgs.isTFF)"
}

#region Main
function Main {
    Show-Border
    Write-Host "參數計算與批處理注入工具" -ForegroundColor Cyan
    Show-Border
    Write-Host ""

    # 1. 自動尋找最新的 ffprobe CSV，並讀取影片資訊
    $ffprobeCsvPath = 
        Get-ChildItem -Path $Global:TempFolder -Filter "temp_v_info*.csv" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 | 
        ForEach-Object { $_.FullName }

    if ($null -eq $ffprobeCsvPath) {
        throw "未找到 ffprobe 生成的 CSV 文件；請運行步驟 3 腳本以補全"
    }

    # 2. 尋找源資訊 CSV
    $sourceInfoCsvPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    if (-not (Test-Path $sourceInfoCsvPath)) {
        throw "未找到專用資訊 CSV 文件；請運行步驟 3 腳本以補全"
    }

    Show-Info "正在讀取 ffprobe 資訊：$(Split-Path $ffprobeCsvPath -Leaf)..."
    Show-Info "正在讀取源專用資訊：$(Split-Path $sourceInfoCsvPath -Leaf)..."
    $ffprobeCSV =
        Import-Csv $ffprobeCsvPath -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA,AB,AC,AD,AE,AF,AG,AH,AI,AJ
    $sourceCSV =
        Import-Csv $sourceInfoCsvPath -Header SourcePath,UpstreamCode,Avs2PipeModDllPath,SvfiConfigInput,SvfiTaskId

    # 驗證 CSV 數據
    if (-not $sourceCSV.SourcePath) { # 直接驗證 CSV 項存在，不需要添加引號
        throw "temp_s_info CSV 數據不完整，請重運行步驟 3 腳本"
    }

    # 隔行掃描源支持
    # ffmpeg、vspipe、avs2yuv、svfi：忽略
    # avs2pipemod: y4mp, y4mt, y4mb (progressive, tff, bff)
    # x264: --tff, --bff
    # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
    # SVT-AV1：原生不支持，報錯並退出
    Show-Info "正在區分隔行掃描格式..."
    Set-IsVOB -ffprobeCsvPath $ffprobeCsvPath
    Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $ffprobeCSV.H -topFieldFirst $ffprobeCSV.J

    # 計算並賦值給對象屬性
    Show-Info "正在最佳化編碼參數（Profile、解析度、動態搜索範圍等）..."
    # $x265Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $false
    # $svtav1Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $true
    $x265Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C
    $svtav1Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C -isSVTAV1 $true
    $x265Params.MERange = Get-x265MERange -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C

    # Show-Debug "矩陣格式：$($ffprobeCSV.E)；傳輸特質：$($ffprobeCSV.F)；三原色：$($ffprobeCSV.G)"
    $svtav1Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec svtav1
    $x265Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x265
    $x264Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x264

    # VOB 格式的幀率資訊位於 I
    if ($script:interlacedArgs.isVOB) {
        $ffmpegParams.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target ffmpeg
        $svtav1Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target svtav1
        $x265Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target x265
        $x264Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.I -Target x264

        $x265Params.Subme = Get-x265Subme -fpsString $ffprobeCSV.I
        [int]$x265SubmeInt = Get-x265Subme -fpsString $ffprobeCSV.I -getInteger $true
        Show-Debug "VOB 源的幀率為：$(ConvertTo-Fraction $ffprobeCSV.I)"
        $x264Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes 250 -askUser -isx264
        $x265Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes $x265SubmeInt -askUser -isx265
        $svtav1Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.I -bframes 999 -askUser -isSVTAV1
        
        $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.I -bframes 250 # hack：借 bframes 做出建議最大值
        $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.I -bframes $x265SubmeInt
    }
    else {
        $ffmpegParams.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target ffmpeg
        $svtav1Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target svtav1
        $x265Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target x265
        $x264Params.FPS = Get-FPSParam -fpsString $ffprobeCSV.H -Target x264

        $x265Params.Subme = Get-x265Subme -fpsString $ffprobeCSV.H
        [int]$x265SubmeInt = Get-x265Subme -fpsString $ffprobeCSV.H -getInteger $true
        Show-Debug "源影片的幀率為：$(ConvertTo-Fraction $ffprobeCSV.H)"
        $x264Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes 250 -askUser -isx264
        $x265Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes $x265SubmeInt -askUser -isx265
        $svtav1Params.Keyint = Get-Keyint -fpsString $ffprobeCSV.H -bframes 999 -askUser -isSVTAV1
        $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.H -bframes 250
        $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $ffprobeCSV.H -bframes $x265SubmeInt
    }

    # VOB 的總幀數資訊位於 J
    $x265Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $x264Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $svtav1Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $true

    # x265 執行緒管理
    $x265Params.PME = Get-x265PME
    $x265Params.Pools = Get-x265ThreadPool

    # 獲取並配置色彩空間格式
    $avs2yuvVersionCode = 'a'
    if ($sourceCSV.UpstreamCode -eq 'c') {
        Write-Host ""
        Show-Info "選擇使用的 avs2yuv(64).exe 類型："
        $avs2yuvVersionCode = Read-Host " [默認 Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
    }
    $ffmpegParams.CSP = Get-ffmpegCSP -CSVpixfmt $ffprobeCSV.D
    $svtav1Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $true
    $x265Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $x264Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $avsyuvParams.CSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $false -isAvs2YuvInput $true -isSVTAV1 $false -isAVSPlus ($avs2yuvVersionCode -eq 'a')

    # Avs2PipeMod 需要的 DLL
    $quotedDllPath = Get-QuotedPath $sourceCSV.Avs2PipeModDllPath
    $avsmodParams.DLLInput = "-dll $quotedDllPath"

    # SVFI 需要的設定檔以及 Task ID
    if (-not [string]::IsNullOrWhiteSpace($sourceCSV.SvfiConfigInput)) {
        $quotedSvfiConfig = Get-QuotedPath $sourceCSV.SvfiConfigInput
        $olsargParams.ConfigInput = "--config $quotedSvfiConfig --task-id $($sourceCSV.SvfiTaskId)"
        Show-Debug "olsargParams.ConfigInput: $($olsargParams.ConfigInput)"
    }
    else { $olsargParams.ConfigInput = "" }

    Write-Host ""
    Show-Info "配置編碼結果導出路徑、檔案名..."
    $encodeOutputPath = Select-Folder -Description "選擇壓制結果的導出位置"
    # 1. 獲取源檔案名（用於傳遞給函數）
    $sourcePathRaw = $sourceCSV.SourcePath
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($sourcePathRaw)
    # 2. 判斷是否為佔位符腳本源
    $isPlaceholder = Get-IsPlaceHolderSource -defaultName $defaultNameBase
    # 3. 獲取最終檔案名（所有交互、驗證、重試都在函數內完成）
    $encodeOutputFileName = Get-EncodeOutputName -SourcePath $sourcePathRaw -IsPlaceholder $isPlaceholder

    # 由於默認給所有編碼器生成參數，因此僅通知相容性問題，而非報錯退出
    if ($script:interlacedArgs.isInterlaced -and
        $program -in @('x265', 'h265', 'hevc', 'svt-av1', 'svtav1', 'ivf')) {
        Show-Info "Get-EncodingIOArgument：SVT-AV1 原生不支持隔行掃描、x265 的隔行掃描編碼是實驗性功能（官方版）"
        Show-Info ("轉逐行與 IVTC 濾鏡教學：" + $script:interlacedArgs.toPFilterTutorial)
        Write-Host ""
    }

    Show-Info "生成管道上下遊程序的 IO 參數 (Input/Output)..."
    # 1. 管道上遊程序輸入
    # 管道連接符由先前腳本生成的批處理控制，這裡不寫
    $ffmpegParams.Input = Get-EncodingIOArgument -program 'ffmpeg' -isImport $true -source $sourceCSV.SourcePath
    $vspipeParams.Input = Get-EncodingIOArgument -program 'vspipe' -isImport $true -source $sourceCSV.SourcePath
    $avsyuvParams.Input = Get-EncodingIOArgument -program 'avs2yuv' -isImport $true -source $sourceCSV.SourcePath
    $avsmodParams.Input = Get-EncodingIOArgument -program 'avs2pipemod' -isImport $true -source $sourceCSV.SourcePath
    $olsargParams.Input = Get-EncodingIOArgument -program 'svfi' -isImport $true -source $sourceCSV.SourcePath
    # 2. 管道下遊程序（編碼器）輸入——需要根據隔行掃描判斷參數，因此必用 Get-EncodingIOArgument
    $x264Params.Input = Get-EncodingIOArgument -program 'x264' -isImport $true -source $sourceCSV.SourcePath
    $x265Params.Input = Get-EncodingIOArgument -program 'x265' -isImport $true -source $sourceCSV.SourcePath
    $svtav1Params.Input = Get-EncodingIOArgument -program 'svtav1' -isImport $true -source $sourceCSV.SourcePath
    # 3. 管道下遊程序輸出
    $x264Params.Output = Get-EncodingIOArgument -program 'x264' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x264Params.OutputExtension
    $x265Params.Output = Get-EncodingIOArgument -program 'x265' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x265Params.OutputExtension
    $svtav1Params.Output = Get-EncodingIOArgument -program 'svtav1' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $svtav1Params.OutputExtension

    Show-Info "構建管道下游（編碼器）基礎參數..."
    $x264Params.BaseParam = Invoke-BaseParamSelection -CodecName "x264" -GetParamFunc ${function:Get-x264BaseParam} -ExtraParams @{ askUserFGO = $true }
    $x265Params.BaseParam = Invoke-BaseParamSelection -CodecName "x265" -GetParamFunc ${function:Get-x265BaseParam}
    $svtav1Params.BaseParam = Invoke-BaseParamSelection -CodecName "SVT-AV1" -GetParamFunc ${function:Get-svtav1BaseParam} -ExtraParams @{ askUserDLF = $true }

    Show-Info "拼接最終參數字串..."
    # 這些字串將直接注入到批處理的 "set 'xxx_params=...'" 中
    # 空參數可能會導致雙空格出現，但路徑、檔案名裡也可能有雙空格，因此不過濾（-replace "  ", " "）
    # 1. 管道上游工具
    $ffmpegFinalParam = "$($ffmpegParams.FPS) $($ffmpegParams.Input) $($ffmpegParams.CSP)"
    $vspipeFinalParam = "$($vspipeParams.Input)"
    $avsyuvFinalParam = "$($avsyuvParams.Input) $($avsyuvParams.CSP)"
    $avsmodFinalParam = "$($avsmodParams.Input) $($avsmodParams.DLLInput)"
    $olsargFinalParam = "$($olsargParams.Input) $($olsargParams.ConfigInput)"
    # 2. x264（Input 必須放在最末尾）
    $x264FinalParam = "$($x264Params.Keyint) $($x264Params.SEICSP) $($x264Params.BaseParam) $($x264Params.Output) $($x264Params.Input)"
    # 3. x265
    $x265FinalParam = "$($x265Params.Keyint) $($x265Params.SEICSP) $($x265Params.RCLookahead) $($x265Params.MERange) $($x265Params.Subme) $($x265Params.PME) $($x265Params.Pools) $($x265Params.BaseParam) $($x265Params.Input) $($x265Params.Output)"
    # 4. SVT-AV1
    $svtav1FinalParam = "$($svtav1Params.Keyint) $($svtav1Params.SEICSP) $($svtav1Params.BaseParam) $($svtav1Params.Input) $($svtav1Params.Output)"

    $x264RawPipeApdx = "$($x264Params.FPS) $($x264Params.RAWCSP) $($x264Params.Resolution) $($x264Params.TotalFrames)"
    $x265RawPipeApdx = "$($x265Params.FPS) $($x265Params.RAWCSP) $($x265Params.Resolution) $($x265Params.TotalFrames)"
    $svtav1RawPipeApdx = "$($svtav1Params.FPS) $($svtav1Params.RAWCSP) $($svtav1Params.Resolution) $($svtav1Params.TotalFrames)"
    # N. RAW 管道相容
    if (Get-IsRAWSource -validateUpstreamCode $sourceCSV.UpstreamCode) {
        $x264FinalParam = $x264RawPipeApdx + " " + $x264FinalParam
        $x265FinalParam = $x265RawPipeApdx + " " + $x265FinalParam
        $svtav1FinalParam = $svtav1RawPipeApdx + " " + $svtav1FinalParam
    }

    # 生成 ffmpeg, vspipe, avs2yuv, avs2pipemod 編碼任務批處理
    Write-Host ""
    Show-Info "定位先前腳本生成的 encode_single.bat 模板..."
    $templateBatch = $null
    do {
        $templateBatch = Select-File -Title "選擇 encode_single.bat 批處理" -BatOnly
        
        if (-not $templateBatch) {
            if ((Read-Host "未選擇模板文件，按 Enter 重試，輸入 'q' 強制退出") -eq 'q') {
                return
            }
        }
    }
    while (-not $templateBatch)

    # 讀取模板
    $batchContent = [System.io.File]::ReadAllText($templateBatch, $Global:utf8BOM)

    # 準備要注入的參數塊
    # 一次性設置所有工具的參數，批處理執行時只用到它需要的部分
    $paramsBlock = @"
REM ========================================================
REM [自動注入] 詳細編碼參數（$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')）
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
REM [自動注入] RAW 管道輔助參數（手動添加）
REM ========================================================
REM x264_appendix=$x264RawPipeApdx
REM x265_appendix=$x265RawPipeApdx
REM svtav1_appendix=$svtav1RawPipeApdx


"@

    # 尋找替換錨點
    # 策略：找到 "REM 參數範例" 行，替換為參數塊
    # 若模板變更，則回退到在 @echo off 後面插入
    $newBatchContent = $batchContent

    # 字樣匹配
    $englishAnchor = '(?msi)^REM\s+Parameter\s+examples\b'
    $chineseAnchor = '(?msi)^REM\s+參數範例\b'

    if ($batchContent -match $englishAnchor -or $batchContent -match $chineseAnchor) {
        # 順序匹配英文模板、中文模板
        if ($batchContent -match $englishAnchor) {
            # 匹配從“REM 參數範例”到（但不包括）“REM 指定命令行”行的內容
            $pattern = '(?msi)^REM\s+Parameter\s+examples\b.*?^(?=REM\s+Specify\s+commandline\b)'
        }
        else {
            # 中文字樣（保持相容性）
            $pattern = '(?msi)^REM\s+參數範例\b.*?^(?=REM\s+指定本次所需編碼命令\b)'
        }

        # 替換操作使用 [regex]::Replace 以確保 .NET 正則表達式的行為。
        $newBatchContent = [regex]::Replace($batchContent, $pattern, $paramsBlock)
    }
    else {
        Write-Warning "未在模板中找到參數占位符，將在文件頭部追加參數。"
        $lines = [System.IO.File]::ReadAllLines($templateBatch, $Global:utf8BOM)

         # 在第3行（通常是 setlocal 之後）插入
        $insertIndex = 3

        # 使用 CRLF 或 LF 分割 paramsBlock 以安全地獲取行。
        $paramsLines = [System.Text.RegularExpressions.Regex]::Split($paramsBlock, "\r?\n")

        # 使用插入的參數創建新行
        $newLines = $lines[0..($insertIndex-1)] + $paramsLines + $lines[$insertIndex..($lines.Count-1)]
        $newBatchContent = $newLines -join "`r`n"
    }

    # 保存最終文件
    $finalBatchPath = Join-Path (Split-Path $templateBatch) "encode_task_final.bat"
    Show-Debug "輸出文件：$finalBatchPath"
    Write-Host ""
    
    try {
        Confirm-FileDelete $finalBatchPath
        Write-TextFile -Path $finalBatchPath -Content $newBatchContent -UseBOM $true

        # 驗證換行符
        Show-Debug "驗證批處理檔案格式..."
        if (-not (Test-TextFileFormat -Path $finalBatchPath)) {
            return
        }
    
        Show-Success "任務生成成功！直接運行該批處理文件以開始編碼。"
        Show-Info "若批處理運行後立即退出，則打開 CMD，運行導出錯誤到文本的命令，如：`r`n X:\encode_task_final.bat 2>Y:\error.txt"
    }
    catch {
        Show-Error "寫入檔案失敗：$_"
    }
    pause
}
#endregion

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}