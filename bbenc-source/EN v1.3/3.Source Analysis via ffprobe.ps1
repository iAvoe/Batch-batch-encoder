<#
.SYNOPSIS
    FFProbe source analyzer script
.DESCRIPTION
    Analyzes the source video and exports file to %USERPROFILE%\temp_v_info(_is_mov).csv, i.e., width, height, csp info, sei info, etc.
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
#            .AA：NUMBER_OF_FRAMES-eng (only for non-MOV formats)
# $sourceCSV.SourcePath：source video path (could be vpy/avs scripts)
# $sourceCSV.UpstreamCode：upstream tool specifier
# $sourceCSV.Avs2PipeModDLLPath：avisynth.dll needed by Avs2PipeMod
# $sourceCSV.SvfiConfigPath：one_line_shot_args (SVFI)'s render config X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini

# Load globals, including $utf8NoBOM、Get-QuotedPath、Select-File、Select-Folder...
. "$PSScriptRoot\Common\Core.ps1"

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
        Show-Error "Failed to create filter-less script: $_"
        return $null
    }
}

# Use ffprobe to detect the actual video file container format, ignoring the file extension (the container format is represented by uppercase letters)

function Test-VideoContainerFormat {
    param (
        [Parameter(Mandatory = $true)][string]$ffprobePath,
        [Parameter(Mandatory = $true)][string]$videoSource
    )

    if (-not (Test-Path $ffprobePath)) {
        throw "Test-VideoContainerFormat: ffprobe.exe does not exist ($ffprobePath)"
    }
    if (-not (Test-Path $videoSource)) {
        throw "Test-VideoContainerFormat: Input video does not exist ($videoSource)"
    }
    Show-Info ("Test-VideoContainerFormat: Imported video $videoSource")
    $quotedVideoSource = Get-QuotedPath $videoSource

    try {
        # Use JSON input for analysis
        $ffprobeJson = &$ffprobePath -hide_banner -v quiet -show_format -print_format json $quotedVideoSource 2>null

        if ($LASTEXITCODE -eq 0) {
            # ffprobe exits normally, analysis results exist
            $formatInfo = $ffprobeJson | ConvertFrom-Json
            $formatName = $formatInfo.format.format_name
            # VOB format detection
            if ($formatName -match "mpeg") {
                # Further detection
                $ffprobeText = & $ffprobePath -hide_banner $quotedVideoSource 2>&1
                # Filename contains "VTS_" (unsure if all uppercase, so cmatch is not used)
                # $hasVTSFileName = $filename -match "^VTS_"
                # Metadata contains "dvd_nav" (highly likely VOB)
                $hasDVD = $false
                # Metadata contains "mpeg2video" (highly likely VOB)
                $hasMPEG2 = $false

                foreach ($line in $ffprobeText) {
                    if ($line -match "mpeg2video") {
                        $hasMPEG2 = $true
                    }
                    if ($line -match "dvd_nav") {
                        $hasDVD = $true
                    }
                }

                # VOBs typically contain DVD navigation packets or specific stream structures
                if ($hasDVD -or $hasMPEG2) {
                    Show-Info "Test-VideoContainerFormat: VOB format (DVD video) detected"
                    return "VOB"
                }
                elseif ($hasMPEG2) {
                    Show-Warning "Test-VideoContainerFormat: The source uses MPEG2 encoding and will be treated as VOB format (DVD video)"
                    return "VOB"
                }
                elseif ($hasDVD) {
                    Show-Warning "Test-VideoContainerFormat: The source is not MPEG2 encoded but contains DVD navigation identifiers and will be treated as VOB format (DVD video)"
                    return "VOB"
                }
                else {
                    Show-Warning "Test-VideoContainerFormat: The source is not MPEG2 encoded and has no DVD navigation identifier, so it will be treated as a general container format."
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
            return $formatName
        }
        else {
            # ffprobe failed
            throw "Test-VideoContainerFormat: ffprobe execution or JSON parsing failed"
        }
    }
    catch {
        throw ("Test-VideoContainerFormat: Detection failed" + $_)
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
    do {
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
    while ($true)
    
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

                # TODO: Check the video path in the custom script and try different path syntaxes.
            
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