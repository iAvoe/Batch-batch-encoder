<#
.SYNOPSIS
    Video encoding toolchain generator
.DESCRIPTION
    Generate a batch file for video encoding, support multiple tool-chains
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# Downstream pipe (video encoders) must support Y4M pipe, otherwise upstream-overrides should be added
# For simplicity, usage of Y4M/RAW pipe is dictated by upstream tools only
# i.e., one_line_shot_args (SVFI) Support RAW YUV pipe only, and always override downstreams

# Load globals
. "$PSScriptRoot\Common\Core.ps1"

$Script:DownstreamPipeParams = @{
    y4m = @{
        x264   = '--demuxer y4m'
        x265   = '--y4m'
        svtav1 = ''
    }
    raw = @{
        x264   = '--demuxer raw'
        x265   = ''
        svtav1 = ''
    }
}

# Pipe format compatibility map
function Get-PipeType($upstream) {
    switch ($upstream) {
        'ffmpeg'       { 'y4m' }
        'vspipe'       { 'y4m' }
        'avs2pipemod'  { 'y4m' }
        'avs2yuv'      { 'raw' }
        'svfi'         { 'raw' }
        default        { 'raw' }
    }
}

# Get correct Y4M pipe parameter for vspipe automatically
# Instead of reading VapourSynth versions and map API to Y4M parameters, simply try a list of commands and find the working one
function Get-VSPipeY4MArgument {
    param([Parameter(Mandatory=$true)][string]$VSpipePath)

    $tests = @(
        @("-c", "y4m"),
        @("--container", "y4m"),
        @("--y4m")
    )

    foreach ($testArgs in $tests) {
        Write-Host (" Testing: {0} {1}" -f $VSpipePath, ($testArgs -join " "))
        
        # Use Start-Process to execute on a different process,
        # so it doesn't break the character code page used in current console
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $VSpipePath
        $processInfo.Arguments = $testArgs -join " "
        $processInfo.RedirectStandardError = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        $vsResponse = $output + $errorOutput
        
        if ($vsResponse -match "No script file specified") {
            return @{
                Args = $testArgs -join " "
                Note = "vspipe Y4M paramter detection succeeded: $($testArgs -join ' ')"
            }
        }
    }
    
    throw "Could not detect vspipe's Y4M parameter"
}

# Traversal all pipe routes imported to create "backup routes"
function Get-CommandFromPreset([string]$presetName, $tools, $vspipeInfo) {
        $preset = $Global:PipePresets[$presetName]
        if (-not $preset) {
            throw "Unknown PipePreset: $presetName"
        }

        $up   = $preset.Upstream
        $down = $preset.Downstream

        $pType = Get-PipeType $up
        $pArg  = $Script:DownstreamPipeParams[$pType][$down]
        $template = switch ($up) {
            'ffmpeg'      { '"{0}" %ffmpeg_params% -f yuv4mpegpipe -an -strict unofficial - | "{1}" {3} %{2}_params%' }
            'vspipe'      { '"{0}" %vspipe_params% {3} - | "{1}" {4} %{2}_params%' }
            'avs2yuv'     { '"{0}" %avs2yuv_params% - | "{1}" {3} %{2}_params%' }
            'avs2pipemod' { '"{0}" %avs2pipemod_params% -y4mp | "{1}" {3} %{2}_params%' }
            'svfi'        { '"{0}" %svfi_params% --pipe-out - | "{1}" {3} %{2}_params%' }
        }

        # Check pipe format
        if (-not $Script:DownstreamPipeParams.ContainsKey($pType)) {
            throw "Unknown PipeType: $pType"
        }
        if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
            throw "Downstream (Video Encoder) $down does not support $pType pipe"
        }

        if ($up -eq 'vspipe') {
            return $template -f $tools[$up], $tools[$down], $down, $vspipeInfo.Args, $pArg
        }
        else {
            return $template -f $tools[$up], $tools[$down], $down, $pArg
        }
    }

#region Main
function Main {
    Show-Border
    Write-Host "Video encoding toolchain generator" -ForegroundColor Cyan
    Show-Border
    Write-Host ""
    
    Show-Info "Example of common encoding commandlines:"
    Write-Host "ffmpeg -i [source] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    Write-Host "vspipe [source.vpy] --y4m - | x265.exe --y4m - -o"
    Write-Host "avs2pipemod [source.avs] -y4mp | x265.exe --y4m - -o"
    Write-Host ""
    
    Show-Info "Select path to export batch file..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "Select a path to export batch file"
        if (-not $outputPath -or -not (Test-Path $outputPath)) {
            if ((Read-Host "No path selection, please try again. Input 'q' to force exit") -eq 'q') {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_single.bat"

    Show-Success "Output file defined: $batchFullPath"
    
    # Import encoding tools
    $upstreamTools = @{
        'ffmpeg' = $null
        'vspipe' = $null
        'avs2yuv' = $null
        'avs2pipemod' = $null
        'svfi' = $null
    }
    $downstreamTools = @{
        'x264' = $null
        'x265' = $null
        'svtav1' = $null
    }

    Show-Info "Start importing upstream tools..."
    Write-Host " Hint: Select-File supports opening file selection -InitialDirectory parameter“
    Write-Host " customize the import statements in this script to improve dexterity" -ForegroundColor DarkGray
    Write-Host " If it doesn't work as intended, you may also create shortcut paths"
    
    # Store vspipe version, API version
    $vspipeInfo = $null

    # Upstream tools import
    $i=0
    foreach ($tool in @($upstreamTools.Keys)) {
        $i++
        $choice = Read-Host " [Upstream] ($i/$($upstreamTools.Count)) Import $tool? (y=yes，Enter=Skip)"
        if ($choice -eq 'y') {
            $upstreamTools[$tool] =
                if ($tool -eq 'svfi') {
                    Show-Info "SVFI's executable is 'one_line_shot_args.exe', Steam installation path is X:\SteamLibrary\steamapps\common\SVFI\"
                    Select-File -Title "Locate one_line_shot_args.exe" -ExeOnly
                }
                elseif ($tool -eq 'vspipe') {
                    Show-Info "The default VapourSynth installation places vspipe.exe in C:\Program Files\VapourSynth\core\"
                    Select-File -Title  "Locate vspipe.exe"
                }
                else {
                    Select-File -Title "Locate $tool executable" -ExeOnly
                }

            Show-Success "$tool imported: $($upstreamTools[$tool])"
        }

        # Detect API version for vspipe
        if ($tool -eq 'vspipe' -and $upstreamTools[$tool]) {
            Write-Host ""
            Show-Info "Detect VapourSynth pipe command..."
            $vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $upstreamTools[$tool]
            Show-Success $($vspipeInfo.Note)
        }
    }
    
    Show-Info "Start importing downstream tools..."
    $i = 0
    foreach ($tool in @($downstreamTools.Keys)) {
        $i++
        $choice = Read-Host " [Downstream] ($i/$($downstreamTools.Count)) Import $tool? (y=yes，Enter=Skip)"
        if ($choice -eq 'y') {
            $downstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
            Show-Success "$tool imported: $($downstreamTools[$tool])"
        }
    }

    # TODO

    # Merge all tools (using manual merge to avoid object reference/type issues caused by Clone())
    $tools = @{}
    # Copy upstream tools
    foreach ($k in $upstreamTools.Keys) {
        $tools[$k] = $upstreamTools[$k]
    }
    # Copy downstream tools
    foreach ($k in $downstreamTools.Keys) {
        if ($k -eq 'svtav1') {
            Write-Host " It is recommended to compile the SVT-AV1 encoder yourself"
            Write-Host " (large performance gap, harder to obtain compiled executable)"
            Write-Host " The compilation tutorial can be viewed in the full version of the AV1 tutorial (iavoe.github.io)"
            Write-Host " or the emergency version of the SVT-AV1 tutorial"
            Write-Host " You may need webpage translation to view the compiling tutorial"
        }
        $tools[$k] = $downstreamTools[$k]
    }

    Show-Debug "Merged encoding tool list..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }

    # Verify wer have at least 1 stream and 1 downstream tool
    $hasUpstreamTool =
        @('ffmpeg', 'vspipe', 'avs2yuv', 'avs2pipemod', 'svfi') | Where-Object { 
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '') 
        }
    $hasDownstreamTool =
        @('x264', 'x265', 'svtav1') | Where-Object { 
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '') 
        }

    if (($hasUpstreamTool.Count -eq 0) -or ($hasDownstreamTool.Count -eq 0)) {
        Show-Error "At least 1 upstream tool and 1 downstream tool need to be selected (e.g. ffmpeg + x265 or ffmpeg + svtav1)"
        exit 1
    }

    # Show toochains that could work
    Show-Info "Available encoding toolchains:"
    Write-Host ("─" * 60)

    # Construct “ID → PresetName” map
    $presetIdMap = @{}
    $availablePresets =
        $Global:PipePresets.GetEnumerator() |
        Where-Object {
            if ($null -eq $_.Value) { return $false } # Allow Null
            $up = $_.Value.Upstream
            $down = $_.Value.Downstream
            $tools[$up] -and $tools[$down]
        } |
        Sort-Object { $_.Value.ID }
    
    Write-Host ("{0,-6} {1,-22} {2,-12} {3}" -f "ID", "Preset", "Upstream", "Downstream") -ForegroundColor Yellow
    Write-Host ("─" * 60)
    
    foreach ($item in $availablePresets) {
        $id   = $item.Value.ID
        $name = $item.Key
        $up   = $item.Value.Upstream
        $down = $item.Value.Downstream

        $presetIdMap[$id] = $name

        Write-Host ("[{0,-2}]  {1,-22} {2,-12} {3}" -f $id, $name, $up, $down)
    }
    
    Write-Host ("─" * 60)

    if ($presetIdMap.Count -eq 0) {
        Show-Error "No complete toolchain combination available"
        exit 1
    }
    
    # Select a toolchain
    do {
        Write-Host ""
        $inputId = Read-Host "Please enter toolchain number (integer)"

        if ($inputId -match '^\d+$' -and $presetIdMap.ContainsKey([int]$inputId)) {
            $selectedPreset = $presetIdMap[[int]$inputId]
            Show-Success "Toolchain selected: [$inputId] $selectedPreset"
            break
        }
        Show-Error "Invalid number, please enter a number from the list above"
    }
    while ($true)
    
    # Generate batch processing content and append pipeline specifying commands
    # 1. Generate the currently selected main command
    # Show-Debug "S $selectedPreset"; Show-Debug "T $tools"; Show-Debug "V $vspipeInfo"
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vspipeInfo $vspipeInfo

    # 2. Generate alternate commands for other imported lines (REM write)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        # Note: calling the Key property, not $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vspipeInfo $vspipeInfo
        $otherCommands += "REM PRESET[$presetName]: $cmdStr"
    }
    $remCommands = $otherCommands -join "`r`n"

    # Build batch file (needs double line break at the beginning of the file)
    
    # !TODO: Alter Script 4 so it matches English batch title!
    $batchContent = @'

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM Video encoding toochain pipelines
REM Generated on: {0}
REM Toolchain (Alter this when modify): {1}
REM ========================================

echo.
echo Starting encode...
echo.

REM Parameter examples (this section will be reworked by later scripts)
REM set ffmpeg_params=-i input.mkv -an -f yuv4mpegpipe -strict unofficial
REM set x265_params=--y4m - -o output.hevc
REM set svtav1_params=-i - -b output.ivf

REM Specify commandline for this encode
{2}

REM Auxiliary encoding commandlines
{3}

echo.
echo Encoding completed!
echo.
pause

endlocal
echo Press any button to enter CMD, input exit to exit...
pause >nul
cmd /k
'@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $selectedPreset, $command, $remCommands
    
    # Save file
    try {
        Confirm-FileDelete $batchFullPath
        Write-TextFile -Path $batchFullPath -Content $batchContent -UseBOM $true
        Show-Success "Batch file generated: $batchFullPath"
        
        # Validate line breaks (must be CRLF or CMD can't read it)
        Show-Debug "Validating batch file format..."
        if (-not (Test-TextFileFormat -Path $batchFullPath)) {
            return
        }
    
        # Show usages
        Write-Host ""
        Write-Host ("─" * 50)
        Show-Info "Usages:"
        Write-Host " 1. Later scripts will generate ‘Encoding Batch’ based on this ‘Toolchain/Pipeline Batch’ to start encoding properly"
        Write-Host " 2. Regenration of ‘Toolchain/Pipeline Batch’ is not required as long as there are no changes in encoding tool programs"
        Write-Host " 3. It is recommended to double check tool existense before encoding, especially after setting aside for a long time"
        Write-Host " 4. You may simply modify the ‘Toolchain/Pipeline Batch’ to make changes, but regenerating is less likely to introduce errors"
        
        if ($downstream -eq 'x265') {
            Show-Warning "x265 encoder will export .hevc files"
            Write-Host " To multiplex, please refer to later script steps, or use ffmpeg manually"
        }

        if ($downstream -eq 'svtav1') {
            Show-Warning "AV1 encoder will export .ivf files (Indeo format)"
            Write-Host " To multiplex, please refer to later script steps, or use ffmpeg manually"
        }
        Write-Host ("─" * 50)
        
    }
    catch {
        Show-Error "File export failed: $_"
        exit 1
    }
    
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