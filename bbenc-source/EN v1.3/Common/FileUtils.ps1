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

    Write-Host " Selection window may open on the background; Avoid pressing Enter here"
    
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