<#
.SYNOPSIS
    Video encoding task batch generator
.DESCRIPTION
    Generate batch script for video encoding, supporting multiple toochains, inherit paths and toolchains created by preceding script steps
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.7
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
    LogLevel = "-loglevel warning" # Hide progress to fix contention with encoder progress
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
    isMOV = $false
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
        Write-Host ''
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
            Write-Host " There must be a character separating 2 square brackets; avoid special characters"
            
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

# Generate upstream & downstream programs' I & O commands (Pipe cmd are done by prev scripts; auto-mkdir configured)
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
        [string]$source, # Import path to file (with or without quotes)
        [bool]$isImport = $true,
        [string]$outputFilePath, # Export directory, not used for import
        [string]$outputFileName, # Export filename, not used for import
        [string]$outputExtension
    )
    # Ensure only one switch is on
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
        throw "Get-EncodingIOArgument: Specify 1 program at least, i.e., -isffmpeg"
    }
    if ($switchedOn.Count -gt 1) {
        throw "Get-EncodingIOArgument：Specify 1 program at most, currently there are: $($switchedOn -join ', ')"
    }
    $program = $switchedOn[0]

    # Interlaced specifier params
    $iArg = ""
    if ($script:interlacedArgs.isInterlaced) {
        switch ($program) {
            'avs2pipemod' { # avs2pipemod: y4mp (progressive), y4mt (tff), y4mb (bff)
                $iArg =
                    if ($script:interlacedArgs.isTFF) { "-y4mt" }
                    else { "-y4mb" }
            }
            'x264' { # x264: --tff, --bff
                $iArg =
                    if ($script:interlacedArgs.isTFF) { "--tff" }
                    else { "--bff" }
            }
            'x265' { # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
                $iArg =
                    if ($script:interlacedArgs.isTFF) { "--interlace 1" }
                    else { "--interlace 2" }
            }
            # SVT-AV1 & ffmpeg don't support interlaced, skip for vspipe/avs2yuv/svfi
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
            'ffmpeg' { return "-i $quotedInput" }
            'svfi' { return "--input $quotedInput" }
            # $sourceCSV.sourcePath accepts only .vpy/.avs files,
            # but upstream steps may include an toolchain incompatible with script
            # While auto-generated placeholder script source provide both scripts,
            # specifying custom scripts bypasses it.
            # Users can change the source extension as a workaround,
            # though the renamed file won't exist by default—in such cases, just warn and continue
            'vspipe' {
                if ($sourceExtension -ne '.vpy') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".vpy")
                    Show-Debug "vspipe route without .vpy script source, trying to match: $(Split-Path $newSource -Leaf)"
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        Show-Success "Successfully switched to $newSource"
                    }
                    else { Show-Debug "vspipe route needs manual correction" }
                }
                # Return input path and interlaced specifier params
                # (avs2pipemod route has $iArg provided)
                if ($iArg) { return "$quotedInput $iArg" }
                else { return $quotedInput }
            }
            { $_ -in @('avs2yuv', 'avs2pipemod') } {
                if ($sourceExtension -ne '.avs') {
                    $newSource = [System.IO.Path]::ChangeExtension($source, ".avs")
                    Show-Debug ($_ + " route without .avs script source, trying to match: $(Split-Path $newSource -Leaf)")
                    if (Test-Path -LiteralPath $newSource) {
                        $source = $newSource
                        $quotedInput = Get-QuotedPath $source
                        Show-Success "Successfully switched to $newSource"
                    }
                    else { Show-Debug ($_ + " route needs manual correction") }
                }
                # Return input path and interlaced specifier params
                if ($iArg) { return "$quotedInput $iArg" }
                else { return $quotedInput }
            }
            'x264' { if ($iArg) { return "- $iArg" } else { return "-" } }
            'x265' { if ($iArg) { return "$iArg --input -" } else { return "--input -" } }
            'svtav1' { return "-i -" } # SVT-AV1 natively doesn't support interlaced
        }
        break
    }
    else { # Export mode
        switch -Wildcard ($program) {
            'x264' { return "--output $quotedOutput" }
            'x265' { return "--output $quotedOutput" }
            'svtav1' { return "-b $quotedOutput" }
            default { throw "Unidentified program: $program" }
        }
    }
    throw "Could not generate IO parameter for: $program"
}

# Retrieve basic x264 parameters
function Get-x264BaseParam {
    Param (
        [Parameter(Mandatory=$true)]$pickOps,
        [switch]$askUserCRF,
        [switch]$askUserFGO
    )

    $isHelp = $pickOps -in @('helpzh', 'helpen')
    $enableFGO = $false
    if ($askUserFGO -and -not $isHelp) {
        Write-Host ''
        Write-Host " Some modified x264 supports high-freq rate-distortion opt. (Film Grain Opt.), enabling is recommended" -ForegroundColor Cyan
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
    $fgo10 = if ($enableFGO) {" --fgo 10"} else { "" }
    $fgo15 = if ($enableFGO) {" --fgo 15"} else { "" }

    $crfParam = "--crf 23" # else default
    if ($askUserCRF -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "Configure x264 constant rate factor (CRF) in positive integer"

        while ($true) {
            $crf = Read-Host " [13-16：UHQ | 18-20：HQ | 21-24：Stream media | 0：Lossless | Enter：x264 default(23)]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " Using default CRF：23"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " Input is not positive integer. Press Enter to retry, input 'q' to force exit"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 0 -or $crfInt -gt 51) {
                $choice = Read-Host " Input is out of 0-51 range. Press Enter to retry, input 'q' to force exit"
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
        # General Purpose，bframes 14
        a {return $default}
        # Stock Footage for Editing，bframes 12
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
            Show-Info "Get-x264BaseParam: Using default encoder parameter"
            return $default
        }
    }
}

# Retrieve basic x265 parametersffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | x265.exe [Get-...] [Get-x265BaseParam] --y4m --input - --output ".\out.hevc"
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
        Show-Info "Configure x265 constant rate factor (CRF) in positive integer"

        while ($true) {
            $crf = Read-Host " [17-20：UHQ | 21-25：HQ | 26-30：Stream media | 0：Lossless | Enter：x265 default (28)]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " Using default CRF：28"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " Input is not positive integer. Press Enter to retry, input 'q' to force exit"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 0 -or $crfInt -gt 51) {
                $choice = Read-Host " Input is out of 0-51 range. Press Enter to retry, input 'q' to force exit"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            $crfParam = "--crf $crf"
            break
        }
    }

    switch ($pickOps) {
        # General Purpose，bframes 5
        a {return $default}
        # Movie，bframes 8
        b {return "--high-tier --ctu 64 --tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --rect --tskip --tskip-fast --me star --weightb --ref 4 --max-merge 5 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --b-intra $crfParam --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1.1 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3"} 
        # Stock Footage，bframes 7
        c {return "--high-tier --ctu 32 --tskip --me star --max-merge 5 --early-skip --b-intra --no-open-gop --min-keyint 1 --ref 3 --fades --bframes 7 --b-adapt 2 $crfParam --crqpoffs -3 --cbqpoffs -2 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --splitrd-skip --deblock -1:-1 --tune grain"}
        # Anime，bframes 16
        d {return "--high-tier --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --tskip --tskip-fast --me umh --weightb --max-merge 5 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --bframe-bias 20 --constrained-intra --b-intra $crfParam --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --deblock -1:0 --limit-sao --sao-non-deblock"}
        # Exhausive
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
            Show-Info "Get-x265BaseParam: Using default encoder parameter"
            return $default
        }
    }
}

# Retrieve basic SVT-AV1 parameters: ffmpeg.exe -y -i ".\in.mp4" -an -f yuv4mpegpipe -strict -1 - | SvtAv1EncApp.exe -i - [Get-svtav1BaseParam] -b ".\out.ivf"
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

    $crfParam = "--crf 35" # else default
    if ($askUserCRF -and -not $isHelp) {
        Write-Host ("─" * 50)
        Show-Info "Configure SVT-AV1 constant rate factor (CRF) in positive integer"

        while ($true) {
            $crf = Read-Host " [28-32：UHQ | 33-36：HQ | 37-40：Stream media | 1：Lossless | Enter：SVT-AV1 default (35)]"

            if ([string]::IsNullOrEmpty($crf)) {
                Write-Host " Using default CRF：35"
                break
            }

            [int]$crfInt = 0
            if (-not [int]::TryParse($crf, [ref]$crfInt)) {
                $choice = Read-Host " Input is not positive integer, Press Enter to retry, input 'q' to force exit"
                if ($choice -eq 'q') { exit 1 }
                continue
            }
            elseif ($crfInt -lt 1 -or $crfInt -gt 70) {
                $choice = Read-Host "  Input is out of 1-70 range, Press Enter to retry, input 'q' to force exit"
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
            Write-Host " Select a custom preset for SVT-AV1——[a: HQ | b: High compression | c: Fast]" -ForegroundColor Yellow
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
            break
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
        [Parameter(Mandatory=$true)][string]$fpsString,
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
    [double]$fps = ConvertTo-Fraction $fpsString

    $userSecond = $null # User specified seconds
    if ($askUser) {
        if ($isx264) {
            Write-Host ''
            Show-Info "Please specify maximum keyframe interval for x264 in seconds"
            Write-Host " positive integer, not frame count, i.e. 11 seconds: 11" -ForegroundColor DarkGray
        }
        elseif ($isx265) {
            Write-Host ''
            Show-Info "Please specify maximum keyframe interval for x265 in seconds"
            Write-Host " positive integer, not frame count, i.e. 12 seconds: 12" -ForegroundColor DarkGray
        }
        elseif ($isSVTAV1) {
            Write-Host ''
            Show-Info "Please specify maximum keyframe interval for SVT-AV1 in seconds"
            Write-Host " positive integer, not frame count, i.e. 13 seconds: 13" -ForegroundColor DarkGray
        }
        else {
            throw "Maximum keyframe interval parameter is missing, cannot proceed"
        }
        Write-Host ''
        
        $userSecond = $null
        do { # Decoding usage for video editing is the sum of the keyframe interval of all video tracks
            # However, the real-world decoding capability depends mostly on the # of hardware decoders,
            # so only setting to 2x default
            Write-Host " 1. Resolutions greater than 2560x1440, pick | ← |"
            Write-Host " 2. For simple & flat video content, pick | → |"
            $userSecond =
                Read-Host " Specify second: [Low Power/Multitrack Editing: 6-7 | 8-10 | High: 11-13+ ]"
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
        [Parameter(Mandatory=$true)][string]$fpsString,
        [Parameter(Mandatory=$true)][int]$bframes,
        [double]$second = 1.8
    )
    try {
        $frames = [math]::Round(((ConvertTo-Fraction $fpsString) * $second))
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

# Get submotion estimation parameter value based on video frame rate
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
    if ($null -eq $CSVw -or $null -eq $CSVh) {
        throw "Get-InputResolution：source video comes without frame size (width-height) metadata"
    }
    if ($isSVTAV1) {
        return "-w $CSVw -h $CSVh"
    }
    return "--input-res ${CSVw}x${CSVh}"
}

# Added support for fractional fps value in SVT-AV1 (directly preserved fraction strings)
function Get-FPSParam {
    Param (
        [Parameter(Mandatory=$true)]$fpsString,
        [Parameter(Mandatory=$true)]
        [ValidateSet("ffmpeg","x264","avc","x265","hevc","svtav1","SVT-AV1")]
        [string]$Target
    )
    if ([string]::IsNullOrWhiteSpace($fpsString)) {
        throw "Get-FPSParam：source video comes without framerate metadata"
    }
    # SVT-AV1's case: use --fps-num & --fps-denom instead
    if ($Target -in @("svtav1", "SVT-AV1")) {
        if ($fpsString -match '^(\d+)/(\d+)$') {
            # Fractional fps, i.e., 24000/1001
            return "--fps-num $($matches[1]) --fps-denom $($matches[2])"
        }
        else { # Direct input in float, restore to fraction
            switch ($fpsString) {
                "23.976" { return "--fps-num 24000 --fps-denom 1001" }
                "29.97"  { return "--fps-num 30000 --fps-denom 1001" }
                "59.94"  { return "--fps-num 60000 --fps-denom 1001" }
                default  { # Use integer for other values
                    try {
                        $intFps = [Math]::Round([double]$fpsString)
                    }
                    catch [System.Management.Automation.RuntimeException] {
                        throw "Get-FPSParam: Unable to convert fpsString: '$fpsString' to number"
                    }
                    return "--fps $intFps" 
                }
            }
        }
    }
    
    # x264、x265、ffmpeg supports direct string fps value
    switch ($Target) {
        'ffmpeg' { return "-r $fpsString" }
        default  { return "--fps $fpsString" }
    }
}

# Get color matrix, trasnfer characteristics and color primaries
function Get-ColorSpaceSEI {
    Param (
        [Parameter(Mandatory=$true)]$CSVColorMatrix,
        [Parameter(Mandatory=$true)]$CSVTransfer,
        [Parameter(Mandatory=$true)]$CSVPrimaries,
        [switch]$isx264,
        [switch]$isx265,
        [switch]$isSVTAV1
    )
    $result = @()
    if (($isx264 -and $isx265) -or ($isx264 -and $isSVTAV1) -or ($isx265 -and $isSVTAV1)) {
        throw "Get-ColorSpaceSEI：Invalid input, please specify one codec at a time"
    }

    if ($isx264) {
        # Colormatrix
        if (($CSVColorMatrix -eq "unknown") -or ($CSVColorMatrix -eq "bt2020nc")) {
            $result += "--colormatrix undef" # x264 不写 unknown
        }
        else { # fcc，bt470bg，smpte170m，smpte240m，GBR，YCgCo，bt2020c，smpte2085，chroma-derived-nc，chroma-derived-c，ICtCp
            $result += "--colormatrix $CSVColorMatrix"
        }

        # Transfer
        if ($CSVTransfer -eq "unknown") {
            # bt470m，bt470bg，smpte170m，smpte240m，linear，log100，log316，iec61966-2-4，bt1361e，iec61966-2-1，bt2020-10，bt2020-12，smpte2084，smpte428，arib-std-b67
            $result += "--transfer undef"
        }
        else {
            $result += "--transfer $CSVTransfer"
        }

        # Color Primaries
        if (($CSVPrimaries -eq "unknown") -or ($CSVPrimaries -eq "unspec")) {
            $result += "--colorprim undef"
        }
        else {
            $result += "--colorprim $CSVPrimaries"
        }
    }
    elseif ($isx265) {
        # Colormatrix
        if ($CSVColorMatrix -eq "bt2020nc") {
            $result += "--colormatrix unknown"
        }
        else { # ==x264
            $result += "--colormatrix $CSVColorMatrix"
        }

        # Transfer
        $result += "--transfer $CSVTransfer"

        # Color Primaries
        if (($CSVPrimaries -eq "unknown") -or ($CSVPrimaries -eq "unspec")) {
            $result += "--colorprim unknown"
        }
        else {
            $result += "--colorprim $CSVPrimaries"
        }
    }
    elseif ($isSVTAV1) {
        # Color Matrix
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
                Show-Warning "Get-ColorSpaceSEI：Unknown color matrix: $CSVColorMatrix, using default (bt709)"
                1
            }
        }
        $result += "--matrix-coefficients $c"

        # Transfer
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
                Show-Warning "Get-ColorSpaceSEI：Unknown transfer characteristics: $CSVTransfer, using default (bt709)"
                1
            }
        }
        $result += "--transfer-characteristics $t"

        # Color Primaries
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
                Show-Warning "Get-ColorSpaceSEI：Unknown color primaries: $CSVPrimaries, using default (bt709)"
                1
            }
        }
        $result += "--color-primaries $p"
    }
    else {
        Show-Warning "Get-ColorSpaceSEI：No codec specified, skipped colormatrix, trasnfer characteristics and color primaries' configuration"
        return ""
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
            if ($depth -eq 12) {
                Show-Warning "Get-RAWCSPBitDepth: detecting SVT-AV1-incompatible 12bit source format, re-run step 2 if SVT-AV1 is designated"
                Write-Host ("─" * 50)
            }

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

# Determine if file is VOB format ASAP (determined by the previous script, and written to filename)
# this redefines the $ffprobeCSV variable structure, which affects numerous subsequent parameters
function Set-IsVOB {
    Param([Parameter(Mandatory=$true)][string]$ffprobeCsvPath)
    if ([string]::IsNullOrWhiteSpace($ffprobeCsvPath)) {
        throw "Set-IsVOB: parameter ffprobeCsvPath is empty, cannot detect"
    }
    $script:interlacedArgs.isVOB = $ffprobeCsvPath -like "*_vob*"
}

# Determine if file is MOV format ASAP (determined by the previous script, and written to filename)
# this redefines the $ffprobeCSV variable structure, which affects numerous subsequent parameters
function Set-IsMOV {
    Param([Parameter(Mandatory=$true)][string]$ffprobeCsvPath)
    if ([string]::IsNullOrWhiteSpace($ffprobeCsvPath)) {
        throw "Set-IsMOV：ffprobeCsvPath is empty, cannot detect"
    }
    $script:interlacedArgs.isMOV = $ffprobeCsvPath -like "*_mov*"
}

function Set-InterlacedArgs {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$fieldOrderOrIsInterlacedFrame, # VOB: $ffprobe.H；Other: $ffprobeCsv.J
        [string]$tffAttribute # !MOV & !VOB: $ffprobeCsv.K
    )
    # Initialize
    $script:interlacedArgs.isInterlaced = $false
    $script:interlacedArgs.isTFF = $false

    # Process VOB, MOV fromat
    if ($script:interlacedArgs.isVOB) {
        $fieldOrder = $fieldOrderOrIsInterlacedFrame.ToLower().Trim()
        
        switch -Regex ($fieldOrder) {
            '^progressive$' {
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            '^(tt|bt)$' { # tt: Top field first display, bt: Bottom encoding top displaying
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $true
            }
            '^(bb|tb)$' { # bb: Bottom field first display, tb: Top encoding bottom displaying
                $script:interlacedArgs.isInterlaced = $true
                $script:interlacedArgs.isTFF = $false
            }
            '^unknown$' {
                Show-Warning "Set-InterlacedArgs: VOB field_order is 'unknown', taking as progressive"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            { [string]::IsNullOrWhiteSpace($fieldOrder) } {
                Show-Warning "Set-InterlacedArgs: VOB field_order is empty, taking as progressive"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
            default {
                Show-Warning "Set-InterlacedArgs: Unusual VOB field_order='$fieldOrder', taking as progressive"
                $script:interlacedArgs.isInterlaced = $false
                $script:interlacedArgs.isTFF = $false
            }
        }
    }
    else { # Non-VOB/MOV format, analyze interlaced_frame (0/1)
        $interlacedFrame = $fieldOrderOrIsInterlacedFrame.Trim()
        
        if ([string]::IsNullOrWhiteSpace($interlacedFrame)) {
            Show-Warning "Set-InterlacedArgs: Empty interlaced_frame field, taking as progressive"
            $script:interlacedArgs.isInterlaced = $false
        }
        else {
            try {
                $interlacedInt = [int]::Parse($interlacedFrame)
                $script:interlacedArgs.isInterlaced = ($interlacedInt -eq 1)
            }
            catch {
                Show-Warning "Set-InterlacedArgs: Unusual interlaced_frame value '$interlacedFrame', taking as progressive"
                $script:interlacedArgs.isInterlaced = $false
            }
        }
        
        # Analyze top_field_first (-1/0/1)
        $tff = $tffAttribute.Trim()
        
        if ([string]::IsNullOrWhiteSpace($tff)) {
            if ($script:interlacedArgs.isInterlaced) {
                Show-Warning "Set-InterlacedArgs: Unknown field order and video is interlaced, assuming top field first"
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
                        Show-Warning "Set-InterlacedArgs: Unusual top_field_first value '$tffInt', taking as top field first"
                        $script:interlacedArgs.isTFF = $true
                    }
                }
            }
            catch {
                Show-Warning "Set-InterlacedArgs: Unknown top_field_first='$tff', taking as top field first"
                $script:interlacedArgs.isTFF = $true
            }
        }
    }
    
    Show-Debug "Set-InterlacedArgs—Interlaced: $($script:interlacedArgs.isInterlaced), Top-field-first: $($script:interlacedArgs.isTFF)"
}

# Splice final parame by non-empty apptributes
function Join-Params ($Object, $PropertyOrder) {
    $values = foreach ($prop in $PropertyOrder) { $Object.$prop }
    return ($values -match '\S' -join " ").Trim()
}

#region Main
function Main {
    Show-Border
    Write-Host "Video encoding task gnerator" -ForegroundColor Cyan
    Show-Border
    Write-Host ''

    # 1. Locate the latest ffprobe CSV and read the video information
    $ffprobeCsvPath = 
        Get-ChildItem -Path $Global:TempFolder -Filter "temp_v_info*.csv" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 | 
        ForEach-Object { $_.FullName }

    if ($null -eq $ffprobeCsvPath) {
        throw "Video CSV file from ffprobe (step 3) is missing; Please complete step 3 script"
    }

    # 2. Locate source CSV
    $sourceInfoCsvPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    if (-not (Test-Path $sourceInfoCsvPath)) {
        throw "Stream CSV file from ffprobe (step 3) is missing; Please complete step 3 script"
    }

    Write-Host ("─" * 50)
    
    Show-Info "Reading ffprobe data: $(Split-Path $ffprobeCsvPath -Leaf)..."
    Show-Info "Reading source data: $(Split-Path $sourceInfoCsvPath -Leaf)..."
    $ffprobeCSV =
        Import-Csv $ffprobeCsvPath -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA,AB,AC,AD,AE,AF,AG,AH,AI,AJ
    $sourceCSV =
        Import-Csv $sourceInfoCsvPath -Header SourcePath,UpstreamCode,Avs2PipeModDllPath,SvfiInputConf,SvfiTaskId

    # Validate CSV data
    if (-not $sourceCSV.SourcePath) { # Validate CSV field existance, no quote needed
        throw "temp_s_info CSV data corrupted. Please rerun step 3 script"
    }

    Write-Host ("─" * 50)

    # Interlaced source support
    # ffmpeg, vspipe, avs2yuv, svfi: Ignore
    # avs2pipemod: y4mp, y4mt, y4mb (progressive, tff, bff)
    # x264: --tff, --bff
    # x265: --interlace 0 (progressive), 1 (tff), 2 (bff)
    # SVT-AV1: Natively unsupported, show error and exit
    Show-Info "Detecting interlaced formats..."
    Set-IsVOB -ffprobeCsvPath $ffprobeCsvPath
    Set-IsMOV -ffprobeCsvPath $ffprobeCsvPath

    # MOV, VOB formats' field order data is in H
    if (-not $script:interlacedArgs.isMOV -and -not $script:interlacedArgs.isVOB) {
        Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $ffprobeCSV.H -tffAttribute $ffprobeCSV.J
    }
    else {
        Set-InterlacedArgs -fieldOrderOrIsInterlacedFrame $ffprobeCSV.H
    }

    Write-Host ("─" * 50)
    
    # Calculate and assign to object properties
    Show-Info "Optimizing encoding parameters..."
    # $x265Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $false
    # $svtav1Params.Profile = Get-x265SVTAV1Profile -CSVpixfmt $ffprobeCSV.D -isIntraOnly $false -isSVTAV1 $true
    $x265Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C
    $svtav1Params.Resolution = Get-InputResolution -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C -isSVTAV1 $true
    $x265Params.MERange = Get-x265MERange -CSVw $ffprobeCSV.B -CSVh $ffprobeCSV.C

    # Show-Debug "Color matrix: $($ffprobeCSV.E); Transfer: $($ffprobeCSV.F); Primaries: $($ffprobeCSV.G)"
    $x264Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -isx264
    $x265Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -isx265
    $svtav1Params.SEICSP = Get-ColorSpaceSEI -CSVColorMatrix $ffprobeCSV.E -CSVTransfer $ffprobeCSV.F -CSVPrimaries $ffprobeCSV.G -isSVTAV1

    # VOB format—frame count: J
    $x265Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $x264Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $false
    $svtav1Params.TotalFrames = Get-FrameCount -ffprobeCSV $ffprobeCSV -isSVTAV1 $true

    # x265 Threading
    $x265Params.PME = Get-x265PME
    $x265Params.Pools = Get-x265ThreadPool

    # Obtain color space format
    $avs2yuvVersionCode = 'a'
    if ($sourceCSV.UpstreamCode -eq 'c') {
        Write-Host ''
        Show-Info "Please select the version of avs2yuv(64).exe used:"
        $avs2yuvVersionCode = Read-Host " [Default Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
    }
    $ffmpegParams.CSP = Get-ffmpegCSP -CSVpixfmt $ffprobeCSV.D
    $svtav1Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $true
    $x265Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $x264Params.RAWCSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $true -isAvs2YuvInput $false -isSVTAV1 $false
    $avsyuvParams.CSP = Get-RAWCSPBitDepth -CSVpixfmt $ffprobeCSV.D -isEncoderInput $false -isAvs2YuvInput $true -isSVTAV1 $false -isAVSPlus ($avs2yuvVersionCode -eq 'a')

    # VOB、MOV framerate data is located at .I，otherwise it would be .H
    $ffFpsString =
        if ($script:interlacedArgs.isVOB -or $script:interlacedArgs.isMOV) { $ffprobeCSV.I }
        else { $ffprobeCSV.H }
    # Show-Debug "Source is VOB mux：$($script:interlacedArgs.isVOB)"
    # Show-Debug "Source is MOV mux：$($script:interlacedArgs.isMOV)"
    # Show-Debug "FPS：$ffFpsString"
    $ffmpegParams.FPS = Get-FPSParam -fpsString $ffFpsString -Target ffmpeg
    $svtav1Params.FPS = Get-FPSParam -fpsString $ffFpsString -Target svtav1
    $x265Params.FPS = Get-FPSParam -fpsString $ffFpsString -Target x265
    $x264Params.FPS = Get-FPSParam -fpsString $ffFpsString -Target x264
    $x265Params.Subme = Get-x265SubmotionEstimation -fpsString $ffFpsString
    [int]$x265SubmeInt = Get-x265SubmotionEstimation -fpsString $ffFpsString -stripParameterName
    $x264Params.Keyint = Get-Keyint -fpsString $ffFpsString -bframes 250 -askUser -isx264
    $x265Params.Keyint = Get-Keyint -fpsString $ffFpsString -bframes $x265SubmeInt -askUser -isx265
    $svtav1Params.Keyint = Get-Keyint -fpsString $ffFpsString -bframes 999 -askUser -isSVTAV1
    $x264Params.RCLookahead = Get-RateControlLookahead -fpsString $ffFpsString -bframes 250
    $x265Params.RCLookahead = Get-RateControlLookahead -fpsString $ffFpsString -bframes $x265SubmeInt

    Write-Host ("─" * 50)

    # Avs2PipeMod's required DLL
    $quotedDllPath = Get-QuotedPath $sourceCSV.Avs2PipeModDllPath
    $avsmodParams.DLLInput = "-dll $quotedDllPath"

    # SVFI's required INI file & Task ID
    $olsargParams.ConfigInput =
        if (![string]::IsNullOrWhiteSpace($sourceCSV.SvfiInputConf)) {
            "--config $(Get-QuotedPath $sourceCSV.SvfiInputConf) --task-id $($sourceCSV.SvfiTaskId)"
        }
        else { '' }

    Write-Host ''
    Show-Info "Configure output path, filename..."
    $encodeOutputPath = Select-Folder -Description "Select output path for encoder file output"
    # 1. Get source filename (pass to selection function as an option)
    $sourcePathRaw = $sourceCSV.SourcePath
    $defaultNameBase = [System.IO.Path]::GetFileNameWithoutExtension($sourcePathRaw)
    # 2. Check if is a placeholder script source
    $isPlaceholder = Get-IsPlaceHolderSource -defaultName $defaultNameBase
    # 3. Get the final filename (all interactions, validations, and retries are done within the function).
    $encodeOutputFileName = Get-EncodeOutputName -SourcePath $sourcePathRaw -IsPlaceholder $isPlaceholder

    # All encoders are getting parameters, therefore warn compatibility issues not don't quit
    if ($script:interlacedArgs.isInterlaced -and
        $program -in @('x265', 'h265', 'hevc', 'svt-av1', 'svtav1', 'ivf')) {
        Show-Info "Get-EncodingIOArgument: SVT-AV1 natively reject interlaced source; x265 interlaced support is experimental (official version)"
        Show-Info ("Deinterlacing & IVTC filtering tutorial: " + $script:interlacedArgs.toPFilterTutorial)
        Write-Host ''
    }

    Show-Info "Generate IO Parameters (Input/Output)..."
    # 1. Upstream Program Input of the Pipe
    # The pipe connector is controlled by the batch generated by the previous script,
    # and is not specified here.
    $ffmpegParams.Input = Get-EncodingIOArgument -isffmpeg -isImport $true -source $sourceCSV.SourcePath
    $vspipeParams.Input = Get-EncodingIOArgument -isVsPipe -isImport $true -source $sourceCSV.SourcePath
    $avsyuvParams.Input = Get-EncodingIOArgument -isAvs2Yuv -isImport $true -source $sourceCSV.SourcePath
    $avsmodParams.Input = Get-EncodingIOArgument -isAvs2Pipemod -isImport $true -source $sourceCSV.SourcePath
    $olsargParams.Input = Get-EncodingIOArgument -isSVFI -isImport $true -source $sourceCSV.SourcePath
    # 2. Downstream program (encoder) input
    # requires interlaced specifier parameters, using Get-EncodingIOArgument is mandatory
    $x264Params.Input = Get-EncodingIOArgument -isx264 -isImport $true -source $sourceCSV.SourcePath
    $x265Params.Input = Get-EncodingIOArgument -isx265 -isImport $true -source $sourceCSV.SourcePath
    $svtav1Params.Input = Get-EncodingIOArgument -isSVTAV1 -isImport $true -source $sourceCSV.SourcePath
    # 3. Pipe downstream program output
    $x264Params.Output = Get-EncodingIOArgument -isx264 -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x264Params.OutputExtension
    $x265Params.Output = Get-EncodingIOArgument -isx265 -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $x265Params.OutputExtension
    $svtav1Params.Output = Get-EncodingIOArgument -isSVTAV1 -isImport $false -outputFilePath $encodeOutputPath -outputFileName $encodeOutputFileName -outputExtension $svtav1Params.OutputExtension

    Write-Host ("─" * 50)

    Show-Info "Constructing base parameters of the pipe downstream programs..."
    $x264Params.BaseParam = Invoke-BaseParamSelection -CodecName "x264" -GetParamFunc ${function:Get-x264BaseParam} -ExtraParams @{ askUserFGO = $true; askUserCRF = $true }
    $x265Params.BaseParam = Invoke-BaseParamSelection -CodecName "x265" -GetParamFunc ${function:Get-x265BaseParam} -ExtraParams @{ askUserCRF = $true }
    $svtav1Params.BaseParam = Invoke-BaseParamSelection -CodecName "SVT-AV1" -GetParamFunc ${function:Get-svtav1BaseParam} -ExtraParams @{ askUserDLF = $true; askUserCRF = $true }

    Show-Info "Concatenating final parameter string..."
    # These strings will be directly injected into the batch file "set 'xxx_params=...'"
    # Empty parameters may result in double spaces, but paths and filenames may also contain double spaces, so they are not filtered (-replace " ", " ")
    # 1. Pipeline upstream tool
    $ffmpegFinalParam = Join-Params $ffmpegParams @('FPS', 'Input', 'CSP', 'LogLevel')
    $vspipeFinalParam = Join-Params $vspipeParams @('Input')
    $avsyuvFinalParam = Join-Params $avsyuvParams @('Input', 'CSP')
    $avsmodFinalParam = Join-Params $avsmodParams @('Input', 'DLLInput')
    $olsargFinalParam = Join-Params $olsargParams @('Input', 'ConfigInput')
    # 2. x264 (Input located in the end), x265, SVT-AV1
    $x264FinalParam = Join-Params $x264Params @('Keyint', 'SEICSP', 'BaseParam', 'Output', 'Input')
    $x265FinalParam = Join-Params $x265Params @('Keyint', 'SEICSP', 'RCLookahead', 'MERange', 'Subme', 'PME', 'Pools', 'BaseParam', 'Input', 'Output')
    $svtav1FinalParam = Join-Params $svtav1Params @('Keyint', 'SEICSP', 'BaseParam', 'Input', 'Output')
    # 3. RAW Pipe Appendix
    $x264RawPipeApdx = Join-Params $x264Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    $x265RawPipeApdx = Join-Params $x265Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    $svtav1RawPipeApdx = Join-Params $svtav1Params @('FPS', 'RAWCSP', 'Resolution', 'TotalFrames')
    # 4. RAW pipe mode
    if (Get-IsRAWSource -validateUpstreamCode $sourceCSV.UpstreamCode) {
        $x264FinalParam = "$x264RawPipeApdx $x264FinalParam"
        $x265FinalParam = "$x265RawPipeApdx $x265FinalParam"
        $svtav1FinalParam = "$svtav1RawPipeApdx $svtav1FinalParam"
    }

    #  Generate ffmpeg, vspipe, avs2yuv, avs2pipemod encoding task batch
    Write-Host ''
    Show-Info "Locate the encode_template.bat template..."
    $templateBatch = $null
    while (-not $templateBatch) {
        $templateBatch = Select-File -Title "Select encode_template.bat" -BatOnly
        
        if (-not $templateBatch) {
            if ((Read-Host "No file selected. Press Enter to retry, input 'q' to force exit") -eq 'q') {
                return
            }
        }
    }

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

    # Replacement anchor is keeping Chinese anchor for code simplicity
    # Strategy: find the "REM Parameter examples" block and replace it with $paramsBlock.
    # If the template changed, stop script execution
    $newBatchContent = $batchContent

    # Patterns to match
    $enAnchor = '(?msi)^REM\s+Parameter\s+examples\b'
    $zhcnAnchor = '(?msi)^REM\s+参数示例\b'
    $zhtwAnchor = '(?msi)^REM\s+參數範例\b'

    # Match from "REM Parameter examples" up to (but not including) the "REM Specify commandline" line.
    # Prefer English pattern; if English not present but Chinese present, use Chinese pattern.
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
        throw "The placeholder missing in template generated by step 2. Please re-run step 2 script."
    }
    # Perform the replacement. Use [regex]::Replace to ensure .NET regex behavior.
    $newBatchContent = [regex]::Replace($batchContent, $pattern, $paramsBlock)

    # Save final batch
    $finalBatchPath = Join-Path (Split-Path $templateBatch) "encode_task_final.bat"
    Show-Debug "Exporting file: $finalBatchPath"
    Write-Host ''
    
    try {
        Confirm-FileDelete $finalBatchPath
        Write-TextFile -Path $finalBatchPath -Content $newBatchContent -UseBOM $true

        # Validate line breaks, must be CRLF
        Show-Debug "Validating batch file format..."
        if (-not (Test-TextFileFormat -Path $finalBatchPath)) {
            return
        }
    
        Show-Success "Task generated successfully!"
        Write-Host ''

        Write-Host ("─" * 50)
        
        Show-Info "Usages for generated batch files："
        Write-Host "1. Run encode_task_final.bat to start encoding"
        Write-Host "2. You may keep encode_template.bat to skip Step 2 in future encodings,"
        Write-Host "   as long as the tool chain remains the same"
        Write-Host "3. You can manually swap different commands in encode_template.bat"
        Write-Host "   to switch upstream and downstream encoding tools or routes"
        Write-Host ("─" * 50)
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