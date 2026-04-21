<#
.SYNOPSIS
    FFProbe source analyzer script
.DESCRIPTION
    Analyzes the source video and exports file to %USERPROFILE%\temp_v_info(_is_mov).json, i.e., width, height, csp info, sei info, etc.
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.7
#>

# If both temp_v_info_is_mov.json and temp_v_info.json are detected, use the file created latest

# Load globals, including $utf8NoBOM、Get-QuotedPath、Select-File、Select-Folder...
. "$PSScriptRoot\Common\Core.ps1"

# Parameters for video readings
$fpsParams = [PSCustomObject]@{
    rNumerator = [int]0 # Base frame rate
    rDenumerator = [int]0
    rDouble = [double]0
    aNumerator = [int]0 # Average frame rate
    aDenumerator = [int]0
    aDouble = [double]0
}

# Script file path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Collect and update the base frame rate, average frame rate,
# total number of frames, and total duration data of the video source.
function Set-FpsParams {
    param(
        [Parameter(Mandatory=$true)][string]$rFpsString,
        [Parameter(Mandatory=$true)][string]$aFpsString
    )
    $rFpsString = $rFpsString.Trim()
    $aFpsString = $aFpsString.Trim()
    $fpsRegex = '^\s*(\d+)\s*/\s*(\d+)\s*$'

    # Add denominator for integer frame rate 
    if ($rFpsString -notmatch "/") { $rFpsString += "/1" }
    if ($aFpsString -notmatch "/") { $aFpsString += "/1" }
    
    # Handle base frame rate
    if ($rFpsString -match $fpsRegex) {
        $rNum = [int]$Matches[1]
        $rDnm = [int]$Matches[2]
        if ($rDnm -eq 0) { throw "Base frame rate is dividing by 0" }
        $script:fpsParams.rNumerator = $rNum
        $script:fpsParams.rDenumerator = $rDnm
        $script:fpsParams.rDouble = [double]$rNum / $rDnm
    }
    
    # Handle average frame rate
    if ($aFpsString -match $fpsRegex) {
        $aNum = [int]$Matches[1]
        $aDnm = [int]$Matches[2]
        if ($aDnm -eq 0) { throw "Average frame rate is dividng by 0" }
        $script:fpsParams.aNumerator = $aNum
        $script:fpsParams.aDenumerator = $aDnm
        $script:fpsParams.aDouble = [double]$aNum / $aDnm
    }
    elseif ([double]::TryParse($aFpsString, [ref]$null)) {
        $aDouble = [double]$aFpsString
        $script:fpsParams.aNumerator = [int]($aDouble * 1000)
        $script:fpsParams.aDenumerator = 1000
        $script:fpsParams.aDouble = $aDouble
    }
}

# Detecting whether an integer is similar to a prime number，credit：buttondown.com/behind-the-powershell-pipeline/archive/a-prime-scripting-solution
function Test-IsLikePrime {
    param (
        [Parameter(Mandatory=$true)][int]$number,
        [int]$threshold = 5 # Threshold for the number of divisors is set
    )
    if ($number -lt 3) { throw "Test value must be greater than 3" }
    $t = 0
    for ($i=2; $i -le [math]::Sqrt($number); $i++) {
        if ($number % $i -eq 0) {
            $t++
        }
        if ($t -gt $threshold) {
            return $false
        }
    }
    return $true
}

# Modularized ffprobe information retrieval function
function Get-VideoStreamInfo {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource, # Do not supply quoted path
        [string]$showEntries = "stream"
    )
    if (-not (Test-NullablePath $ffprobePath)) {
        throw "Get-VideoStreamInfo: ffprobe.exe missing ($ffprobePath)"
    }
    if (-not (Test-NullablePath $videoSource)) {
        throw "Get-VideoStreamInfo: Video source missing ($videoSource)"
    }
    
    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-select_streams', 'v:0',
        '-show_entries', $showEntries,
        '-of', 'json', $videoSource
    )
    
    # Switch to UTF-8 text encoding temporarily to capture ffprobe output
    $prevOut = [Console]::OutputEncoding
    $prevPS = $OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $ffprobeJson = &$ffprobePath @ffprobeArgs 2>$null
    }
    finally {
        [Console]::OutputEncoding = $prevOut
        $OutputEncoding = $prevPS
    }

    if ($LASTEXITCODE -ne 0 -or -not $ffprobeJson) {
        throw "Get-VideoStreamInfo: ffprobe failed or did not return any valid data"
    }

    try {
        $streamInfo = $ffprobeJson | ConvertFrom-Json
    }
    catch {
        Write-Host $ffprobeJson
        throw "Get-VideoStreamInfo: Invalid JSON returned by ffprobe"
    }

    if (-not $streamInfo.streams -or $streamInfo.streams.Count -lt 1) {
        throw "Get-VideoStreamInfo: Could not find video stream data"
    }

    return $streamInfo.streams[0]
}

# 检测并警告可变帧率以及非方形像素变宽比存在，并提供修复建议
function Test-VideoWarnings {
    param (
        [Parameter(Mandatory=$true)]$ffprobeStreamInfo,
        [double]$RelativeTolerance = 0.000000001,
        [Parameter(Mandatory=$true)][string]$quotedVideoSource
    )

    function Write-NoticeBlock {
        param(
            [Parameter(Mandatory=$true)][string]$Title,
            [Parameter(Mandatory=$true)][object[]]$Lines
        )

        Show-Warning $Title
        foreach ($line in $Lines) {
            if ($line -is [hashtable]) {
                Write-Host $line.Text -ForegroundColor $line.Color
            }
            else {
                Write-Host $line -ForegroundColor Yellow
            }
        }
    }

    try {
        $warningBlocks = @()

        # 1) First update fps
        try {
            Set-FpsParams `
                -rFpsString ([string]$ffprobeStreamInfo.r_frame_rate).Trim() `
                -aFpsString ([string]$ffprobeStreamInfo.avg_frame_rate).Trim()
        }
        catch {
            Show-Warning "Test-VideoWarnings: invalid or empty video framerate, could not analyze"
        }

        $rFps = $script:fpsParams.rDouble
        $aFps = $script:fpsParams.aDouble
        $nbFrames = 0
        $duration = 0

        try {
            $nbFrames = [int]$ffprobeStreamInfo.nb_frames.Trim()
            $duration = [double]$ffprobeStreamInfo.duration.Trim()
        }
        catch {
            Show-Info "Test-VideoWarnings: Invalid total frames & duration, video encoder will not show ETA"
        }

        $eFps = $null
        if ($nbFrames -gt 0 -and $duration -gt 0) {
            $eFps = $nbFrames / $duration
        }

        # 2) VFR check
        $vReasons = @()
        $score = 0

        if ($rFps -gt 0 -and $aFps -gt 0) {
            $relDiff = [math]::Abs($rFps - $aFps) / [math]::Max(1e-9, [math]::Max($rFps, $aFps))
            if ($relDiff -gt $RelativeTolerance) {
                $score += 1
                $vReasons += "Base fps ($rFps) differs from avg. fps ($aFps)"
            }
        }

        if ($null -ne $eFps -and $aFps -gt 0) {
            $relDiff2 = [math]::Abs($eFps - $aFps) / [math]::Max(1e-9, [math]::Max($eFps, $aFps))
            if ($relDiff2 -gt $RelativeTolerance) {
                $score += 2
                $vReasons += "Estimated fps ($eFps) differs from avg. fps ($aFps)"
            }
        }

        if ($ffprobeStreamInfo.r_frame_rate -eq "90000/1") {
            $score += 3
            $vReasons += "Characteristical r_frame_rate (90000) indicates VFR container"
        }

        $aDnm = $script:fpsParams.aDenumerator
        if ($aDnm -gt 50000) {
            if (Test-IsLikePrime -number $aDnm) {
                $score += 2
                $vReasons += "Relatively big, prime-like average fps denumerator ($aDnm)"
            }
            else {
                $score += 1
                $vReasons += "Relatively big average fps denumerator ($aDnm)"
            }
        }

        $mode = "[IS] Constant frame rate (CFR)"
        if ($score -ge 5)     { $mode = "[IS] Variable frame rate (VFR)" }
        elseif ($score -ge 4) { $mode = "[LIKELY IS] Variable frame rate (VFR)" }
        elseif ($score -ge 2) { $mode = "[SUGGESTS] Variable frame rate (VFR)" }
        elseif ($score -gt 0) { $mode = "[FAINTLY HINTS] Variable frame rate (VFR)" }

        if ($score -gt 0) {
            $rNum = $script:fpsParams.rNumerator
            $rDnm = $script:fpsParams.rDenumerator

            $lines = @()
            $lines += ($vReasons | ForEach-Object { "   - $_" })
            $lines += "  Please convert source to constant frame rate, or attach ffmpeg/VS/AVS filters in generated batch (Step 4)"
            $lines += " i.e. Render and encode to FFV1 lossless video:"
            $lines += @{ Text = "   - ffmpeg -i $quotedVideoSource -r $rNum/$rDnm -c:v ffv1 -level 3 -context 1 -g 180 -c:a copy output.mkv"; Color = "Magenta" }
            $lines += " Measure video frame to detect VFR:"
            $lines += @{ Text = "   - ffmpeg -i $quotedVideoSource -vf vfrdet -an -f null -"; Color = "Magenta" }
            $lines += @{ Text = "   - identify with [Parsed_vfrdet_0 @ 0000012a34b5cd00] VFR:0.xxx (yyy/zzz)"; Color = "Yellow" }
            $lines += @{ Text = "   - yyy: Frames with unmatching display durations"; Color = "Magenta" }

            $warningBlocks += [PSCustomObject]@{
                Title = "Source $mode, This program does not handle VFR alignment (Encoding leads to video-audio progressively misalign)"
                Lines = $lines
            }
        }

        # 3) SAR check
        $sampleAspectRatio = "1:1"
        try {
            $sampleAspectRatio = ([string]$ffprobeStreamInfo.sample_aspect_ratio).Trim()
        }
        catch {
            Show-Warning "Test-VideoWarnings: sample aspect radio (SAR) is missing or corrupted, defaulting to 1:1"
        }

        if ($sampleAspectRatio -notin @("1:1", "0:1")) {
            $warningBlocks += [PSCustomObject]@{
                Title = "$videoSource has a $sampleAspectRatio SAR (non-square pixel)"
                Lines = @(
                    " This program does not support SAR handling (encodes to square pixel, width shrinks)",
                    " Example fix:",
                    " 1. ffmpeg -i $quotedVideoSource -c copy -aspect $sampleAspectRatio output.mkv",
                    " 2. MP4Box -par 1=$sampleAspectRatio $quotedVideoSource -out output.mp4",
                    " 3. moviepy:",
                    "    from moviepy.editor import VideoFileClip",
                    "    clip = VideoFileClip($quotedVideoSource)",
                    "    clip.aspect_ratio = $sampleAspectRatio",
                    "    clip.write_videofile('output.mp4')"
                )
            }
        }

        # 4) Output
        if ($warningBlocks.Count -gt 0) {
            foreach ($block in $warningBlocks) {
                Write-NoticeBlock -Title $block.Title -Lines $block.Lines
                Write-Host ""
            }
            Read-Host " Press any key to continue..." | Out-Null
        }
        else {
            Show-Success "Source [IS] Constant frame rate (CFR), and uses square pixel format"
        }
    }
    catch { throw ("Test-VideoWarnings：" + $_) }
}

# Use ffprobe to detect the actual video file container format, ignoring the file extension (the container format is represented by uppercase letters)
function Test-VContainerFormat {
    param (
        [Parameter(Mandatory = $true)][string]$ffprobePath,
        [Parameter(Mandatory = $true)][string]$videoSource # Do not supply quoted path
    )
    Show-Info "Test-VContainerFormat: Validating if container format is genuine..."
    
    # Temporarily change text encoding
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    if (-not (Test-Path -LiteralPath $ffprobePath)) {
        throw "Test-VContainerFormat: ffprobe.exe does not exist ($ffprobePath)"
    }
    if (-not (Test-Path -LiteralPath $videoSource)) {
        throw "Test-VContainerFormat: Input video does not exist ($videoSource)"
    }

    # Get the file extension for subsequent logics
   $ext = [System.IO.Path]::GetExtension($videoSource)
    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-show_format',
        '-of', 'json', $videoSource
    )
    $ffprobeArgs2 = @(
        '-v', 'quiet', '-hide_banner', $videoSource
    )

    try { # Use JSON input for analysis
        $ffprobeJson = &$ffprobePath @ffprobeArgs 2>$null

        if ($LASTEXITCODE -eq 0) { # ffprobe exits normally, analysis results exist
            $formatInfo = $ffprobeJson | ConvertFrom-Json
            $formatName = $formatInfo.format.format_name

            # VOB format detection
            if ($formatName -match "mpeg") {
                # Further detection
                $ffprobeText = & $ffprobePath @$ffprobeArgs2 2>&1
                # Filename contains "VTS_" (unsure if all uppercase, so cmatch is not used)
                # $hasVTSFileName = $filename -match "^VTS_"
                # Metadata contains "dvd_nav; mpeg2video"
                $hasDVD = $ffprobeText -match "dvd_nav"
                $hasMPEG2 = $ffprobeText -match "mpeg2video"

                # VOBs typically contain DVD navigation packets or specific stream structures
                if ($hasDVD -or $hasMPEG2) {
                    Show-Success "Test-VContainerFormat: VOB format (DVD video) detected"
                    return "VOB"
                }

                Show-Warning "Test-VContainerFormat: Non-MPEG2 source, no DVD navigation identifier, assuming general container format"
                return "std"
            }

            # Mapping regular formats
            switch -Regex ($formatName) {
                "mov|mp4|m4a|3gp|3g2|mj2" {
                    if ($formatName -match "qt" -or $ext -eq ".mov") {
                        Show-Success "MOV container detected"
                        return "MOV"
                    }
                    Show-Success "MP4 container detected"
                    return "MP4"
                }
                "matroska" { Show-Success "MKV container detected"; return "MKV" }
                "webm"     { Show-Success "WebM container detected"; return "WebM" }
                "avi"      { Show-Success "AVI container detected"; return "AVI" }
                "ivf"      { Show-Success "IVF container detected"; return "ivf" }
                "hevc"     { Show-Success "HEVC H.265 raw stream detected"; return "hevc" }
                "h264|avc" { Show-Success "AVC H.264 raw stream detected"; return "avc" }
                "ffv1"     { Show-Success "FFV1 detected"; return "ffv1" }
            }
            return $formatName
        }
        else { # ffprobe failed
            throw "Test-VContainerFormat: ffprobe execution or JSON parsing failed"
        }
    }
    catch {
        throw ("Test-VContainerFormat: Detection failed" + $_)
    }
    finally { # 还原编码设置
        [Console]::OutputEncoding = $oldEncoding
    }
}

# Generate both AVS/VS script to %USERPROFILE%, allowing encoding to start when the scripts are not ready
function Get-BlankAVSVSScript {
    param([Parameter(Mandatory=$true)][string]$videoSource)

    # Get quotes on path
    $quotedImport = Get-QuotedPath $videoSource

    # Empty Script and Export Path
    $AVSScriptPath = Join-Path $Global:TempFolder "blank_avs_script.avs"
    $VSScriptPath = Join-Path $Global:TempFolder "blank_vs_script.vpy"
    # Generate AVS content (LWLibavVideoSource requires the path to be enclosed in double quotes)
    # libvslsmashsource.dll must exist in folder C:\Program Files (x86)\AviSynth+\plugins64+\
    $blankAVSScript = "LWLibavVideoSource($quotedImport) # Generated filter-less script, modify if needed"
    # Generate VapourSynth content (use raw string literal r"..." to avoid escaping issues)
    # If Get-QuotedPath returns strings like "C:\path\file.mp4", then modify r$quotedImport to r"C:\path\file.mp4"
    $blankVSScript = @"
import vapoursynth as vs
core = vs.core
src = core.lsmas.LWLibavSource(source=r$quotedImport)
# Add filters needed here
src.set_output()
"@

    try {
        Confirm-FileDelete $AVSScriptPath
        Confirm-FileDelete $VSScriptPath

        Show-Info "Generating filter-less script: `n $AVSScriptPath`n $VSScriptPath"
        Write-TextFile -Path $AVSScriptPath -Content $blankAVSScript -UseBOM $false
        Write-TextFile -Path $VSScriptPath -Content $blankVSScript -UseBOM $false
        Show-Success "Filter-less script created to %USERPROFILE%"

        # Check line breaks, must be CRLF for Windows
        Show-Debug "Validate script file format..."
        if (-not (Test-TextFileFormat -Path $AVSScriptPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $VSScriptPath)) {
            return
        }

        # Activate a script by previous selection
        return @{
            AVS = $AVSScriptPath
            VPY = $VSScriptPath
        }
    }
    catch {
        Show-Error ("Failed to create filter-less script: " + $_)
        return $null
    }
}

#region Main
function Main {
    $toolsJson = Join-Path $Global:TempFolder "tools.json"
    
    Show-Border
    Show-info (" ffprobe video analyzer, exports " + $Global:TempFolder + "temp_v_info(_is_mov).json`r`n for later scripts' reference")
    Show-Border
    Write-Host ''

    # Select source type based on upstream tool
    $sourceTypes = @{
        'A' = @{ Name = 'ffmpeg'; Ext = ''; Message = "Any source" }
        'B' = @{ Name = 'vspipe'; Ext = '.vpy'; Message = ".vpy source" }
        'C' = @{ Name = 'avs2yuv'; Ext = '.avs'; Message = ".avs source" }
        'D' = @{ Name = 'avs2pipemod'; Ext = '.avs'; Message = ".avs source" }
        'E' = @{ Name = 'SVFI'; Ext = ''; Message = ".ini source" }
    }

    # Get source file type
    $selectedType = $null
    while ($true) {
        Show-Info "Select the pipe upstream tool program used by previous script..."
        $sourceTypes.GetEnumerator() | Sort-Object Key | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value.Name)"
        }
        $choice = (Read-Host " Selection (A/B/C/D/E)").ToUpper()

        if ($sourceTypes.ContainsKey($choice)) {
            $selectedType = $sourceTypes[$choice]
            Show-Info $selectedType.Message
            break
        }
    }
    
    # Get upstream tool code（(from JSON); Import DDL for Avs2PipeMod
    $upstreamCode = $null
    $Avs2PipeModDLL = $null
    $OneLineShotArgsINI = $null
    $isScriptUpstream =
        $selectedType.Name -in @('vspipe', 'avs2yuv', 'avs2pipemod')

    switch ($selectedType.Name) {
        'ffmpeg'      { $upstreamCode = 'a' }
        'vspipe'      { $upstreamCode = 'b' }
        'avs2yuv'     { $upstreamCode = 'c'}
        'avs2pipemod' {
            $upstreamCode = 'd'
            Show-Info "Locating the path to AviSynth.dll..."
            Write-Host " Get avisynth.dll: download from AviSynth+ repo (https://github.com/AviSynth/AviSynthPlus/releases)"
            Write-Host " and extract AviSynthPlus_x.x.x_yyyymmdd-filesonly.7z"
            do {
                $Avs2PipeModDLL = Select-File -Title "Select avisynth.dll" -InitialDirectory ([Environment]::GetFolderPath('System')) -DllOnly
                if (-not $Avs2PipeModDLL) {
                    $placeholderScript = Read-Host "No DLL file selected. Press Enter to retry, input 'q' to force exit"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $Avs2PipeModDLL)
            Show-Success "Path to AviSynth.dll: $Avs2PipeModDLL"
        }
        'SVFI'        {
            $upstreamCode = 'e'
            Show-Info "Locating SVFI render config INI path..."
            $foundPath = Get-PSDrive -PSProvider FileSystem | ForEach-Object { 
                $p = "$($_.Root)SteamLibrary\steamapps\common\SVFI\Configs"
                if (Test-Path $p) { $p }
            } | Select-Object -First 1

            Show-Info "Please select the desginated SVFI render configuration INI file"
            Write-Host " For Steam installation, it would be X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"

            do {
                if ($foundPath) { # The the auto-located path
                    Show-Success "Candidate path found: $foundPath"
                    $OneLineShotArgsINI = Select-File -Title "Select render configuration（.ini）" -IniOnly -InitialDirectory $foundPath
                }
                else { # DIY
                    $OneLineShotArgsINI = Select-File -Title "Select render configuration（.ini）" -IniOnly
                }

                if (-not $OneLineShotArgsINI) {
                    $placeholderScript = Read-Host "No INI file selected. Press Enter to retry, input 'q' to force exit"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $OneLineShotArgsINI)
        }
        default       { $upstreamCode = 'a' }
    }
    Write-Host ("─" * 50)
    
    # Define IO Variables
    $videoSource = $null # ffprobe will analyze this one
    $scriptSource = $null # script source, overrides video source in json export
    $encodeImportSourcePath = $null
    $svfiTaskId = $null

    # vspipe / avs2yuv / avs2pipemod: Filter-less script generation option
    if ($isScriptUpstream) {
        do {
            # Select source file (ffprobe analysis)
            Show-Info "Select the video source file (referenced by the script) for ffprobe to analyze"
            while ($null -eq $videoSource) {
                $videoSource = Select-File -Title "Select video source (.mp4/.mkv/.mov)"
                if ($null -eq $videoSource) { Show-Error "No video source selected" }
            }
        
            # Ask user to generate or import existing script
            Show-Info "Import one or generate both AviSynth and VapourSynth filter-less scripts"
            $mode = Read-Host " Input 'y' to generate script, 'n'/Enter to import a custom script"
        
            if ([string]::IsNullOrWhiteSpace($mode) -or 'n' -eq $mode) {
                Show-Warning "Due to the wide variety of import source paths supported by the script, the conditions are too complex to validate, please check whether source video exists manually."
                do {
                    $scriptSource = Select-File -Title "Locate the script file (.avs/.vpy...)"
                    if (-not $scriptSource) {
                        Show-Error "No script file selected"
                        continue
                    }
                
                    # Validate file extension
                    $ext = [IO.Path]::GetExtension($scriptSource).ToLower()
                    if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod') -and $ext -ne '.avs') {
                        Show-Error "Incorrect script file, expecting .avs script for $($selectedType.Name)"
                        $scriptSource = $null
                    }
                    elseif ($selectedType.Name -eq 'vspipe' -and $ext -ne '.vpy') {
                        Show-Error "Incorrect script file, expecting .vpy script for vspipe"
                        $scriptSource = $null
                    }
                }
                while (-not $scriptSource)

                Show-Success "Script source selected: $scriptSource"
            }
            # Generate filter-less script
            elseif ('y' -eq $mode) {
                if (Test-NullablePath 'C:\Program Files (x86)\AviSynth+\plugins64+\LSMASHSource.dll') {
                    Show-Success "LSMASHSource.dll is detected under C:\Program Files (x86)\AviSynth+\plugins64+\, all set"
                }
                else {
                    Show-Warning "Half-baked environment?: LSMASHSource.dll is missing under C:\Program Files (x86)\AviSynth+\plugins64+\ (decoder)"
                    Write-Host " Missing of this file can result in high quantity of AVS scripts to fail"
                    Write-Host " Download and extract 64bit version：https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works/releases`r`n" -ForegroundColor Magenta
                }
                Write-Host ("─" * 50)

                $placeholderScript = Get-BlankAVSVSScript -videoSource $videoSource
                if (-not $placeholderScript) { 
                    Show-Error "Failed to create filter-less script, please try again."
                    continue
                }
            
                # Select the correct script path based on the upstream type
                if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod')) {
                    $scriptSource = $placeholderScript.AVS
                }
                else { # vspipe
                    $scriptSource = $placeholderScript.VPY
                }
                
                Show-Success "Filter-less script created: $scriptSource"
            }
            else {
                Show-Warning "Invalid input"
                continue
            }
            break
        }
        while ($true)

        $encodeImportSourcePath = $scriptSource
    }
    # SVFI: parse source video from INI file
    elseif ($OneLineShotArgsINI -and (Test-Path -LiteralPath $OneLineShotArgsINI)) {
        # SVFI's source path config within ini file (actually its one-liner)：gui_inputs="{
        #     \"inputs\": [{
        #         \"task_id\": \* Requird field to be exported to json\",
        #         \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\Video.mp4\",
        #         \"is_surveillance_folder\": false
        #     }]
        # }"
        # Read and find line starts with gui_inputs, i.e.:
        # gui_inputs="{\"inputs\": [{\"task_id\": \"798_2aa174\", \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\[Airota][Yuru Yuri\\u3001][OVA][BDRip 1080p].mp4\", \"is_surveillance_folder\": false}]}"
        Show-Info "Attempting to get source video path from SVFI render configuration INI file..."

        try { # Read INI & locate gui_inputs line
            $iniContent = Get-Content -LiteralPath $OneLineShotArgsINI -Raw -ErrorAction Stop
            $pattern = 'gui_inputs\s*=\s*"((?:[^"\\]|\\.)*)"'
            $guiInputsMatch = [regex]::Match($iniContent, $pattern)
            if (-not $guiInputsMatch.Success) {
                Show-Error "Missing gui_inputs section in SVFI INI file, please recreate INI with SVFI"
                Read-Host "Press Enter to exit"
                return
            }

            # Extract the JSON string containing the path (remove the outer gui_inputs="...")
            $jsonString = $guiInputsMatch.Groups[1].Value
            $jsonString = $jsonString -replace '\\"', '"'
            $jsonString = $jsonString -replace '\\\\', '\\'
            Show-Debug "Parsed JSON: $jsonString"

            # Translate JSON and extract the video source path to a PowerShell variable
            try {
                $jsonObject = $jsonString | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $jsonObject.inputs -or ($jsonObject.inputs.Count -eq 0)) {
                    Show-Error "Missing video import statement in SVFI INI file, please recreate INI with SVFI"
                    Read-Host "Press Enter to exit"
                    return
                }

                # Fetch path to the first video source
                Show-Success "Source import statement detected successfully"
                Show-Warning "Only the first video source in the INI file will be used"
                $jsonSource = $jsonObject.inputs[0].input_path
                if ([string]::IsNullOrWhiteSpace($jsonSource)) {
                    Show-Error "Blank input statement found in SVFI INI file, please recreate INI with SVFI"
                    Read-Host "Press Enter to exit"
                    return
                }
                $svfiTaskId = $jsonObject.inputs[0].task_id
                if ([string]::IsNullOrWhiteSpace($svfiTaskId)) {
                    Show-Error "task_id statment corrupted in SVFI INI file, please recreate INI with SVFI"
                    Read-Host "Press Enter to exit"
                    return
                }
                Show-Success "SVFI Task ID detected: $svfiTaskId"

                $videoSource = Convert-IniPath -iniPath $jsonSource # FileUtils.ps1 function
                Show-Success "Source video detected from $videoSource"

                # Validate if video file exists
                if (-not (Test-Path -LiteralPath $videoSource)) {
                    Show-Error "Source video fill no longer exists on disk: $videoSource, please recreate INI with SVFI"
                    Read-Host "Press Enter to exit"
                    return
                }
            }
            catch {
                Show-Error "Failed to parse JSON：$_"
                Show-Debug "Original JSON string：$jsonString"
                Read-Host "Press Enter to exit"
                return
            }
        }
        catch {
            Show-Error "Could not read SVFI INI：$_"
            Read-Host "Press Enter to exit"
            return
        }

        $encodeImportSourcePath = $videoSource
    }
    else { # ffmpeg: video source
        do {
            Show-Info "Select the video source file for ffprobe to analyze"
            $videoSource = Select-File -Title "Locate video source (.mp4/.mov/...), RAW (.yuv/.y4m/...)"
            if (-not $videoSource) { 
                Show-Error "No video source selected" 
                continue
            }
            
            Show-Success "Video source selected: $videoSource"
            break
        }
        while ($true)

        $encodeImportSourcePath = $videoSource
    }
    $quotedVideoSource = Get-QuotedPath $videoSource

    $ffprobeArgs = @(
        '-i', $quotedVideoSource,
        '-select_streams', 'v:0',
        '-v', 'error', '-hide_banner',
        '-show_streams',
        '-show_frames', '-read_intervals', "%+#1"
        '-of', 'json'
    )
    Write-Host ("─" * 50)

    Show-Info "Locating ffprobe.exe..."
    $ffprobePath = $null
    $isSavedPathValid = $false
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Info "Detecting config file ($($savedConfig.SaveDate)), loading now..."
            if ($savedConfig.Analysis) {
                $ffprobePath = $savedConfig.Analysis.ffprobe
                Show-Debug ("ffprobe path: " + $ffprobePath)
                if (Test-NullablePath $ffprobePath) { $isSavedPathValid = $true }
                else { Show-Info "Path to ffprobe leads to nowhere, recommended to re-exec step 2 script" }
            }
        }
        catch { Show-Info "Config file is missing or corrupted, manual import required; Recommended to re-exec step 2 script" }
    }

    # Auto path detect with Invoke-AutoSearch
    if (-not $isSavedPathValid) {
        $ffprobePath = Invoke-AutoSearch -ToolName 'ffprobe' -ScriptDir $scriptDir
        if ($ffprobePath) {
            Show-Success "Going directly with found ffprobe.exe: $ffprobePath"
        }
        else {
            do {
                $ffprobePath =
                    Select-File -Title "Open ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
                if (-not (Test-Path -LiteralPath $ffprobePath)) {
                    Show-Warning "Could not locate ffprobe executable, please retry"
                }
            }
            while (-not (Test-Path -LiteralPath $ffprobePath))
        }
    }

    Write-Host ("─" * 50)
    # Observation only, not for final export, does not support $quotedVideoSource as param input
    $streamInfo = Get-VideoStreamInfo -ffprobePath $ffprobePath -videoSource $videoSource -showEntries "stream=r_frame_rate,avg_frame_rate,nb_frames,duration,sample_aspect_ratio"
    # Show-Debug "Frame rate, Avg. frame rate, total frames, duration, sample aspect ratio:"
    # Write-Host $streamInfo

    # Detect non-square pixel source, source container format and warn
    Test-VideoWarnings -ffprobeStreamInfo $streamInfo -quotedVideoSource $quotedVideoSource

    Write-Host ("─" * 50)

    # Detect if video container format is genuine, does not support $quotedVideoSource as param input
    $realFormatName = Test-VContainerFormat -ffprobePath $ffprobePath -videoSource $videoSource

    Write-Host ("─" * 50)

    $isMOV = ($realFormatName -like "MOV")
    $isVOB = ($realFormatName -like "VOB")
    # if ($isMOV) { Show-Debug "The imported video $videoSource is in MOV format" }
    # elseif ($isVOB -like "VOB") { Show-Debug "The imported video $videoSource is in VOB format" }
    # else { Show-Debug "The imported video $videoSource is not in MOV or VOB format" }

    # ffprobe output is different for different formats, leading to misalignment, it was a mistake for using keyless format (-of csv)
    $sourceJsonExportPath = Join-Path $Global:TempFolder "temp_s_info.json"
    $ffprobeJsonExportPath =
        if ($isMOV) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.json"
        }
        elseif ($isVOB) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.json"
        }
        else {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.json"
        }
    # $ffprobeJsonExportPathDebug =
    #     if ($isMOV) {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov_debug.json"
    #     }
    #     else {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_debug.json"
    #     }

    # If the CSV file already exists, manually confirm and delete
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.json")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.json")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.json")
    Confirm-FileDelete $sourceJsonExportPath

    # Execute ffprobe with video source path provided
    try {
        Write-Host $ffprobeArgs -ForegroundColor Green

        $ffprobeOutputJson = (& $ffprobePath @ffprobeArgs) -join "`n"
        
        # Create source info object
        $sourceInfoObject = @{
            SourcePath       = $encodeImportSourcePath
            UpstreamCode     = $upstreamCode
            Avs2PipeModDllPath = $Avs2PipeModDLL
            SvfiInputConf    = $OneLineShotArgsINI
            SvfiTaskId       = $svfiTaskId
        }
        
        # Create ffprobe JSON, source info JSON
        Write-TextFile -Path $ffprobeJsonExportPath -Content $ffprobeOutputJson -UseBOM $true
        Write-JsonFile -Path $sourceJsonExportPath -Object $sourceInfoObject
        Show-Success "JSON file created: `r`n $ffprobeJsonExportPath`r`n $sourceJsonExportPath"
        Write-Host ("─" * 50)
        
        # 验证 JSON 文件格式（使用新的函数）
        Show-Debug "Validating JSON format..."
        if (-not (Test-JsonFileFormat -Path $ffprobeJsonExportPath)) {
            return
        }
        if (-not (Test-JsonFileFormat -Path $sourceJsonExportPath)) {
            return
        }
    }
    catch { throw ("ffprobe execution or JSON export failed: " + $_) }

    Write-Host ''
    Show-Success "Script Completed!"
    Read-Host "Press any button to exit"
}
#endregion

try { Main }
catch {
    Show-Error "Script failed: $_"
    Write-Host "Error details: " -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "Press any button to exit"
}