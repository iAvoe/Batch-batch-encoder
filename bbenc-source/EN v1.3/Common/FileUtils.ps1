# Verify if the filename conforms to Windows naming rules.
function Test-FilenameValid {
    param([string]$Filename)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    return $Filename.IndexOfAny($invalid) -eq -1
}

# Add quotes to path
function Get-QuotedPath {
    param([string]$Path)
    return "`"$Path`""
}

# Prompt delete if file exists
function Confirm-FileDelete {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Show-Warning "Detecting existing file: $Path"
    $confirm = Read-Host " Delete file to continue? Type 'y' to confirm, Enter to force exit (this is not moving to recycle bin)."

    if ($confirm -ne 'y') {
        Show-Info "Exiting script"
        exit 1
    }

    Remove-Item $Path -Force
    Write-Host ""
    Show-Success "File deleted: $Path"
}

function Select-File(
        [string]$Title = "Select File",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$ExeOnly,
        [switch]$AvsOnly,
        [switch]$VpyOnly,
        [switch]$DllOnly,
        [switch]$IniOnly,
        [switch]$BatOnly
    ) {
    
    # If it is a file path, its parent directory is used; if the path does not exist, it returns to Desktop.
    if ($InitialDirectory) {
        if (Test-Path $InitialDirectory -PathType Leaf) {
            $InitialDirectory = Split-Path $InitialDirectory -Parent
        }
        if (-not (Test-Path $InitialDirectory -PathType Container)) {
            $InitialDirectory = [Environment]::GetFolderPath('Desktop')
        }
    }
    else {
        $InitialDirectory = [Environment]::GetFolderPath('Desktop')
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Multiselect = $false

    # Filter of extensions
    if ($ExeOnly) { $dialog.Filter = 'exe files (*.exe)|*.exe' }
    elseif ($AvsOnly) { $dialog.Filter = 'avs files (*.avs)|*.avs' }
    elseif ($VpyOnly) { $dialog.Filter = 'vpy files (*.vpy)|*.vpy' }
    elseif ($DllOnly) { $dialog.Filter = 'dll files (*.dll)|*.dll' }
    elseif ($IniOnly) { $dialog.Filter = 'ini files (*.ini)|*.ini' }
    elseif ($BatOnly) { $dialog.Filter = 'bat Files (*.bat)|*.bat' }
    else { $dialog.Filter = 'All files (*.*)|*.*' }

    Write-Host " Selection window may open in the background; Avoid pressing Enter here."
    
    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        $choice = Read-Host "No file selected. Press Enter to retry, input 'q' to force exit"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

function Select-Folder([string]$Description = "Select folder", [string]$InitialPath = [Environment]::GetFolderPath('Desktop')) {
    # (Put on top of script) Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialPath
    $dialog.ShowNewFolderButton = $true

    Write-Host " Selection window may open in the background; Avoid pressing Enter here."
    
    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (-not $path.EndsWith('\')) { $path += '\' }
            return $path
        }
        $choice = Read-Host "No folder selected. Press Enter to retry, input 'q' to force exit"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

# Generate batch files using Windows (CRLF) and UTF-8 BOM text encoding.
function Write-TextFile { # Call only after the global variable are defined in Core.ps1
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [bool]$UseBOM = $true
    )
    
    # CRLF newline characters must be used;
    # Otherwise, CMD will not be able to read it (garbled characters)
    $normalizedContent = $Content -replace "`r?`n", "`r`n"
    
    # Choose text encoding
    $encoding = if ($UseBOM) { $Global:utf8BOM } else { $Global:utf8NoBOM }
    
    # Write to file
    [System.IO.File]::WriteAllText($Path, $normalizedContent, $encoding)
    Show-Debug "Encoding: $($encoding.EncodingName), Line breaks: CRLF"
    Show-Success "File written: $Path"
}

# Validate Batch file format
function Test-TextFileFormat {
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Show-Error "File not found: $Path"
        return $false
    }
    
    try {
        # Read file content
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        
        $hasUnixLF = $content -match "(?<!`r)`n"
        if ($hasUnixLF) {
            Write-Host "Detecting Unix(LF) line breaks"
        }
        $hasMacCR = $content -match "`r(?!`n)"
        if ($hasMacCR) {
            Write-Host "Detecting Mac(CR) line breaks"
        }
        # Count CR and LFs
        $crCount = ($content -split "`r").Count - 1
        $lfCount = ($content -split "`n").Count - 1
        if ($crCount -ne $lfCount) {
            Show-Warning "Inequal line break CR($crCount) and LF($lfCount) counts, expect batch script to fail (garbled text)"
        }
        
        # Return validation result
        $isValid = (-not $hasUnixLF) -and (-not $hasMacCR) -and ($crCount -eq $lfCount)
        
        if ($isValid) {
            Show-Success "File formatted correctly (CRLF: $crCount)" -ForegroundColor Green
        }
        else {
            Show-Warning "File formatted incorrectly" -ForegroundColor Red
        }
        return $isValid
    }
    catch {
        Show-Error "File validation failed: $_" -ForegroundColor Red
        return $false
    }
}

# Get metadata by ffprobe
function Get-StreamMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$FFprobePath,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$StreamType
    )
    
    # Verify if stream file/ffprobe exists
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Show-Error "Missing file: $FilePath"
        return $null
    }
    if (-not (Test-Path -LiteralPath $FFprobePath)) {
        Show-Error "Missing ffprobe executable: $FFprobePath"
        return $null
    }
    
    try { # Build ffprobe parameters
        $streamSelector = switch ($StreamType.ToLower()) {
            "v" { "v" }  # video stream
            "a" { "a" }  # audio stream
            "s" { "s" }  # subtitle
            "t" { "t" }  # font
            default { $StreamType }
        }
        
        $arguments = @(
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-select_streams", $streamSelector,
            "`"$FilePath`""
        )
        
        Show-Debug "Executing ffprobe: $FFprobePath $arguments"
        
        # Run ffprobe and fetch output
        $result = & $FFprobePath @arguments 2>&1
        
        # Detect error
        if ($LASTEXITCODE -ne 0) {
            Show-Warning "ffprobe failed (exit code: $LASTEXITCODE): $result"
            return $null
        }
        
        # Read JSON output
        $jsonOutput = $result | Out-String
        $metadata = $jsonOutput | ConvertFrom-Json
        
        # No match case (i.e., looking for audio (-StreamType "a"), but source doesn't have it)
        if (-not $metadata.streams -or $metadata.streams.Count -eq 0) {
            Show-Debug "No stream found in specified type: $($StreamType) ($($FilePath))"
            return $null
        }
        
        # Return the first videl stream's metadata
        $stream = $metadata.streams[0]
        
        # Build returns
        $streamInfo = [PSCustomObject]@{
            Index      = if ($stream.index) { [int]$stream.index } else { 0 }
            CodecName  = if ($stream.codec_name) { $stream.codec_name } else { $null }
            CodecTag   = if ($stream.codec_tag_string) { $stream.codec_tag_string } else { $null }
            CodecType  = if ($stream.codec_type) { $stream.codec_type } else { $null }
            FrameRate  = if ($stream.r_frame_rate) { 
                # Fractional frame rate to string (i.e., 23.976 → 24000/1001)
                $frameRateStr = $stream.r_frame_rate.ToString()
                # Simplify integer frame rate (24/1 → 24)
                if ($frameRateStr -match '^(\d+)/1$') {
                    $matches[1]
                }
                else { $frameRateStr }
            }
            else { $null }
            Width      = if ($stream.width) { [int]$stream.width } else { $null }
            Height     = if ($stream.height) { [int]$stream.height } else { $null }
            Duration   = if ($stream.duration) { [double]$stream.duration } else { $null }
            BitRate    = if ($stream.bit_rate) { [int]$stream.bit_rate } else { $null }
            SampleRate = if ($stream.sample_rate) { [int]$stream.sample_rate } else { $null }
            Channels   = if ($stream.channels) { [int]$stream.channels } else { $null }
            Language   = if ($stream.tags -and $stream.tags.language) { $stream.tags.language } else { $null }
            RawData    = $stream  # Keep original copy
        }
        
        Show-Debug "Stream data detected: $($streamInfo.CodecType) - $($streamInfo.CodecName)"
        if ($streamInfo.FrameRate) {
            Show-Debug "FPS: $($streamInfo.FrameRate)"
        }
        
        return $streamInfo
        
    }
    catch {
        Show-Error "Failed to parse ffprobe output: $_"
        Show-Debug "Error details: $($_.ScriptStackTrace)"
        return $null
    }
}