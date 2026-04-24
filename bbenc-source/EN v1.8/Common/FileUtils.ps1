# Before calling Test-Path, make sure path is not null
function Test-NullablePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return Test-Path -LiteralPath $Path }
    catch { return $false }
}

# UTF-8 JSON Read write
function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 10
    $utf8 = [System.Text.UTF8Encoding]::new($true) # 带 BOM
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

# Validate json file on write
function Test-JsonFileFormat {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Show-Error "File missing: $Path"
        return $false
    }
    try {
        $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        Show-Debug "JSON format validation passed: $Path"
        return $true
    }
    catch {
        Show-Error "JSON format validation failed：$Path"
        Write-Host $_ -ForegroundColor Red
        return $false
    }
}

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
    do {
        $confirm = Read-Host " Delete file to continue? Type 'y' to confirm, input 'q' to force quit (permanent deletion)."
        if ('y' -eq $confirm) { break }
        elseif ('q' -eq $confirm) {
            Show-Info "Stopping..."
            exit 1
        }
    } while ('y' -ne $confirm)

    Remove-Item $Path -Force
    Write-Host ''
    Show-Success "File deleted: $Path"
}

# Try fuzzy matching for .exe files containing the specified name in the script's directory and the PATH variable
function Find-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Keyword,
        [string[]]$SearchPaths = @(),
        [switch]$IncludePathEnv
    )

    # Collect all search locations
    $allPaths = New-Object System.Collections.ArrayList

    # Additional paths specified by the user + directories in the PATH environment variable (if enabled)
    foreach ($p in $SearchPaths) {
        if (Test-Path -Path $p -PathType Container) {
            [void]$allPaths.Add($p)
        }
    }
    if ($IncludePathEnv) {
        $envPaths = $env:Path -split ';'
        foreach ($p in $envPaths) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            $p = $p.trim()
            if (Test-Path -LiteralPath $p -PathType Container) {
                [void]$allPaths.Add($p)
            }
        }
    }

    # Deduplicate
    if (@($allPaths).Count -gt 1) {
        $allPaths = $allPaths | Select-Object -Unique
    }

    # Search for *.exe in each path and filter for files whose filenames contain the keyword
    foreach ($dir in $allPaths) {
        try {
            $hits = Get-ChildItem -Path $dir -Filter *.exe -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$Keyword*" }

            if ($hits) { # Return the first match
                return $hits[0].FullName
            }
        }
        catch { continue } # Move on from failed match
    }
    Write-Host " Find-Tool: Cannot find $keyword in script path, env. variables, or user-specified additional paths" -ForegroundColor DarkGray
    return $null
}

function Invoke-AutoSearch {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [Parameter(Mandatory = $true)][string]$ScriptDir
    )
    <#
    .SYNOPSIS
        Automatically search for encoding tools, UI not included
    .DESCRIPTION
        Search for .exe files containing a keyword in the script directory, additional paths, and PATH.
        Return the paths found; otherwise, return $null.
        Additional paths (must be manually defined in Common/Core.ps1).
    .PARAMETER ToolName
        Tool name (used for keyword matching and finding additional paths in ToolExtraSearchPaths)
    .PARAMETER ScriptDir
        Where the script is located (use the $scriptDir)
    #>
    # Build a list of search paths: script directory + additional paths
    $searchPaths = @($ScriptDir)
    if ($Global:ToolExtraSearchPaths.ContainsKey($ToolName)) {
        $searchPaths += $Global:ToolExtraSearchPaths[$ToolName]
    }
    return Find-Tool -Keyword $ToolName -SearchPaths $searchPaths -IncludePathEnv
}

# General file selection logic
function Select-File(
        [string]$Title = "Select File",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$ScriptOnly,
        [switch]$ExeOnly,
        [switch]$DllOnly,
        [switch]$IniOnly,
        [switch]$BatOnly
    ) {
    Write-Host " Commandline console may lose focus, click on the console to restore input cursor" -ForegroundColor DarkGray

    # If it is a file path, its parent directory is used; if the path does not exist, it returns to Desktop.
    if ($InitialDirectory) {
        if (Test-Path $InitialDirectory -PathType Leaf) {
            $InitialDirectory = Split-Path $InitialDirectory -Parent
        }
        if (-not (Test-Path $InitialDirectory -PathType Container)) {
            $InitialDirectory = [Environment]::GetFolderPath('Desktop')
        }
    }
    else { $InitialDirectory = [Environment]::GetFolderPath('Desktop') }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Multiselect = $false

    # Filter of extensions
    $dialog.Filter = if ($ScriptOnly) { 'Script files (*.avs, *.vpy)|*.avs;*.vpy' }
        elseif ($ExeOnly) { 'exe files (*.exe)|*.exe' }
        elseif ($DllOnly) { 'dll files (*.dll)|*.dll' }
        elseif ($IniOnly) { 'ini files (*.ini)|*.ini' }
        elseif ($BatOnly) { 'bat Files (*.bat)|*.bat' }
        else { 'All files (*.*)|*.*' }

    # Create a hidden TopMost window as form owner
    $form = New-Object System.Windows.Forms.Form
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.WindowState = 'Minimized'

    while ($true) {
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        
        # Refocus of CLI (ineffective on VSCode)
        $hwnd = [WinAPI]::GetConsoleWindow()
        [WinAPI]::SetForegroundWindow($hwnd) | Out-Null

        if ('q' -eq (Read-Host "No file selected. Press Enter to retry, input 'q' to force exit")) { exit 1 }
    }
}

function Select-Folder(
        [string]$Description = "Select folder",
        [string]$InitialPath = [Environment]::GetFolderPath('Desktop')
    ) {
    Write-Host " Commandline console may lose focus, click on the console to restore input cursor" -ForegroundColor DarkGray
    # UI.ps1: Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialPath
    $dialog.ShowNewFolderButton = $true

    # Create a hidden TopMost window as form owner
    $form = New-Object System.Windows.Forms.Form
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.WindowState = 'Minimized'

    while ($true) {
        $result = $dialog.ShowDialog($form)

        # Refocus of CLI (ineffective on VSCode)
        $hwnd = [WinAPI]::GetConsoleWindow()
        [WinAPI]::SetForegroundWindow($hwnd) | Out-Null

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (-not $path.EndsWith('\')) { $path += '\' }
            return $path
        }

        $choice = Read-Host "No folder selected. Press Enter to retry, input 'q' to force exit"
        if ($choice -eq 'q') { exit 1 }
    }
}

# Generate batch files using Windows (CRLF) and UTF-8 BOM text encoding.
function Write-TextFile { # Call only after the global variable are defined in Core.ps1
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [bool]$UseBOM = $true
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Show-Error "Write-TextFile - Failed: Empty path"
        return
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        Show-Error "Write-TextFile - Failed: No content"
        return
    }

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
        Show-Error $_
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
            "v" { "v" }  # video
            "a" { "a" }  # audio
            "s" { "s" }  # subtitle
            "t" { "t" }  # font
            default { $StreamType }
        }
        
        $arguments = @(
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-select_streams", $streamSelector,
            (Get-QuotedPath $FilePath)
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
        Show-Error $_
        Show-Debug "Error details: $($_.ScriptStackTrace)"
        return $null
    }
}

# Extract path from SVFI INI file（CRLF linebreak, UTF-8 No BOM）
function Convert-IniPath {
    param([string]$iniPath)
    
    # Unicode conversion
    $path = [regex]::Unescape($iniPath)
    
    # Remove outside double quotes
    $path = $path.Trim('"')
    
    # double inverted slash to single
    $path = $path -replace '\\\\', '\'
    return $path
}