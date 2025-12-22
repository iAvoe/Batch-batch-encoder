<#
.SYNOPSIS
    Multi-track multiplex command generator
.DESCRIPTION
    Using ffmpeg and ffprobe to multiplex/encapsulate multiple tracks to video container format
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# Load globals
. "$PSScriptRoot\Common\Core.ps1"

# Validate if frame rate value is normal
function Test-FrameRateValid {
    param([string]$fr)
    if (-not $fr) { return $false }

    # Exclude 0/0 or 0
    if ($fr -match '^(0(/0)?|0(\.0+)?)$') { return $false }

    # Fractions such as 24000/1001 are allowed, as are integers like 24 and floats like 23.976
    if ($fr -match '^\d+/\d+$') { return $true }
    if ($fr -match '^\d+(\.\d+)?$') { return $true }
    return $false
}

function Get-FrameRateFromContainer {
    param(
        [Parameter(Mandatory=$true)][string]$FFprobePath,
        [Parameter(Mandatory=$true)][string]$FilePath
    )
    $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
    if ($vData -and $vData.FrameRate) {
        return $vData.FrameRate
    }
    return $null
}


# Calling ffprobe retrieves information about a specified stream and returns an object directly without writing to a temporary file
# Let user to specify video fps as a last resort to eliminate errors and improve experience
function Get-StreamArgs {
    param (
        [string]$FFprobePath,
        [string]$FilePath,
        [int]$MapIndex,
        [bool]$IsFirstVideo
    )
    $ext = [IO.Path]::GetExtension($FilePath).ToLower()
    $argsResult = @()
    $hasVideo = $false
    
    # Try to match video container formats
    $isVideoContainer = $ext -in @('.mkv', '.mp4', '.mov', '.f4v', '.flv', '.avi', '.m3u', '.mxv')
    $isAudioContainer = $ext -in @('.m4a', '.mka', '.mks')
    $isSingleFile = -not ($isVideoContainer -or $isAudioContainer)
    
    Show-Debug "Analyzing: $FilePath (Extension: $ext)"
    
    # Process multiplexed/contained video formats
    if ($isVideoContainer) {
        Show-Info "Video container format, analyzing internal tracks..."
        
        # Video streams
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        if ($vData -and $IsFirstVideo) {
            $codec = if ($vData.CodecTag -and $vData.CodecTag -ne "0") { 
                $vData.CodecTag 
            }
            else { 
                $vData.CodecName 
            }
            
            Show-Success "Video stream: $codec"
            if ($vData.FrameRate) { # Assume video container format always provide fps data
                $argsResult += "-r $($vData.FrameRate) -c:v copy"
            }
            else {
                $argsResult += "-c:v copy"
            }
            $hasVideo = $true
        }
        elseif ($vData) {
            Show-Warning "Skip extra video streams (allow only the 1st video stream)."
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "Audio stream detected"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "Subtitle stream detected"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isAudioContainer) { # Process audio container format
        Show-Info "Detected audio container format..."
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "Audio stream detected"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "Subtitle stream detected"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isSingleFile) { # Single file (video stream, audio stream, subtitle...)
        Show-Info "Singular file detected..."
        
        # Try to detect file type
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        
        if ($vData -and $IsFirstVideo) {
            Show-Success "Detecting singular video stream: $($vData.CodecName)"
            
            # Get fps of this stream
            $currentFrameRate = $vData.FrameRate
            $isCurrentFrameRateValid = Test-FrameRateValid -fr $currentFrameRate
            
            # FPS handling
            if ($isCurrentFrameRateValid) {
                # 1. Video file actually provides frame rate (could be indeo video format / ivf)
                Show-Info "Use the frame rate provided in the file: $currentFrameRate"
                $frameRate = $currentFrameRate
            }
            else {
                # 2. No fps data provided
                Show-Warning "Singular video stream does not provide valid frame rate (fps) data..."
                
                # Provide choices
                Write-Host "`nSelect a method to provide frame rate (fps) data:" -ForegroundColor Cyan
                Write-Host "1: Manual input" -ForegroundColor Yellow
                Write-Host "2: Read from another video source (recommended)" -ForegroundColor Yellow
                Write-Host "3: Pick a common frame rate from list" -ForegroundColor Yellow
                Write-Host "q: Skip this file" -ForegroundColor DarkGray
                
                $choice = Read-Host "`nSpecify (1-3, q)"
                
                switch ($choice.ToLower()) {
                    '1' { # Manual input
                        $manualFrameRate = Read-Host "Specify a framerate (Integer/Decimal/Fraction, i.e., 24, 23.976, 24000/1001)"
                        if (Test-FrameRateValid -fr $manualFrameRate) {
                            $frameRate = $manualFrameRate
                        }
                        else {
                            Show-Error "Invalid framerate, skipping current stream"
                            return $null
                        }
                    }
                    '2' { # Read from another source
                        Show-Info "Selected a multiplexed/container format (.mp4/.mov/.flv/...)"
                        $containerFile = Select-File -Title "Select a video source to read framerate (fps)"
                        
                        if ($containerFile -and (Test-Path -LiteralPath $containerFile)) {
                            $frameRate = Get-FrameRateFromContainer -FFprobePath $FFprobePath -FilePath $containerFile
                            if (-not $frameRate) {
                                Show-Error "Could not find valid video framerate from file, skipping current stream"
                                return $null
                            }
                            Show-Info "Framerate found from file: $frameRate"
                        }
                        else {
                            Show-Error "Invalid file selected, skipping current stream"
                            return $null
                        }
                    }
                    '3' { # Pick a common frame rate
                        Write-Warning "Framerate (fps) must be exactly same as source video stream, expect playback issues otherwise"
                        Write-Host "`nCommon framerate (fps)" -ForegroundColor Cyan
                        Write-Host "1. 23.976 (24000/1001)" -ForegroundColor Yellow
                        Write-Host "2. 24" -ForegroundColor Yellow
                        Write-Host "3. 25" -ForegroundColor Yellow
                        Write-Host "4. 29.97 (30000/1001)" -ForegroundColor Yellow
                        Write-Host "5. 30" -ForegroundColor Yellow
                        Write-Host "6. 48" -ForegroundColor Yellow
                        Write-Host "7. 50" -ForegroundColor Yellow
                        Write-Host "8. 59.94 (60000/1001)" -ForegroundColor Yellow
                        Write-Host "9. 60" -ForegroundColor Yellow
                        Write-Host "a. 120" -ForegroundColor Yellow
                        Write-Host "b. 144" -ForegroundColor Yellow
                        Write-Host ""
                        
                        $presetChoice = Read-Host "Select a framerate/fps (1-9, a-b)"
                        $frameRate = switch ($presetChoice.ToLower()) {
                            '1' { '24000/1001' }
                            '2' { '24' }
                            '3' { '25' }
                            '4' { '30000/1001' }
                            '5' { '30' }
                            '6' { '48' }
                            '7' { '50' }
                            '8' { '60000/1001' }
                            '9' { '60' }
                            'a' { '120' }
                            'b' { '144' }
                            default { 
                                Show-Error "Invalid choice, skipping current stream"
                                return $null
                            }
                        }
                    }
                    'q' {
                        Show-Info "Cancelled, skipping current stream"
                        return $null
                    }
                    default {
                        Show-Error "Invalid choice, skipping current stream"
                        return $null
                    }
                }
            }
            
            # Add ffmpeg framerate parameter
            if ($frameRate) {
                $argsResult += "-r $frameRate -c:v copy"
                $hasVideo = $true
            }
            else {
                Show-Warning "No framerate selected, please expect playback issues"
                $argsResult += "-c:v copy"
                $hasVideo = $true
            }
        }
        elseif (-not $vData) { # Try to match audio stream
            $aData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a"
            if ($aData) {
                Show-Success "Audio stream detected: $($aData.CodecName)"
                $argsResult += "-c:a copy"
            }
        }
        
        if ($ext -in @('.srt', '.ass', '.ssa')) {
            Show-Success "Subtitle stream detected: $ext"
            $argsResult += "-c:s copy"
        }
        elseif ($ext -in @('.ttf', '.ttc', '.otf')) {
            Show-Success "Font file detected: $ext"
            $argsResult += "-c:t copy"
        }
    }
    else {
        Show-Warning "Unidentified source, cannot be processed"
        return $null
    }
    
    if ($argsResult.Count -eq 0) {
        Show-Warning "Input file did not generate valid parameters: $FilePath"
        return $null
    }
    
    return [PSCustomObject]@{
        ArgumentsString = $argsResult -join " "
        ContainsVideo   = $hasVideo
    }
}

function Main {
    Show-Border
    Show-Info "Multi-track multiplex command generator"
    Show-Border
    
    # 1. Initialize paths and tools
    Show-Info "Import tools and select export paths"
    Show-Info "(1/4) Import ffprobe.exe..."
    $fprbPath = Select-File -Title "Select ffprobe.exe" -ExeOnly
    Show-Info "(2/4) Import ffmpeg.exe..."
    $ffmpegPath = Select-File -Title "Select ffmpeg.exe" -ExeOnly -InitialDirectory ([IO.Path]::GetDirectoryName($fprbPath))
    Show-Info "(3/4) Select export path for mux/multiplexing/encapsulating/containing batch..."
    $exptPath = Select-Folder -Description "Select folder to export the multiplexing batch file"
    Show-Info "(4/4) Select export path for mux/mutiplex/encapsulation/cantained file result..."
    $muxPath  = Select-Folder -Description "Select folder to export the multiplexing result"

    # 2. Import streams
    Show-Info "Import source stream (loop)"
    Write-Host " Note: Only the first video stream will be used" -ForegroundColor Yellow
    Write-Host "       all later imports will only add audio, subtitle tracks" -ForegroundColor Yellow
    
    $inputsAgg = ""   # All -i "path"S
    $mapsAgg   = ""   # All -map xArgs
    $mapIndex  = 0
    $hasVideo  = $false

    while ($true) {
        $strmPath = Select-File -Title "Select source stream ($($mapIndex+1)st/nd/th)"
        
        $result = Get-StreamArgs -FFprobePath $fprbPath -FilePath $strmPath -MapIndex $mapIndex -IsFirstVideo (-not $hasVideo)
        
        if ($result) {
            $inputsAgg += " -i `"$strmPath`""
            $mapsAgg   += " -map $mapIndex $($result.ArgumentsString)"
            
            if ($result.ContainsVideo) {
                $hasVideo = $true
                Show-Success "Master/Primary video stream added"
            }
            
            $mapIndex++
        }
        
        Write-Host ""
        $continue = Read-Host "Add more streams? Input 'y' to add, press Enter to complete import"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            break
        }
    }

    # 3. Export batch
    # 3-1. Specify file name for multiplex result
    $defaultName = [IO.Path]::GetFileNameWithoutExtension($strmPath) + "_mux"
    $outName = Read-Host "Please specify the file name for multiplex result`r`n (Input Enter on empty for default: $defaultName)"
    if ([string]::IsNullOrWhiteSpace($outName)) { $outName = $defaultName }
    
    # 3-2. Validate file name
    if (-not (Test-FilenameValid $outName)) {
        Show-Warning "Invalid characters found, replacing..."
        $invalid = [IO.Path]::GetInvalidFileNameChars()
        foreach ($c in $invalid) { $outName = $outName.Replace($c, '_') }
    }

    # 3-3. Select 
    Write-Host "`r`nSelect a video container format:"
    Write-Host " 1：MP4 (General purpose)"
    Write-Host " 2：MOV (Editing software preferred)"
    Write-Host " 3：MKV (Compatible with most subtitles, support fonts)"
    Write-Host " 4：MXF (Professional use case)"
    Write-Warning " ffmpeg is deprecating the MP4 timecode (pts) generation feature, at which point the MP4 format option will stop working"
    
    $containerExt = ""
    do {
        switch (Read-Host "Pick an option (1/2/3/4)") {
            1 { $containerExt = ".mp4" }
            2 { $containerExt = ".mov" }
            3 { $containerExt = ".mkv" }
            4 { $containerExt = ".mxf" }
            default { Write-Warning "Invalid option selected" }
        }
    }
    while ($containerExt -eq "")

    # 3-4. Commandline generation and final checks
    
    # Construct final commandline
    # Structore: ffmpeg.exe inputs maps output
    $finalOutput = Join-Path $muxPath ($outName + $containerExt)
    $cmdLine = "& $(Get-QuotedPath $ffmpegPath) $inputsAgg $mapsAgg $(Get-QuotedPath $finalOutput)"

    # Compatibility checks and fixes
    if (($containerExt -in ".mp4", ".mov", ".mxf") -and $cmdLine -match "-c:t copy") {
        Show-Warning "Font detected (-c:t copy), they are unsupported by MP4/MOV/MXF format"
        Write-Host "`r`nSelect an option to proceed:"
        Write-Host " d: Delete import statement"
        Write-Host " m: Alter container format to MKV"
        Write-Host " Enter: Ignore"

        $fix = Read-Host "Please select on option..."
        if ($fix -eq 'd') {
            $cmdLine = $cmdLine.Replace("-c:t copy", "")
        }
        elseif ($fix -eq 'm') { 
            $containerExt = ".mkv"
            $cmdLine = $cmdLine.Replace(".mp4", ".mkv").Replace(".mov", ".mkv").Replace(".mxf", ".mkv")
            Show-Success "Switched format to MKV"
        }
    }

    if (($containerExt -in ".mp4", ".mov") -and $cmdLine -match "-c:s copy") {
        Show-Warning "Subtitle detected (-c:s copy), MP4/MOV, multiplexing is likely going to fail"
        Write-Host "`r`nSelect an option to proceed:"
        Write-Host " d: Delete import statement"
        Write-Host " m: Alter container format to MKV"
        Write-Host " Enter: Ignore"

        $fix = Read-Host "Please select on option..."
        if ($fix -eq 'd') {
            $cmdLine = $cmdLine.Replace("-c:s copy", "")
        }
        elseif ($fix -eq 't') {
            $cmdLine = $cmdLine.Replace("-c:s copy", "-c:s:0 mov_text")
        }
        
    }
    
    # Generate file name
    $batFilename = "ffmpeg_mux.bat"
    $batPath = Join-Path $exptPath $batFilename

    # Write batch (remove PowerShell's & call, convert to CMD format)
    $cmdContent = $cmdLine.TrimStart('& ') 
    $batContent = @"

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM ffmpeg Multiplexing tool
REM Generated on: {0}
REM ========================================

echo.
echo Starting multiplexing task...
echo.

{1}

echo.
echo ========================================
echo  Batch execution completed！
echo ========================================
echo.

endlocal
echo Press any button to enter CMD, input exit to exit...
pause >nul
cmd /k
"@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $cmdContent

    # Ensure the ffmpeg path is enclosed in quotes
    # (although it might not be in the $ffmpegPath variable, it was added when combining them above).
    
    Show-Border
    Write-TextFile -Path $batPath -Content $batContent -UseBOM $true
    
    Show-Success "Script completed!"
    Show-Info "Batch saved to: $batPath"
    Show-Info "Open the batch file to start multiplexing process"
    Write-Host "Note: If the audio and video are out of sync, add -itoffset <seconds> parameter between -map and -c" -ForegroundColor DarkGray
    
    Pause
}

try { Main }
catch {
    Show-Error "Script failed: $_"
    Write-Host "Error details: " -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "Press any button to exit"
}