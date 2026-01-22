<#
.SYNOPSIS
    Video encoding task batch generator
.DESCRIPTION
    Generate batch script for video encoding, supporting multiple toochains, inherit paths and toolchains created by preceding script steps
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# Load globals
. "$PSScriptRoot\Common\Core.ps1"

# Encoding parameters to configure according to source result and user requirements
# Note that pipe parameteres was already configured in step 2 script
$x264Params = [PSCustomObject]@{
    FPS = "" # Best practice: use string (24000/1001) for fractional frame rate
    Resolution = ""
    TotalFrames = ""
    RAWCSP = "" # Depth, colorspace...
    Keyint = ""
    RCLookahead = ""
    SEICSP = "" # ColorMatrix、Transfer
    BaseParam = ""
    Input = "-"
    Output = ""
    OutputExtension = ".mp4"
}
$x265Params = [PSCustomObject]@{
    FPS = "" # same as x264
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
    FPS = "" # Best practice: use --fps-num --fps-denom for fractional rate, not --fps
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

# Interlaced format support
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

    # 1. Calculate default filename
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $finalDefaultName = $null
    
    if (-not $IsPlaceholder -and -not [string]::IsNullOrWhiteSpace($defaultNameBase)) {
        $finalDefaultName = $defaultNameBase
    }
    else {
        # If it's a placeholder source (automatic script) or the source path is empty, use the timestamp as the default name.
        # Note: Filenames cannot contain colons, therefore use HH-mm.
        $finalDefaultName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    }

    # 2. Generate the display file name; truncate if too long
    $displayPrompt = if ($finalDefaultName.Length -gt 18) { 
        $finalDefaultName.Substring(0, 18) + "..." 
    }
    else {  $finalDefaultName  }

    # 3. UI loop
    while ($true) {
        Write-Host ""
        $inputOp = Read-Host " Specify the output filename——[a: Copy from file | b: Input | Enter: $displayPrompt]"

        # 3-1: Enter (default behavior)
        if ([string]::IsNullOrWhiteSpace($inputOp)) {
            if (Test-FilenameValid -Filename $finalDefaultName) {
                Show-Success "Using default filename: $finalDefaultName"
                return $finalDefaultName
            }
            else {
                Show-Error "Default filename has illegal character, please try other methods"
            }
        }
        elseif ($inputOp -eq 'a') { # 3-2: Option a
            Show-Info "Copy filename..."
            $selectedFile = $null
            
            # Inner loop: until file selected or break triggered
            while (-not $selectedFile) {
                $selectedFile = Select-File -Title "Select a file to copy its filename"
                if (-not $selectedFile) {
                    $retry = Read-Host "File not selected, press Enter to retry. Enter 'q' to return to previous menu"
                    if ($retry -eq 'q') { break }
                }
            }

            if ($selectedFile) {
                $extractedName = [System.IO.Path]::GetFileNameWithoutExtension($selectedFile)
                # Since the filename already exists in the system, it is usually valid, verifying anyways as a precaution
                if (Test-FilenameValid -Filename $extractedName) {
                    Show-Success "Extracted filename: $extractedName"
                    return $extractedName
                }
            }
        }
        elseif ($inputOp -eq 'b') { # 3-3: Option b (manual)
            Show-Info "Input filename..."
            Show-Warning "There must be a character separating both square brackets; avoid special characters"
            
            $manualName = $null
            while ($true) {
                $manualName = Read-Host " Enter filename without extension. Enter 'q' to return to previous menu"
                if ($manualName -eq 'q') { break }

                if ([string]::IsNullOrWhiteSpace($manualName)) {
                    Show-Warning "Filename cannot be empty"
                    continue
                }
                if (Test-FilenameValid -Filename $manualName) {
                    Show-Success "Filename set: $manualName"
                    return $manualName
                }
                else {
                    Show-Error "Illegal character found in file name, please retry"
                }
            }
        }
        else { # 3-4
            Show-Warning "Invalid option. Please enter a, b or press Enter"
        }
    }
}

# Parse the fraction string and perform division, i.e., ConvertTo-Fraction -fraction "1/2"
function ConvertTo-Fraction {
    param([Parameter(Mandatory=$true)][string]$fraction)
    if ($fraction -match '^(\d+)/(\d+)$') {
        return [double]$matches[1] / [double]$matches[2]
    }
    elseif ($fraction -match '^\d+(\.\d+)?$') {
        return [double]$fraction
    }
    throw "Could not parse framerate division string: $fraction"
}

# Generate upstream program's I and downstream's O commands
# (Pipe commands are completed by the previous script; auto-create needed directories)
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
        [string]$source, # Import path to file (with or without quotes)
        [bool]$isImport = $true,
        [string]$outputFilePath, # Export directory, not used for import
        [string]$outputFileName, # Export filename, not used for import
        [string]$outputExtension
    )
    # Interlaced specifier params
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
            # No argument for other programs
        }
    }

    # Validate file input (generate input argument)
    $quotedInput = $null
    if ($isImport) {
        if ([string]::IsNullOrWhiteSpace($source)) {
            throw "Import mode needs parameter: source"
        }
        if (-not (Test-Path -LiteralPath $source)) { # Treat all names as with square brackets
            throw "Input file missing: $source"
        }
        $quotedInput = Get-QuotedPath $source
    }
    else { # Export mode requires specifying the export file name
        if ([string]::IsNullOrWhiteSpace($outputFileName)) {
            throw "Export (downstream) mode requires the outputFileName parameter"
        }
    }

    # Combined output paths (without automatically adding file extensions)
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

    # Add quote to path ($quoteInput specified；Dont delete brackets here or we lose extension)
    $quotedOutput = Get-QuotedPath ($combinedOutputPath+$outputExtension)
    $sourceExtension = [System.IO.Path]::GetExtension($source)

    # Generate upstream import and downstream export parameters for pipelines
    if ($isImport) { # Import mode
        switch -Wildcard ($program) {
            'ffmpeg' { 
                return "-i $quotedInput"
            }
            { $_ -in @('svfi', 'one_line_shot_args', 'ols', 'olsa') } { 
                return "--input $quotedInput"
            }
            # $sourceCSV.sourcePath accepts only .vpy/.avs files,
            # but upstream steps may include an toolchain incompatible with script
            # While auto-generated placeholder script source provide both scripts,
            # specifying custom scripts bypasses it.
            # Users can change the source extension as a workaround,
            # though the renamed file won't exist by default—in such cases, just warn and continue
            { $_ -in @('vspipe', 'vs') } {
                if ($sourceExtension -ne '.vpy') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".vpy")
                    Show-Warning "vspipe route without .vpy script source, trying to match: $(Split-Path $newSource -Leaf)"
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "Successfully switched to $newSource"
                        }
                    }
                    else {
                        Show-Warning "$newSource not found, vspipe route needs manual correction"
                    }
                }
                # Return input path and interlaced specifier params
                # (avs2pipemod route has $interlacedArg provided)
                if ($interlacedArg -ne "") {
                    return "$quotedInput $interlacedArg"
                }
                else { return "$quotedInput" }
            }
            { $_ -in @('avs2yuv', 'avsy', 'a2y', 'avs2pipemod', 'avsp', 'a2p') } {
                if ($sourceExtension -ne '.avs') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".avs")
                    Show-Warning ($_ + " route without .avs script source, trying to match: $(Split-Path $newSource -Leaf)")
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        if (Show-Success -ErrorAction SilentlyContinue) {
                            Show-Success "Successfully switched to $newSource"
                        }
                    }
                    else {
                        Show-Warning ("$newSource not found, " + $_ + " route needs manual correction")
                    }
                }
                # Return input path and interlaced specifier params
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
            { $_ -in @('svt-av1', 'svtav1', 'ivf') } { # SVT-AV1 natively doesn't support interlaced
                return "-i -"
            }
        }
        break
    }
    else { # Export mode
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
                throw "Unidentified program: $program"
            }
        }
    }
    throw "Could not generate IO parameter for: $program"
}

# Subsequent scripts have implemented encapsulation functionality; 
# Use the default values, otherwise call this function.
# function Get-EncodingOutputFormatExtension {
#     Param (
#         [ValidateSet(
#             'x264','h264','avc',
#             'x265','h265','hevc',
#             'svt-av1','svtav1','ivf'
#         )][Parameter(Mandatory=$true)]$program
#     )
#     # x264 supports direct encapsulation of MP4 files;
#     # x265 only exports .hevc files;
#     # SVT-AV1 only exports .ivf files.
#     switch ($program) {
#         { $_ -in @('x264', 'h264', 'avc') } {
#             return ".mp4"
#         }
#         { $_ -in @('x265', 'h265', 'hevc') } {
#             return ".hevc"
#         }
#         { $_ -in @('svt-av1', 'svtav1', 'ivf') } {
#             return ".ivf"
#         }
#     }
# }

# Retrieve basic x264 parameters
function Get-x264BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserFGO
    )

    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableFGO = $false
    if ($askUserFGO -and -not $isHelp) {
        Write-Host ""
        Write-Host " Some modified/unofficial x264 support high-frequency information rate-distortion optimization (Film Grain Optimization)." -ForegroundColor Cyan
        Write-Host " Test with 'x264.exe --fullhelp | findstr fgo' to verify if its supported (shows up)" -ForegroundColor DarkGray
        if ((Read-Host " Input 'y' to add '--fgo' for better image, or Enter to disable (disable if unsure / can't confim)") -match '^[Yy]$') {
            $enableFGO = $true
            Show-Info "Enabled x264 parameter --fgo"
        }
        else { Show-Info "Disabled x264 parameter --fgo" }
    }
    elseif (-not $isHelp) {
        Write-Host " Skipped '--fgo' prompt..."
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
        # General Purpose，bframes 14
        a {return $default}
        # Stock Footage for Editing，bframes 12
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
            Show-Info "Get-x264BaseParam: Using default encoder parameter"
            return $default
        }
    }
}

# Retrieve basic x265 parametersffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | x265.exe [Get-...] [Get-x265BaseParam] --y4m --input - --output ".\out.hevc"
function Get-x265BaseParam {
    Param ([Parameter(Mandatory=$true)]$pickOps)
    # TODO：Add DJATOM? Mod's fully customizable AQ
    $default = "--high-tier --preset slow --me umh --subme 5 --weightb --aq-mode 4 --bframes 5 --ref 3"
    switch ($pickOps) {
        # General Purpose，bframes 5
        a {return $default}
        # Movie，bframes 8
        b {return "--high-tier --ctu 64 --tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --rect --tskip --tskip-fast --me star --weightb --ref 4 --max-merge 5 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --b-intra --crf 21.8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1.1 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3"} 
        # Stock Footage，bframes 7
        c {return "--high-tier --ctu 32 --tskip --me star --max-merge 5 --early-skip --b-intra --no-open-gop --min-keyint 1 --ref 3 --fades --bframes 7 --b-adapt 2 --crf 17 --crqpoffs -3 --cbqpoffs -2 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --splitrd-skip --deblock -1:-1 --tune grain"}
        # Anime，bframes 16
        d {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --tskip --tskip-fast --me umh --weightb --max-merge 5 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --deblock -1:0 --limit-sao --sao-non-deblock"}
        # Exhausive
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
            Show-Info "Get-x265BaseParam: Using default encoder parameter"
            return $default
        }
    }
}

# Retrieve basic SVT-AV1 parameters：ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | SvtAv1EncApp.exe -i - [Get-svtav1BaseParam] -b ".\out.ivf"
function Get-svtav1BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserDLF
    )
    
    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableDLF2 = $false
    Write-Host ""
    if ($askUserDLF -and (-not $isHelp) -and ($pickOps -ne 'b')) {
        Write-Host " Some modified/unofficial SVT-AV1 encoder (i.e., SVT-AV1-Essential) supports precise deblocking filter --enable-dlf 2"  -ForegroundColor Cyan
        Write-Host " Test with 'SvtAv1EncApp.exe --help | findstr enable-dlf' to verify if its supported (shows up)" -ForegroundColor DarkGray
        if ((Read-Host " Input 'y' to add '--enable-dlf 2' for better image, or Enter to disable (disable if unsure / can't confim)") -match '^[Yy]$') {
            $enableDLF2 = $true
            Show-Info "Enabled SVT-AV1 parameter --enable-dlf 2"
        }
        else { Show-Info "Enabled SVT-AV1 parameter --enable-dlf 1" }
    }
    elseif (-not $isHelp) {
        Write-Host " Skipped --enable-dlf 2 prompt..."
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
            Show-Info "Get-svtav1BaseParam: Using default encoder parameter"
            return $default
        }
    }
}

# Get base encoding parameter by user requirement
function Invoke-BaseParamSelection {
    Param (
        [Parameter(Mandatory=$true)][string]$CodecName, # Only for display
        [Parameter(Mandatory=$true)][scriptblock]$GetParamFunc, # Correcponding get function
        [hashtable]$ExtraParams = @{}
    )

    $selectedParam = ""
    do {
        & $GetParamFunc -pickOps "helpen"
        
        $selection = (Read-Host " Specify a custom present for $CodecName, Input 'q' to skip (use encoder defaults)").ToLower()

        if ($selection -eq 'q') { # $selectedParam = "" # No need to specify again
            break;
        }
        elseif ($selection -notmatch "^[a-z]$") {
            if ((Read-Host " Could not identify option. Press Enter to retry, input 'q' to force exit") -eq 'q') {
                exit 1
            }
            continue
        }

        # Get base parameters by use selection
        $selectedParam = & $GetParamFunc -pickOps $selection @ExtraParams
    }
    while (-not $selectedParam)

    if ($selectedParam) {
        Show-Success "Defined base parameter for $($CodecName): $($selectedParam)"
    }
    else { Show-Info "$CodecName will use default parameters" }

    return $selectedParam
}

# Get keyframe interval. Default to 10*fps, which is directly applicable to x264
function Get-Keyint { 
    Param (
        [Parameter(Mandatory=$true)]$CSVfps,
        [int]$bframes,
        [int]$second = 10,
        [switch]$askUser,
        [switch]$isx264,
        [switch]$isx265,
        [switch]$isSVTAV1
    )
    if (($isx264 -and $isx265) -or ($isx264 -and $isSVTAV1) -or ($isx265 -and $isSVTAV1)) {
        throw "Parameter error; only one encoder can be configured at a time."
    }

    # Note: The value can be a string like "24000/1001",
    # which needs to be parsed (resulting in 23.976d).
    [double]$fps = ConvertTo-Fraction $CSVfps

    $userSecond = $null # User specified seconds
    if ($askUser) {
        if ($isx264) {
            Write-Host ""
            Show-Info "Please specify the maximum keyframe interval for x264 in seconds (positive integer, not frame number)"
        }
        elseif ($isx265) {
            Write-Host ""
            Show-Info "Please specify the maximum keyframe interval for x265 in seconds (positive integer, not frame number)"
        }
        elseif ($isSVTAV1) {
            Write-Host ""
            Show-Info "Please specify the maximum keyframe interval for SVT-AV1 in seconds (positive integer, not frame number)"
        }
        else {
            throw "The encoder for which the maximum keyframe interval parameter is not specified cannot be executed"
        }
        
        $userSecond = $null
        do { # Decoding usage for video editing is the sum of the keyframe interval of all video tracks
            # However, the real-world decoding capability depends mostly on the # of hardware decoders,
            # so only setting to 2x default
            Write-Host " 1. For resolutions higher than 2560x1440, pick from 1 section to left"
            Write-Host " 2. For simple & flat video content, pick from 1 section to right"
            $userSecond =
                Read-Host " General Range to specify (second): [Low Power/Multitrack Editing: 6-7 | Normal: 8-10 | High: 11-13+ ]"
            if ($userSecond -notmatch "^\d+$") {
                if ((Read-Host " Not receiving positive integer. Press Enter to retry, input 'q' to force exit") -eq 'q') {
                    exit 1
                }
            }
        }
        while ($userSecond -notmatch "^\d+$")
        $second = $userSecond
    }

    try {
        $keyint = [math]::Round(($fps * $second))

        # The keyframe interval must be greater than a consecutive B-frame,
        # but this is irrelevant to SVT-AV1
        if ($isSVTAV1) {
            Show-Success "Maximum keyframe interval for SVT-AV1: ${second} seconds"
            return "--keyint ${second}s"
        }

        # The if -lt creates a hack that uses $bframes as the upper limit, and its really dumb
        $keyint = 
            if ($bframes -lt $keyint) {
                [math]::max($keyint, $bframes)
            }
            elseif ($bframes -ge $keyint) {
                [math]::min($keyint, $bframes)
            }

        if ($isx264) {
            Show-Success "Maximum keyframe interval for x264: ${keyint} frames"
        }
        elseif ($isx265) {
            Show-Success "Maximum keyframe interval for x265: ${keyint} frames"
        }
        return "--keyint " + $keyint
    }
    catch {
        Show-Warning "Unable to read video frame rate information, using the encoder default keyframe interval"
        return ""
    }
}

function Get-RateControlLookahead { # 1.8*fps
    Param (
        [Parameter(Mandatory=$true)]$CSVfps,
        [Parameter(Mandatory=$true)][int]$bframes,
        [double]$second = 1.8
    )
    try {
        $frames = [math]::Round(((ConvertTo-Fraction $CSVfps) * $second))
        # must be greater than --bframes
        $frames = [math]::max($frames, $bframes+1)
        return "--rc-lookahead $frames"
    }
    catch {
        Show-Warning "Unable to read video frame rate information, rate control lookahead (RC Lookahead) will use the encoder default."
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
        throw "Unable to resolve video resolution: width=$CSVw, height=$CSVh"
    }
    if ($res -ge 8294400) { return "--merange 56" } # >=3840x2160
    elseif ($res -ge 3686400) { return "--merange 52" } # >=2560*1440
    elseif ($res -ge 2073600) { return "--merange 48" } # >=1920*1080
    elseif ($res -ge 921600) { return "--merange 40" } # >=1280*720
    else { return "--merange 36" }
}

function Get-x265Subme { # 24fps=3, 48fps=4, 60fps=5, ++=6
    Param ([Parameter(Mandatory=$true)]$CSVfps, [bool]$getInteger=$false)
    $encoderFPS = ConvertTo-Fraction $CSVfps
    $subme = 6
    if ($encoderFPS -lt 25) {$subme = 3}
    elseif ($encoderFPS -lt 49) {$subme = 4}
    elseif ($encoderFPS -lt 61) {$subme = 5}

    if ($getInteger) { return $subme }
    return ("--subme " + $subme)
}

# Enable parallel motion estimation when the # of cores is greater than 36
function Get-x265PME {
    if ([int](wmic cpu get NumberOfCores)[2] -gt 36) {
        return "--pme"
    }
    return ""
}

# Specify a NUMA node to run on (starting from 0). i.e.: --pools -,+ (Use node 2 in dual-pool workstation)
function Get-x265ThreadPool {
    Param ([int]$atNthNUMA=0) # Direct input, usually not needed

    $nodes = Get-CimInstance Win32_Processor # | Select-Object Availability
    [int]$procNodes = ($nodes | Measure-Object).Count
    
    # Count usable processors
    if ($procNodes -lt 1) { $procNodes = 1 }

    # Validate parameters
    if ($atNthNUMA -lt 0 -or $atNthNUMA -gt ($procNodes - 1)) {
        throw "NUMA node index cannot be greater than the available node index, nor being negative"
    }

    Write-Output ""
    if ($procNodes -gt 1) {
        if ($atNthNUMA -eq 0) {
            do {
                $inputValue = Read-Host "A NUMA node was detected at $procNodes. Please specify a node to use (range: 0-$($procNodes-1))."
                if ([string]::IsNullOrWhiteSpace($inputValue)) {
                    if ((Read-Host "No value entered. Press Enter to retry, type 'q' to force exit") -eq 'q') { exit }
                }
                elseif ($inputValue -notmatch '^\d+$') {
                    if ((Read-Host "Non-integer entered. Press Enter to try again, type 'q' to force exit") -eq 'q') { exit }
                }
                elseif (($inputValue -lt 0) -or ($inputValue -gt ($procNodes - 1))) {
                    if ((Read-Host "Inexistent NUMA node. Press Enter to try again, type 'q' to force exit") -eq 'q') { exit }
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
        Show-Info "Detected 1 CPU node. Ignoring x265 parameter --pools."
        return ""
    }
}

# Attempt to obtain the total frame count and generate x264, x265, and SVT-AV1 parameters
# Problem: total frames can reside in .I, .AA-AJ ranges, but its location is random, we only know fake values are 0
function Get-FrameCount {
    Param (
        [Parameter(Mandatory=$true)]$ffprobeCSV, # Get fill CSV object
        [bool]$isSVTAV1
    )
    
    # All columns which can have total frame count（I, AA, AB, AC, AD, AE, AF, AG, AH, AI, AJ）
    $frameCountColumns = @();
    # VOB format only has J, with unrelated large integer around AA, never look there
    if ($script:interlacedArgs.isVOB) {
        $frameCountColumns = @('J');
    }
    else {
        $frameCountColumns =
            @('I') + (65..74 | ForEach-Object { [char]$_ } | ForEach-Object { "A$_" })
    }
    
    # Check each column, use the 1st non-zero value
    foreach ($column in $frameCountColumns) {
        $frameCount = $ffprobeCSV.$column

        # Find a number greater than 0
        if ($frameCount -match "^\d+$" -and [int]$frameCount -gt 0) {
            if ($isSVTAV1) { 
                return "-n " + $frameCount 
            }
            return "--frames " + $frameCount
        }
    }
    return "" # Not found
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

# Added support for fractional fps value in SVT-AV1 (directly preserved fraction strings)
function Get-FPSParam {
    Param (
        [Parameter(Mandatory=$true)]$CSVfps,
        [Parameter(Mandatory=$true)]
        [ValidateSet("ffmpeg","x264","avc","x265","hevc","svtav1","SVT-AV1")]
        [string]$Target
    )
    $fpsValue = $CSVfps
    
    # SVT-AV1's case: use --fps-num & --fps-denom instead
    if ($Target -in @("svtav1", "SVT-AV1")) {
        if ($fpsValue -match '^(\d+)/(\d+)$') {
            # Fractional fps, i.e., 24000/1001
            return "--fps-num $($matches[1]) --fps-denom $($matches[2])"
        }
        else { # Direct input in float, restore to fraction
            switch ($fpsValue) {
                "23.976" { return "--fps-num 24000 --fps-denom 1001" }
                "29.97"  { return "--fps-num 30000 --fps-denom 1001" }
                "59.94"  { return "--fps-num 60000 --fps-denom 1001" }
                default  { 
                    # Use integer for whole fps value
                    $intFps = [Math]::Round([double]$fpsValue)
                    return "--fps $intFps" 
                }
            }
        }
    }
    
    # x264、x265、ffmpeg supports direct string fps value
    switch ($Target) {
        "ffmpeg" { return "-r $fpsValue" }
        default  { return "--fps $fpsValue" }
    }
}

# Get color matrix, trasnfer characteristics and color primaries
function Get-ColorSpaceSEI {
    Param (
        [Parameter(Mandatory=$true)]$CSVColorMatrix,
        [Parameter(Mandatory=$true)]$CSVTransfer,
        [Parameter(Mandatory=$true)]$CSVPrimaries,
        [ValidateSet("avc","x264","hevc","x265","av1","svtav1")][string]$Codec
    )
    $Codec = $Codec.ToLower()
    $result = @()
    
    # ColorMatrix
    if (($Codec -eq 'avc' -or $Codec -eq 'x264')) {
        if (($CSVColorMatrix -eq "unknown") -or ($CSVColorMatrix -eq "bt2020nc")) {
            $result += "--colormatrix undef" # x264 uses undef instead of unknown
        }
        else { # fcc，bt470bg，smpte170m，smpte240m，GBR，YCgCo，bt2020c，smpte2085，chroma-derived-nc，chroma-derived-c，ICtCp
            $result += "--colormatrix $CSVColorMatrix"
        }
    }
    elseif (($Codec -eq 'hevc') -or ($Codec -eq 'x265')) {
        if ($CSVColorMatrix -eq "bt2020nc") {
            $result += "--colormatrix unknown"
        }
        else { # same as x264
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
                Show-Warning "Could not match color matrix：$CSVColorMatrix, using default (bt709)"
                1
            }
        }
        $result += "--matrix-coefficients $c"
    }
    
    # Transfer
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
                Show-Warning "Could not match transfer characteristics：$CSVTransfer, using default (bt709)"
                1
            }
        }
        $result += "--transfer-characteristics $t"
    }

    # Color Primaries
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
                Show-Warning "Could not match color primaries：$CSVPrimaries, using default (bt709)"
                1
            }
        }

        $result += "--color-primaries $p"
    }
    
    return ($result -join " ")
}

# Input is already ffmpeg CSP
function Get-ffmpegCSP {
    Param ([ValidateSet(
            "yuv420p","yuv420p10le","yuv420p12le",
            "yuv422p","yuv422p10le","yuv422p12le",
            "yuv444p","yuv444p10le","yuv444p12le",
            "gray","gray10le","gray12le",
            "nv12","nv16"
        )][Parameter(Mandatory=$true)]$CSVpixfmt)
    # Remove any possible "-pix_fmt" prefixes (although its unlikely encounter)
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
    # Remove any possible "-pix_fmt" prefixes (although its unlikely encounter)
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''
    $chromaFormat = $null
    $depth = 8

    # Match and validate bit depth
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "Video encoder may not support $depth bit" # $depth = 8
    }

    # Match and validate chroma subsampling type
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
    else { # Default to 4:2:0
        if ($isEncoderInput) {
            $chromaFormat = 'i420'
            Show-Warning "[Encoder] Unknown pixel format: $pixfmt, using default (i420)"
        }
        else {
            $chromaFormat = 'AUTO'
            Show-Warning "[AviSynth] Unknown pixel format: $pixfmt, using default (AUTO)"
        }
    }

    if ($isEncoderInput) {
        if ($isSVTAV1) { # --color-format, --input-depth
            # SVT-AV1 uses integer --color-format
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
                Show-Warning "[SVT-AV1] Unknown color format: $chromaFormat, falling back to yuv420"
                $svtColor = 1
            }
            return "--color-format $svtColor --input-depth $depth"
        }
        else { # x265 uses --input-csp and --input-depth
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
        # avs2yuv 0.30 Dropped support for AviSynth (AviSynth+ only) therefore -csp option is gone
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

# Since the auto-generated script source exists, the filename will become "blank_vs_script/blank_avs_script" instead of the video filename.
# If a match is found, the default (Enter) option will be eliminated.
function Get-IsPlaceHolderSource {
    Param([Parameter(Mandatory=$true)][string]$defaultName)
    return [string]::IsNullOrWhiteSpace($defaultName) -or
        $defaultName -match '^(blank_.*|.*_script)$' -or
        -not (Test-Path -LiteralPath $sourceCSV.SourcePath)
}

# The pipeline type is simply determined by an elimination process
# Therefore, modifications is required if an upstream tool only supports RAW YUV pipelines
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

#region Main
function Main {
    Show-Border
    Write-Host "Video encoding task gnerator" -ForegroundColor Cyan
    Show-Border
    Write-Host ""

    # 1. Locate the latest ffprobe CSV and read the video information
    $ffprobeCsvPath = 
        Get-ChildItem -Path $Global:TempFolder -Filter "temp_v_info*.csv" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 | 
        ForEach-Object { $_.FullName }

    if ($null -eq $ffprobeCsvPath) {
        Show-Error "Missing CSV file created by ffprobe (step 3); Please complete step 3 script"
        return
    }

    # 2. Locate source CSV
    $sourceInfoCsvPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    if (-not (Test-Path $sourceInfoCsvPath)) {
        Show-Error "Missing CSV file about source created by previous script; Please complete step 3 script"
        return
    }

    Show-Info "Reading ffprobe data: $(Split-Path $ffprobeCsvPath -Leaf)..."
    Show-Info "Reading source data: $(Split-Path $sourceInfoCsvPath -Leaf)..."

    $ffprobeCSV =
        Import-Csv $ffprobeCsvPath -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA,AB,AC,AD,AE,AF,AG,AH,AI,AJ
    $sourceCSV =
        Import-Csv $sourceInfoCsvPath -Header SourcePath,UpstreamCode,Avs2PipeModDllPath,SvfiConfigInput,SvfiTaskId

    # Validate CSV data
    if (-not $sourceCSV.SourcePath) { # Validate CSV field existance, no quote needed
        Show-Error "temp_s_info CSV data corrupted. Please rerun step 3 script"
        return
    }

    # Calculate and assign to object properties
    Show-Info "Optimizing encoding parameters (Profile, resolution, dynamic search range, etc.)..."
    # $x265Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $false
    # $svtav1Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $true
    $x265Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C
    $svtav1Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C -isSVTAV1 $true
    $x265Params.MERange = Get-x265MERange -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C
    $ffmpegParams.FPS = Get-FPSParam -CSVfps $ffprobeCSV.H -Target ffmpeg
    $svtav1Params.FPS = Get-FPSParam -CSVfps $ffprobeCSV.H -Target svtav1
    $x265Params.FPS = Get-FPSParam -CSVfps $ffprobeCSV.H -Target x265
    $x264Params.FPS = Get-FPSParam -CSVfps $ffprobeCSV.H -Target x264

    Show-Debug "Color matrix：$($ffprobeCSV.E); Transfer: $($ffprobeCSV.F); Primaries: $($ffprobeCSV.G)"
    $svtav1Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec svtav1
    $x265Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x265
    $x264Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -Codec x264
    $x265Params.Subme = Get-x265Subme -CSVfps $ffprobeCSV.H
    [int]$x265SubmeInt = Get-x265Subme -CSVfps $ffprobeCSV.H -getInteger $true
    Show-Debug "Source framerate: $(ConvertTo-Fraction $ffprobeCSV.H)"
    $x264Params.Keyint = Get-Keyint -CSVfps $ffprobeCSV.H -bframes 250 -askUser -isx264
    $x265Params.Keyint = Get-Keyint -CSVfps $ffprobeCSV.H -bframes $x265SubmeInt -askUser -isx265
    $svtav1Params.Keyint = Get-Keyint -CSVfps $ffprobeCSV.H -bframes 999 -askUser -isSVTAV1
    $x264Params.RCLookahead = Get-RateControlLookahead -CSVfps $ffprobeCSV.H -bframes 250 # hack：implement suggested maximum value in x264 using fake bframes
    $x265Params.RCLookahead = Get-RateControlLookahead -CSVfps $ffprobeCSV.H -bframes $x265SubmeInt

    $x265Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $x264Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $svtav1Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $true
    $x265Params.PME = Get-x265PME
    $x265Params.Pools = Get-x265ThreadPool

    # Obtain color space format
    $avs2yuvVersionCode = 'a'
    if ($sourceCSV.UpstreamCode -eq 'c') {
        Write-Host ""
        Show-Info "Select the correct version of avs2yuv(64).exe used:"
        $avs2yuvVersionCode = Read-Host " [a/Default Enter: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
    }

    $ffmpegParams.CSP = Get-ffmpegCSP -CSVpixfmt $ffprobeCSV.D
    $svtav1Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $true
    $x265Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $x264Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $avsyuvParams.CSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $false -isAvs2YuvInput $true -isSVTAV1 $false -isAVSPlus ($avs2yuvVersionCode -eq 'a')

    # Avs2PipeMod's required DLL
    $quotedDllPath = Get-QuotedPath $sourceCSV.Avs2PipeModDllPath
    $avsmodParams.DLLInput = "-dll $quotedDllPath"

    # SVFI's required INI file AND Task ID
    if (-not [string]::IsNullOrWhiteSpace($sourceCSV.SvfiConfigInput)) {
        $quotedSvfiConfig = Get-QuotedPath $sourceCSV.SvfiConfigInput
        $olsargParams.ConfigInput = "--config $quotedSvfiConfig --task-id $($sourceCSV.SvfiTaskId)"
        Show-Debug "olsargParams.ConfigInput: $($olsargParams.ConfigInput)"
    }
    else { $olsargParams.ConfigInput = "" }

    # Locate the batch file for exporting the encoding task and the encoding output path.
    Write-Host ""
    Show-Info "Configure the export path for encoding result output..."
    $encodeOutputPath = Select-Folder -Description "Select path for encoding export"

    # Configure the filename of the encoded result
    # 1. Get the default value (copy from the source)
    Show-Debug "CSV SourcePath Original text: $($sourceCSV.SourcePath)"
    
    $defaultName = [io.path]::GetFileNameWithoutExtension($sourceCSV.SourcePath)
    # Auto-generated script source makes the filename to become "blank_vs_script/blank_avs_script" instead of the video filename.
    # If this filename is matched, eliminate the default (Enter) option.
    $isPlaceholderSource = Get-IsPlaceHolderSource -defaultName $defaultName
    $encodeOutputFileName = ""
    
    # Calculate displayName using PowerShell 5.1 compatible syntax.
    if (-not $isPlaceholderSource) {
        $encodeOutputFileName = $defaultName
        if ($defaultName.Length -gt 17) {
            $displayName = $defaultName.Substring(0, 18) + "..."
        }
        else {
            $displayName = $defaultName
        }
    }
    else { # Do not put ":" into path!
        $displayName = "Encode " + (Get-Date -Format 'yyyy-MM-dd HH-mm')
    }

    $encodeOutputNameCode =
        Read-Host " Specify filename for the encoded video——[a: copy from file | b: input | Enter: $displayName]"
    # Ensure there are no special/invisible characters
    if ($encodeOutputNameCode -eq 'a') { # Select source video file
        Show-Info "Select a file to copy filename..."
        do {
            $fileForName = Select-File -Title "Select a file to copy filename"
            if (-not $fileForName) {
                if ((Read-Host " No file selected. Press Enter to try again, type 'q' to force exit") -eq 'q') {
                    return
                }
            }
        }
        while (-not $fileForName)

        # Get file name
        $encodeOutputFileName = [io.path]::GetFileNameWithoutExtension($fileForName)
    }
    elseif ($encodeOutputNameCode -eq 'b') { # Type input
        $encodeOutputFileName = Read-Host " Input a filename (without extension)"
    }
    # Default file name
    # (if final file name is stll empty, set to $displayName)
    # When $displayName = "Encode " + (Get-Date...), $encodeOutputFileName is still unset
    if (-not $encodeOutputFileName -or $encodeOutputFileName -eq "") {
        $encodeOutputFileName = $displayName
    }

    if (Test-FilenameValid -Filename $encodeOutputFileName) {
        Show-Success "Final file name：$encodeOutputFileName"
    }
    else {
        Show-Error "Filename $encodeOutputFileName failed to conform to Windows naming conventions."
        Write-Host " Please manually change it in the generated batch file,"
        Write-Host " otherwise expect encoding to fail in the file save step"
    }

    # Generate IO Parameters (Input/Output)
    # 1. Upstream Program Input of the Pipe
    # The pipe connector is controlled by the batch generated by the previous script,
    # and is not specified here.
    $ffmpegParams.Input = Get-EncodingIOArgument -program 'ffmpeg' -isImport $true -source $sourceCSV.SourcePath
    $vspipeParams.Input = Get-EncodingIOArgument -program 'vspipe' -isImport $true -source $sourceCSV.SourcePath
    $avsyuvParams.Input = Get-EncodingIOArgument -program 'avs2yuv' -isImport $true -source $sourceCSV.SourcePath
    $avsmodParams.Input = Get-EncodingIOArgument -program 'avs2pipemod' -isImport $true -source $sourceCSV.SourcePath
    $olsargParams.Input = Get-EncodingIOArgument -program 'svfi' -isImport $true -source $sourceCSV.SourcePath
    # 2. Downstream program (encoder) input (no need to call Get-EncodingIOArgument since the default value is already provided)
    # $x264Params.Input = Get-EncodingIOArgument -program 'x264' -isImport $true
    # $x265Params.Input = Get-EncodingIOArgument -program 'x265' -isImport $true
    # $svtav1Params.Input = Get-EncodingIOArgument -program 'svtav1' -isImport $true
    # 3. Pipe downstream program output
    $x264Params.Output = Get-EncodingIOArgument -program 'x264' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x264Params.OutputExtension
    $x265Params.Output = Get-EncodingIOArgument -program 'x265' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x265Params.OutputExtension
    $svtav1Params.Output = Get-EncodingIOArgument -program 'svtav1' -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $svtav1Params.OutputExtension

    # Constructing base parameters of the pipe downstream programs
    $x264Params.BaseParam = Invoke-BaseParamSelection -CodecName "x264" -GetParamFunc ${function:Get-x264BaseParam} -ExtraParams @{ askUserFGO = $true }
    $x265Params.BaseParam = Invoke-BaseParamSelection -CodecName "x265" -GetParamFunc ${function:Get-x265BaseParam}
    $svtav1Params.BaseParam = Invoke-BaseParamSelection -CodecName "SVT-AV1" -GetParamFunc ${function:Get-svtav1BaseParam} -ExtraParams @{ askUserDLF = $true }

    # Concatenate final parameter string
    # These strings will be directly injected into the batch file "set 'xxx_params=...'"
    # Empty parameters may result in double spaces, but paths and filenames may also contain double spaces, so they are not filtered (-replace " ", " ")
    # 1. Pipeline upstream tool
    $ffmpegFinalParam = "$($ffmpegParams.FPS) $($ffmpegParams.Input) $($ffmpegParams.CSP)"
    $vspipeFinalParam = "$($vspipeParams.Input)"
    $avsyuvFinalParam = "$($avsyuvParams.Input) $($avsyuvParams.CSP)"
    $avsmodFinalParam = "$($avsmodParams.Input) $($avsmodParams.DLLInput)"
    $olsargFinalParam = "$($olsargParams.Input) $($olsargParams.ConfigInput)"
    # 2. x264 (Input must be located in the end)
    $x264FinalParam = "$($x264Params.Keyint) $($x264Params.SEICSP) $($x264Params.BaseParam) $($x264Params.Output) $($x264Params.Input)"
    # 3. x265
    $x265FinalParam = "$($x265Params.Keyint) $($x265Params.SEICSP) $($x265Params.RCLookahead) $($x265Params.MERange) $($x265Params.Subme) $($x265Params.PME) $($x265Params.Pools) $($x265Params.BaseParam) $($x265Params.Input) $($x265Params.Output)"
    # 4. SVT-AV1
    $svtav1FinalParam = "$($svtav1Params.Keyint) $($svtav1Params.SEICSP) $($svtav1Params.BaseParam) $($svtav1Params.Input) $($svtav1Params.Output)"

    $x264RawPipeApdx = "$($x264Params.FPS) $($x264Params.RAWCSP) $($x264Params.Resolution) $($x264Params.TotalFrames)"
    $x265RawPipeApdx = "$($x265Params.FPS) $($x265Params.RAWCSP) $($x265Params.Resolution) $($x265Params.TotalFrames)"
    $svtav1RawPipeApdx = "$($svtav1Params.FPS) $($svtav1Params.RAWCSP) $($svtav1Params.Resolution) $($svtav1Params.TotalFrames)"
    # N. RAW pipe mode
    if (Get-IsRAWSource -validateUpstreamCode $sourceCSV.UpstreamCode) {
        $x264FinalParam = $x264RawPipeApdx + " " + $x264FinalParam
        $x265FinalParam = $x265RawPipeApdx + " " + $x265FinalParam
        $svtav1FinalParam = $svtav1RawPipeApdx + " " + $svtav1FinalParam
    }

    # Show-Debug $ffmpegFinalParam
    # Show-Debug $vspipeFinalParam
    # Show-Debug $avsyuvFinalParam
    # Show-Debug $avsmodFinalParam
    # Show-Debug $olsargFinalParam
    # Show-Debug $x264FinalParam
    # Show-Debug $x265FinalParam
    # Show-Debug $svtav1FinalParam

    #  Generate ffmpeg, vspipe, avs2yuv, avs2pipemod encoding task batch
    Write-Host ""
    Show-Info "Select the previously generated encode_single.bat template..."
    $templateBatch = $null
    do {
        $templateBatch = Select-File -Title "Select encode_single.bat" -BatOnly
        
        if (-not $templateBatch) {
            if ((Read-Host "No file selected. Press Enter to retry, input 'q' to force exit") -eq 'q') {
                return
            }
        }
    }
    while (-not $templateBatch)

    # Read template
    $batchContent = [System.io.File]::ReadAllText($templateBatch, $Global:utf8BOM)

    # Prepare the parameter block to be injected
    # Configure all toolchain parameters at once
    # despite only use the necessary parts during batch execution.
    $paramsBlock = @"
REM ========================================================
REM [Auto-injected] Encoding param ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
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
REM [Auto-injected] RAW pipe support appendix (Add manually)
REM ========================================================
REM x264_appendix=$x264RawPipeApdx
REM x265_appendix=$x265RawPipeApdx
REM svtav1_appendix=$svtav1RawPipeApdx


"@

    # Replace anchor (translated to English): keep Chinese anchor for backward compatibility
    # Strategy: find the "REM Parameter examples" block and replace it with $paramsBlock.
    # If the template changed, fall back to inserting after the file header.
    $newBatchContent = $batchContent

    # Patterns
    $englishAnchor = '(?msi)^REM\s+Parameter\s+examples\b'
    $chineseAnchor = '(?msi)^REM\s+参数示例\b'

    if ($batchContent -match $englishAnchor -or $batchContent -match $chineseAnchor) {
        # Prefer English pattern; if English not present but Chinese present, use Chinese pattern.
        if ($batchContent -match $englishAnchor) {
            # Match from "REM Parameter examples" up to (but not including) the "REM Specify commandline" line.
            $pattern = '(?msi)^REM\s+Parameter\s+examples\b.*?^(?=REM\s+Specify\s+commandline\b)'
        }
        else {
            # Chinese-compatible pattern (keeps compatibility with older templates)
            $pattern = '(?msi)^REM\s+参数示例\b.*?^(?=REM\s+指定本次所需编码命令\b)'
        }

        # Perform the replacement. Use [regex]::Replace to ensure .NET regex behavior.
        $newBatchContent = [regex]::Replace($batchContent, $pattern, $paramsBlock)
    }
    else {
        Write-Warning "Parameter placeholder not found in template; will append parameters near the file header."
        $lines = [System.IO.File]::ReadAllLines($templateBatch, $Global:utf8BOM)

        # insertIndex = 3 (same as before: typically after @echo off / chcp / setlocal)
        $insertIndex = 3

        # Split paramsBlock on either CRLF or LF to get lines safely
        $paramsLines = [System.Text.RegularExpressions.Regex]::Split($paramsBlock, "\r?\n")

        # Build new lines with inserted params
        $newLines = $lines[0..($insertIndex-1)] + $paramsLines + $lines[$insertIndex..($lines.Count-1)]
        $newBatchContent = $newLines -join "`r`n"
    }

    # Save final batch
    $finalBatchPath = Join-Path (Split-Path $templateBatch) "encode_task_final.bat"
    Show-Debug "Exporting file: $finalBatchPath"
    Write-Host ""
    
    try {
        Confirm-FileDelete $finalBatchPath
        Write-TextFile -Path $finalBatchPath -Content $newBatchContent -UseBOM $true

        # Validate line breaks, must be CRLF
        Show-Debug "Validating batch file format..."
        if (-not (Test-TextFileFormat -Path $finalBatchPath)) {
            return
        }
    
        Show-Success "Task generated successfully! Run the batch file to begin coding."
        Show-Warning "If the batch file exits immediately after running, run the command to export errors to text: `r`n X:\encode_task_final.bat 2>Y:\error.txt"
    }
    catch {
        Show-Error "File write failed: $_"
    }
    pause
}
#endregion

try { Main }
catch {
    Show-Error "Script execution error: $_"
    Write-Host "Error details: " -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "Press Enter to exit"
}