<#
.SYNOPSIS
    FFProbe source analyzer script
.DESCRIPTION
    Analyzes the source video and exports file to %USERPROFILE%\temp_v_info(_is_mov).csv, i.e., width, height, csp info, sei info, etc.
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# .mov format range: $ffprobeCSV.A-I + ...; others: $ffprobeCSV.A-AA + ...
# When both temp_v_info_is_mov.csv & temp_v_info.csv are detected, use the latest one
# $ffprobeCSV.A: stream (or not stream)
# $ffprobeCSV.B: width
# $ffprobeCSV.C: height  
# $ffprobeCSV.D: pixel format (pix_fmt)
# $ffprobeCSV.E: color_space
# $ffprobeCSV.F: color_transfer
# $ffprobeCSV.G: color_primaries
# $ffprobeCSV.H: avg_frame_rate
# $ffprobeCSV.I: nb_frames (for MOV) or first frame count field (for others)
# $ffprobeCSV.AA: NUMBER_OF_FRAMES-eng (only for non-MOV files)
# $sourceCSV.SourcePath: source video path (could be vpy/avs scripts)
# $sourceCSV.UpstreamCode: upstream tool
# $sourceCSV.Avs2PipeModDLLPath: avisynth.dll needed by Avs2PipeMod
# $sourceCSV.SvfiConfigPath: one_line_shot_args (SVFI)'s render config (X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini)

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

#region Main
function Main {
    Show-Border
    Write-Host (" ffprobe source analyzer, exports " + $Global:TempFolder + "temp_v_info(_is_mov).csv") -ForegroundColor Cyan
    Write-Host " for later script to take reference on"
    Show-Border
    Write-Host ""

    Show-Info "Example of common encoding commandlines:"
    Write-Host "ffmpeg -i [source] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    Write-Host "vspipe [script.vpy] --y4m - | x265.exe --y4m - -o"
    Write-Host "avs2pipemod [script.avs] -y4mp | x265.exe --y4m - -o"
    Write-Host ""

    # Select source type based on upstream tool
    $sourceTypes = @{
        'A' = @{ Name = 'ffmpeg'; Ext = ''; Message = "Any source" }
        'B' = @{ Name = 'vspipe'; Ext = '.vpy'; Message = ".vpy source" }
        'C' = @{ Name = 'avs2yuv'; Ext = '.avs'; Message = ".avs source" }
        'D' = @{ Name = 'avs2pipemod'; Ext = '.avs'; Message = ".avs source" }
        'E' = @{ Name = 'SVFI'; Ext = ''; Message = "Video source" }
    }

    # Get source file type
    $selectedType = $null
    do {
        Show-Info "Select the designated tool as the pipe upstream..."
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
        'ffmpeg'       { $upstreamCode = 'a' }
        'vspipe'       { $upstreamCode = 'b' }
        'avs2yuv'      { $upstreamCode = 'c' }
        'avs2pipemod'  {
            $upstreamCode = 'd'
            Show-Info "Please locate the path to avisynth.dll..."

            do {
                $Avs2PipeModDLL = Select-File -Title "Select avisynth.dll" -InitialDirectory ([Environment]::GetFolderPath('System')) -DllOnly
                if (-not $Avs2PipeModDLL) {
                    $placeholderScript = Read-Host "No DLL file selected. Press Enter to retry, input 'q' to force exit"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $Avs2PipeModDLL)

            Show-Success "Path for avisynth.dll added: $Avs2PipeModDLL"
        }
        'SVFI'         {
            $upstreamCode = 'e'
            Show-Info "Please locate the path to SVFI render configuration INI file"
            Write-Host " For Steam installation, it would be, X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"

            do {
                $OneLineShotArgsINI = Select-File -Title "Select SVFI render configuration (.ini)" -IniOnly
                if (-not $OneLineShotArgsINI) {
                    $placeholderScript = Read-Host "No INI file selected. Press Enter to retry, input 'q' to force exit"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $OneLineShotArgsINI)
        }
        default        { $upstreamCode = 'a' }
    }

    $videoSource = $null # ffprobe will analyze this one
    $scriptSource = $null # script source for encoding, but cannot be read by ffprobe
    $encodeImportSourcePath = $null

    # If upstream is set to vspipe / avs2yuv / avs2pipemod, offer filter-less script generation option
    if ($isScriptUpstream) {
        do {
            # Select the video source file to analysis
            Show-Info "Select the video source file (referenced by the script) for ffprobe to analyze"
            while ($null -eq $videoSource) {
                $videoSource = Select-File -Title "Select video source (.mp4/.mkv/.mov)"
                if ($null -eq $videoSource) { Show-Error "No video source selected" }
            }
        
            # Ask user to generate or import existing script
            $mode = Read-Host "Input 'y' to import a custom script; `r`n Enter to generate a filter-less script for this video source"
        
            if ($mode -eq 'y') { # Custom script
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
            elseif ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'n') { # Generate
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
    else { # ffmpeg、SVFI: video source
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

    # Detect source video container format
    $isMOV = ([IO.Path]::GetExtension($videoSource).ToLower() -eq '.mov')
    if ($isMOV) {
        Show-Debug "`r`nVideo source $videoSource is in MOV format`r`n"
    }
    else {
        Show-Debug "`r`nVideo source $videoSource is not in MOV format`r`n"
    }

    # Select ffprobe command and define the filename according to container format
    $ffprobeArgs =
        if ($isMOV) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries', '-of', 'csv'
        )}
        else {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
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
    
    # Because ffprobe outputs different numbers of columns from different sources,
    # causing random misalignment (by extra source information)
    # A separate CSV (s_info) is needed to store the source information
    $sourceCSVExportPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    $ffprobeCSVExportPath =
        if ($isMOV) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv"
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
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv")
    Confirm-FileDelete $sourceCSVExportPath

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

    # Execute ffprobe with video source path provided
    try {
        $ffprobeOutputCSV = (& $ffprobePath @ffprobeArgs).Trim()
        # $ffprobeOutputCSVDebug = (& $ffprobePath @ffprobeArgsDebug).Trim()

        # Construct source CSV row
        $sourceInfoCSV = @"
"$encodeImportSourcePath",$upstreamCode,"$Avs2PipeModDLL","$OneLineShotArgsINI"
"@
        
        Write-TextFile -Path $ffprobeCSVExportPath -Content $ffprobeOutputCSV -UseBOM $true
        # [System.IO.File]::WriteAllLines($ffprobeCSVExportPathDebug, $ffprobeOutputCSVDebug)

        Write-TextFile -Path $sourceCSVExportPath -Content $sourceInfoCSV -UseBOM $true
        Show-Success "CSV file created: $ffprobeCSVExportPath`n$sourceCSVExportPath"

        # Check line breaks (must be CRLF)
        Show-Debug "Validating file format..."
        if (-not (Test-TextFileFormat -Path $ffprobeCSVExportPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $sourceCSVExportPath)) {
            return
        }
    }
    catch { throw "ffprobe execution failed: $_" }

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