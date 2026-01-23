<#
.SYNOPSIS
    FFProbe source analyzer script
.DESCRIPTION
    Analyzes the source video and exports file to %USERPROFILE%\temp_v_info(_is_mov).csv, i.e., width, height, csp info, sei info, etc.
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.5
#>

# If both temp_v_info_is_mov.csv and temp_v_info.csv are detected, use the file created latest
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
#            .AA：NUMBER_OF_FRAMES-eng (only for non-MOV formats)
# $sourceCSV.SourcePath：source video path (could be vpy/avs scripts)
# $sourceCSV.UpstreamCode：upstream tool specifier
# $sourceCSV.Avs2PipeModDLLPath：avisynth.dll needed by Avs2PipeMod
# $sourceCSV.SvfiConfigPath：one_line_shot_args (SVFI)'s render config X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini

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

# Modularized ffprobe information retrieval function
function Get-VideoStreamInfo {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource,
        [string]$showEntries = "stream"
    )
    if (-not (Test-Path -LiteralPath $ffprobePath)) {
        throw "Get-VideoStreamInfo：ffprobe.exe missing ($ffprobePath)"
    }
    if (-not (Test-Path -LiteralPath $videoSource)) {
        throw "Get-VideoStreamInfo：File not found ($videoSource)"
    }
    
    # ffprobe parameters
    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-select_streams', 'v:0',
        '-show_entries', $showEntries,
        '-of', 'json',
        $videoSource
    )
    
    # Run ffprobe
    $ffprobeJson = &$ffprobePath @ffprobeArgs 2>$null
    
    if ($LASTEXITCODE -ne 0 -or -not $ffprobeJson) {
        throw "ffprobe failed or did not return any valid data"
    }
    
    $streamInfo = $ffprobeJson | ConvertFrom-Json
    
    if (-not $streamInfo.streams -or $streamInfo.streams.Count -lt 1) {
        throw "Could not find video stream data"
    }
    
    return $streamInfo.streams[0]
}

function Get-VFRWarning {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource,
        [double]$RelativeTolerance = 0.000000001
    )
    
    Show-Info "Detecting if video is in variable frame rate..."
    
    try {
        $s = Get-VideoStreamInfo -ffprobePath $ffprobePath -videoSource $videoSource `
            -showEntries "stream=r_frame_rate,avg_frame_rate,nb_frames,duration"
        
        # Call Set-FpsParams to update the base frame rate and average frame rate
        Set-FpsParams -rFpsString ([string]$s.r_frame_rate).Trim() -aFpsString ([string]$s.avg_frame_rate).Trim()
        $rFps = $script:fpsParams.rDouble
        $aFps = $script:fpsParams.aDouble

        # Extract total frames and total duration
        $nbFrames = 0
        $duration = 0
        try {
            $nbFrames = [int]$s.nb_frames.Trim()
            $duration = [double]$s.duration.Trim()
        }
        catch {
            Show-Warning "Get-VFRWarning：Invalid number of video frames and/or duration data."
        }

        # Estimated fps
        $eFps = $null
        if ($nbFrames -and $duration -and $duration -gt 0) {
            $eFps = $nbFrames / $duration
        }

        # Reasons and possibility score for determining if a video is VFR
        $vReasons = @()
        $score = 0

        # 1. Compare base fps to average fps
        if ($rFps -gt 0 -and $aFps -gt 0) {
            $relDiff =
                [math]::Abs($rFps-$aFps) / [math]::Max(1e-9, [math]::Max($rFps, $aFps))
            if ($relDiff -gt $RelativeTolerance) {
                $score += 1
                $vReasons +=
                    "Base fps ($rFps) differs from avg. fps ($aFps)"
            }
            else {
                $cReasons += "Base fps is equal to avg. fps"
            }
        }
        else {
            $cReasons += "Could not process base fps (r_frame_rate) or avg. fps (avg_frame_rate), could be N/A"
        }

        # 2. Compare estimated frame rate with average frame rate
        if ($eFps -and $aFps -gt 0) {
            $relDiff2 = [math]::Abs($eFps-$aFps) / [math]::Max($eFps, $aFps)
            if ($relDiff2 -gt $RelativeTolerance) {
                $score += 2
                $vReasons +=
                    "Estimated fps ($eFps) differs from avg. fps ($aFps)"
            }
            else {
                $cReasons += "Estimated fps is equal to avg. fps"
            }
        }

        # 3. Special values
        if ($s.r_frame_rate -eq "90000/1") {
            $score += 3
            $vReasons += "Characteristical r_frame_rate (90000), could be VFR container"
        }

        # 4. Large avg. fps denom
        $aDnm = $script:fpsParams.aDenumerator
        if ($aDnm -gt 50000) {
            if (Test-IsLikePrime -number $aDnm) {
                $score += 2
                $vReasons += "Relatively big, prime-like avg. fps denumerator ($aDnm)"
            }
            else {
                $score++
                $vReasons += "Relatively big avg. fps denumerator ($aDnm)"
            }
        }
        else {
            $cReasons += "Relatively normal avg. fps denumerator ($aDnm)"
        }

        # Final decision mapping
        $mode = "[is] constant Frame Rate (CFR)"
        # $confidence = "High"
        if ($score -ge 5) {
            $mode = "[is] variable Frame Rate (VFR)"
            # $confidence = "Confirmed"
        }
        if ($score -ge 4) {
            $mode = "[very likely to be] variable Frame Rate (VFR)"
            # $confidence = "High"
        }
        elseif ($score -ge 2) {
            $mode = "[could be] variable Frame Rate (VFR)"
            # $confidence = "Med"
        }
        elseif ($score -gt 0) {
            $mode = "[has signs of being] variable frame rate (VFR)"
            # $confidence = "Low"
        }
        # else {
        #     $mode = "[is] constant Frame Rate (CFR)"
        #     $confidence = "High"
        # }
        # return [PSCustomObject]@{
        #     Mode           = $mode
        #     Confidence     = $confidence
        #     Score          = $score
        #     r_frame_rate   = $s.r_frame_rate
        #     r_fps          = if ($rFps) {$rFps} else {"N/A"}
        #     avg_frame_rate = $s.avg_frame_rate
        #     avg_fps        = if ($aFps) {$aFps} else {"N/A"}
        #     computed_fps   = if ($eFps) {$eFps} else {"N/A"}
        #     vfr_reasons    = $vReasons
        #     cfr_reasons    = $cReasons
        # }
        if ($score -gt 0) {
            Show-Warning "Source $mode. This program does not support VFR alignment"
            Write-Host " (Force encoding may result in incorrect video length, " -ForegroundColor Yellow 
            Write-Host " and accumulative audio desynchronization during playback)" -ForegroundColor Yellow 
            $vReasons | ForEach-Object { Write-Host ("   - " + $_) -ForegroundColor Yellow }
            Write-Host " Recommending to re-render to constant frame rate (CFR) before proceed," -ForegroundColor Yellow
            Write-Host " or add ffmpeg/VS/AVS filters to correct" -ForegroundColor Yellow
            $quotedVideoSource = Get-QuotedPath $videoSource
            $rNum = $script:fpsParams.rNumerator
            $rDnm = $script:fpsParams.rDenumerator
            Write-Host " i.e.: Render and encode to FFV1 lossless video:"
            Write-Host "   - ffmpeg -i $quotedVideoSource -r $rNum/$rDnm -c:v ffv1 -level 3 -context 1 -g 180 -c:a copy output.mkv" -ForegroundColor Magenta
            Write-Host " i.e.: Measure video frame to detect VFR:"
            Write-Host "   - ffmpeg -i $quotedVideoSource -vf vfrdet -an -f null -" -ForegroundColor Magenta
            Write-Host "   - When finished, identify with [Parsed_vfrdet_0 @ 0000012a34b5cd00] VFR:0.x (y/z). " -ForegroundColor Magenta
            Write-Host "   - y：Frames with unmatching display durations" -ForegroundColor Magenta
            Read-Host " Press any button to continue..."
        }
        else {
            Show-Success "源$mode"
        }
    }
    catch {
        throw ("Get-VFRWarning：" + $_)
    }
}

# Use ffprobe to detect the actual video file container format,
# ignoring the file extension (the container format is represented by uppercase letters).
function Get-NonSquarePixelWarning {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource
    )
    
    try {
        $s = Get-VideoStreamInfo -ffprobePath $ffprobePath -videoSource $videoSource `
            -showEntries "stream=sample_aspect_ratio"
        $sampleAspectRatio = $s.sample_aspect_ratio.Trim()

        if ($sampleAspectRatio -notlike "1:1") {
            Show-Warning "$videoSource has a $sampleAspectRatio sample aspect ratio (non-square pixel)"
            Write-Host " This program does not support SAR handling" -ForegroundColor Yellow
            Write-Host " (encodes to square pixel, width shrinks)" -ForegroundColor Yellow
            Write-Host " you may correct this manually, or specify ffmpeg/VS/AVS filters" -ForegroundColor Yellow
            Write-Host " Manually attach correcting metadata examples:" -ForegroundColor Magenta
            $e = @(
                " 1. ffmpeg -i $quotedVideoSource -c copy -aspect $sampleAspectRatio output.mkv",
                " 2. MP4Box -par 1=$sampleAspectRatio $quotedVideoSource -out output.mp4",
                " 3. moviepy:",
                "    from moviepy.editor import VideoFileClip",
                "    clip = VideoFileClip($quotedVideoSource)",
                "    clip.aspect_ratio = $sampleAspectRatio",
                "    clip.write_videofile('output.mp4')"
            )
            $e | ForEach-Object { Write-Host $_ }
            Read-Host " Press any button to continue..."
        }
    }
    catch {
        throw ("Get-NonSquarePixelWarning：" + $_)
    }
}

# Use ffprobe to detect the actual video file container format, ignoring the file extension (the container format is represented by uppercase letters)
function Test-VideoContainerFormat {
    param (
        [Parameter(Mandatory = $true)][string]$ffprobePath,
        [Parameter(Mandatory = $true)][string]$videoSource
    )
    # Temporarily change text encoding
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    if (-not (Test-Path -LiteralPath $ffprobePath)) {
        throw "Test-VideoContainerFormat: ffprobe.exe does not exist ($ffprobePath)"
    }
    if (-not (Test-Path -LiteralPath $videoSource)) {
        throw "Test-VideoContainerFormat: Input video does not exist ($videoSource)"
    }

    # Get the file extension for subsequent logics
   $ext = [System.IO.Path]::GetExtension($videoSource)
    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-show_format',
        '-of', 'json',
        $videoSource
    )
    $ffprobeArgs2 = @(
        '-v', 'quiet', '-hide_banner',
        $videoSource
    )

    try {
        # Use JSON input for analysis
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
                    Show-Info "Test-VideoContainerFormat: VOB format (DVD video) detected"
                    return "VOB"
                }
                elseif ($hasMPEG2) {
                    Show-Warning "Test-VideoContainerFormat: MPEG2 source, assuming VOB format (DVD video)"
                    return "VOB"
                }
                elseif ($hasDVD) {
                    Show-Warning "Test-VideoContainerFormat: Non-MPEG2 source, but contains DVD navigation identifiers, assuming VOB format (DVD video)"
                    return "VOB"
                }
                else {
                    Show-Warning "Test-VideoContainerFormat: Non-MPEG2 source, no DVD navigation identifier, assuming general container format"
                    return "std"
                }
            }
            elseif ($formatName -match "mov|mp4|m4a|3gp|3g2|mj2") {
                if ($formatName -match "qt" -or $ext -eq ".mov") {
                    Show-Info "Test-VideoContainerFormat: MOV format detected"
                    return "MOV"
                }
                else {
                    Show-Info "Test-VideoContainerFormat: MP4 format detected"
                    return "MP4"
                }
            }
            elseif ($formatName -match "matroska") {
                Show-Info "Test-VideoContainerFormat: MKV format detected"
                return "MKV"
            }
            elseif ($formatName -match "webm") {
                Show-Info "Test-VideoContainerFormat: WebM format detected"
                return "WebM"
            }
            elseif ($formatName -match "avi") {
                Show-Info "Test-VideoContainerFormat: AVI format detected"
                return "AVI"
            }
            elseif ($formatName -match "ivf") {
                Show-Info "Test-VideoContainerFormat: ivf format detected"
                return "ivf"
            }
            elseif ($formatName -match "hevc") {
                Show-Info "Test-VideoContainerFormat: hevc format detected"
                return "hevc"
            }
            elseif ($formatName -match "h264" -or $formatName -match "avc") {
                Show-Info "Test-VideoContainerFormat: avc format detected"
                return "avc"
            }
            elseif ($formatName -match "ffv1") {
                Show-Info "Test-VideoContainerFormat：检测到 ffv1 格式"
                return "ffv1"
            }
            return $formatName
        }
        else { # ffprobe failed
            throw "Test-VideoContainerFormat: ffprobe execution or JSON parsing failed"
        }
    }
    catch {
        throw ("Test-VideoContainerFormat: Detection failed" + $_)
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
    Show-Border
    Show-info (" ffprobe source analyzer, exports " + $Global:TempFolder + "temp_v_info(_is_mov).csv`r`n for later script to take reference on")
    Show-Border
    Write-Host ""

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
    
    # Get upstream tool code（(from CSV); Import DDL for Avs2PipeMod
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
            Write-Host " To get avisynth.dll: downloaded from AviSynth+ repository"
            Write-Host " (https://github.com/AviSynth/AviSynthPlus/releases)"
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

    # Variables for IO
    $videoSource = $null # ffprobe will analyze this one
    $scriptSource = $null # script source for encoding, but cannot be read by ffprobe
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
            Show-Info "Select the preferred AVS/VS script usage..."
            $mode = Read-Host " Input 'y' to import a custom script; 'n'/Enter to generate a filter-less script"
        
            if ($mode -eq 'y') { # Custom script
                Show-Warning "AVS/VS script supports a wide variety of source path formats,`r`n such as define-variable first or directly-specify in import,`r`n different parsers, literal path symbol usages, different string quotes,`r`n and multiple video sources, resulting a complicated combination.`r`n `r`n Therefore, please manually check if the video source pathes are correct `r`n"
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
                # Note: $videoSource is still going to be for ffprobe
            }
            # Generate filter-less script
            elseif ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'n') {
                Show-Warning "AviSynth(+) does not come with LSMASHSource.dll (video import library),"
                Write-Host " Ensure this libaray is present in C:\Program Files (x86)\AviSynth+\plugins64+\ folder" -ForegroundColor Yellow
                Write-Host " Download and extract 64bit version:`r`n    https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works/releases" -ForegroundColor Yellow
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
        #         \"task_id\": \"...\",
        #         \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\Video.mp4\",
        #         \"is_surveillance_folder\": false
        #     }]
        # }"
        # Read and find line starts with gui_inputs, i.e.:
        # gui_inputs="{\"inputs\": [{\"task_id\": \"798_2aa174\", \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\[Airota][Yuru Yuri\\u3001][OVA][BDRip 1080p AVC AAC][CHS].mp4\", \"is_surveillance_folder\": false}]}"
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

    # Locate ffprobe
    Show-Info "Select ffprobe.exe..."
    do {
        $ffprobePath =
            Select-File -Title "Open ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
        if (-not (Test-Path -LiteralPath $ffprobePath)) {
            Show-Warning "Could not locate ffprobe executable, please retry"
        }
    }
    while (-not (Test-Path -LiteralPath $ffprobePath))

    # Detect variable frame rate source
    Get-VFRWarning -ffprobePath $ffprobePath -videoSource $videoSource

    # Detect non-square pixel source
    Get-NonSquarePixelWarning -ffprobePath $ffprobePath -videoSource $videoSource

    # Detect source container format
    $realFormatName = Test-VideoContainerFormat -ffprobePath $ffprobePath -videoSource $videoSource

    $isMOV = ($realFormatName -like "MOV")
    $isVOB = ($realFormatName -like "VOB")
    # if ($isMOV) { Show-Debug "The imported video $videoSource is in MOV format" }
    # elseif ($isVOB -like "VOB") { Show-Debug "The imported video $videoSource is in VOB format" }
    # else { Show-Debug "The imported video $videoSource is not in MOV or VOB format" }

    # Select ffprobe command and define the filename according to container format
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
    
    # Since ffprobe outputs different numbers of columns from different sources,
    # causing random misalignment (by extra source information)
    # A separate CSV (s_info) is needed to store the source information
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

    # If the CSV file already exists, manually confirm and delete
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv")
    Confirm-FileDelete $sourceCSVExportPath

    # Execute ffprobe with video source path provided
    try {
        $ffprobeOutputCSV = (& $ffprobePath @ffprobeArgs).Trim()
        # $ffprobeOutputCSVDebug = (& $ffprobePath @ffprobeArgsDebug).Trim()

        # Construct source CSV row
        $sourceInfoCSV = @"
"$encodeImportSourcePath",$upstreamCode,"$Avs2PipeModDLL","$OneLineShotArgsINI","$svfiTaskId"
"@
        
        Write-TextFile -Path $ffprobeCSVExportPath -Content $ffprobeOutputCSV -UseBOM $true
        # [System.IO.File]::WriteAllLines($ffprobeCSVExportPathDebug, $ffprobeOutputCSVDebug)

        Write-TextFile -Path $sourceCSVExportPath -Content $sourceInfoCSV -UseBOM $true
        Show-Success "CSV file created:`r`n $ffprobeCSVExportPath`r`n $sourceCSVExportPath"

        # Check line breaks (must be CRLF)
        Show-Debug "Validating file format..."
        if (-not (Test-TextFileFormat -Path $ffprobeCSVExportPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $sourceCSVExportPath)) {
            return
        }
    }
    catch { throw ("ffprobe execution failed: " + $_) }

    Write-Host ""
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