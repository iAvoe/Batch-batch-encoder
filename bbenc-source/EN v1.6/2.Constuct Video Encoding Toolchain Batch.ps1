<#
.SYNOPSIS
    Video encoding toolchain generator
.DESCRIPTION
    Generate a batch file for video encoding, support multiple tool-chains
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.7
#>

# Downstream tools (encoders) must support Y4M pipelines; otherwise, error exit for pipeline mismatch needs should be triggered (not yet implemented since all tools supports it)
# The choice between Y4M/RAW should be determined by the upstream; one_line_shot_args (SVFI) has recently implemented Y4M pipeline support,
# If there is an upstream tool that only supports RAW YUV pipelines, then the pipeline input of the downstream tool should be overridden,
# and the pure parameter assignments for resolution, frame rate, etc., should be specified using the video metadata/SEI obtained by ffprobe (implemented)
# Chart of encoding toolchains:
<#
────────────────────────────────────────────────────────────
ID     Preset                 Upstream     Downstream
────────────────────────────────────────────────────────────
[1 ]  ffmpeg_x264            ffmpeg       x264
[2 ]  ffmpeg_x265            ffmpeg       x265
[3 ]  ffmpeg_svtav1          ffmpeg       svtav1
[4 ]  vspipe_x264            vspipe       x264
[5 ]  vspipe_x265            vspipe       x265
[6 ]  vspipe_svtav1          vspipe       svtav1
[7 ]  avs2yuv_x264           avs2yuv      x264
[8 ]  avs2yuv_x265           avs2yuv      x265
[9 ]  avs2yuv_svtav1         avs2yuv      svtav1
[10]  avs2pipemod_x264       avs2pipemod  x264
[11]  avs2pipemod_x265       avs2pipemod  x265
[12]  avs2pipemod_svtav1     avs2pipemod  svtav1
[13]  svfi_x264              svfi         x264
[14]  svfi_x265              svfi         x265
[15]  svfi_svtav1            svfi         svtav1
────────────────────────────────────────────────────────────
#>

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

# Script file path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Tools to import
$upstreamTools = [ordered]@{
    'ffmpeg' = $null
    'vspipe' = $null
    'avs2yuv' = $null
    'avs2pipemod' = $null
    'svfi' = $null
}
$downstreamTools = [ordered]@{
    'x264' = $null
    'x265' = $null
    'svtav1' = $null
}
$analysisTools = [ordered]@{
    'ffprobe' = $null
}

# Pipe format compatibility map
function Get-PipeType($upstream) {
    switch ($upstream) {
        'ffmpeg'       { 'y4m' }
        'vspipe'       { 'y4m' }
        'avs2pipemod'  { 'y4m' }
        'avs2yuv'      { 'y4m' } # Not RAW !
        'svfi'         { 'y4m' } # Not RAW !
        default        { 'raw' }
    }
}

# Instead of reading VapourSynth versions and map API to Y4M parameters,
# simply try a list of commands and find the working one
function Get-VSPipeY4MArgument {
    param([Parameter(Mandatory=$true)][string]$VSpipePath)
    $tests = @(
        @("-c", "y4m"),
        @("--container", "y4m"),
        @("--y4m")
    )

    foreach ($testArgs in $tests) {
        Write-Host (" Testing: {0} {1}" -f $VSpipePath, ($testArgs -join " "))
        
        # Start-Process: execute on other process, so text encoding in current console stays
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
        Write-Debug $vsResponse
        
        if ($vsResponse -match "No script file specified") {
            return @{
                Args = $testArgs -join " "
                Note = "vspipe Y4M paramter detection succeeded: $($testArgs -join ' ')"
            }
        }
    }
    throw "Could not detect vspipe's Y4M parameter. Either VapourSynth or Python environment corrupted"
}

# Traversal all pipe routes imported to create "backup routes"
function Get-CommandFromPreset([string]$presetName, $tools, $vsAPI, [bool]$DebugMode = $false) {
    if ($DebugMode) {
        $debugInfo = [PSCustomObject]@{
            PresetName = $presetName
            Tools      = $tools
            vsAPI      = $vsAPI
        }
        Show-Debug "`r`nGet-CommandFromPreset" -ForegroundColor Yellow
        $debugInfo | ConvertTo-Json | Write-Host -ForegroundColor Gray
    }

    if (-not $presetName) {
        throw "Get-CommandFromPreset：No encoding toolchain selected"
    }
    $preset = $Global:PipePresets[$presetName]
    if (-not $preset) {
        throw "Get-CommandFromPreset——No such toolchain option：$presetName"
    }

    $up    = $preset.Upstream
    $down  = $preset.Downstream
    $pType = Get-PipeType $up
    $pArg  = $Script:DownstreamPipeParams[$pType][$down]
    $template = switch ($up) {
        'ffmpeg'      { '"{0}" %ffmpeg_params% -f yuv4mpegpipe -an -strict unofficial - | "{1}" {3} %{2}_params%' }
        'vspipe'      { '"{0}" %vspipe_params% {3} - | "{1}" {4} %{2}_params%' }
        'avs2yuv'     { '"{0}" %avs2yuv_params% - | "{1}" {3} %{2}_params%' }
        'avs2pipemod' { '"{0}" %avs2pipemod_params% -y4mp | "{1}" {3} %{2}_params%' } # No “-” in upstream
        'svfi'        { '"{0}" %svfi_params% --pipe-out | "{1}" {3} %{2}_params%' } # No “-” in upstream
    }

    # Check pipe format
    if (-not $Script:DownstreamPipeParams.ContainsKey($pType)) {
        throw "Get-CommandFromPreset——Unknown PipeType: $pType"
    }
    if (-not $Script:DownstreamPipeParams[$pType].ContainsKey($down)) {
        throw "Get-CommandFromPreset——Downstream (Video Encoder) $down does not support $pType pipe"
    }
    if ($up -eq 'vspipe') {
        if (-not $vsAPI -or -not $vsAPI.Args) {
            throw "Get-CommandFromPreset——vspipe parameter detect failed, environment might be corrupted, please fix it first"
        }
        return $template -f $tools[$up], $tools[$down], $down, $vsAPI.Args, $pArg
    }
    else {
        return $template -f $tools[$up], $tools[$down], $down, $pArg
    }
}

#region Main
function Main {
    $toolsJson = Join-Path $Global:TempFolder "tools.json"    

    # Version of vspipe API and AVS
    $vspipeInfo = $null
    $isAvsPlus = $true # Old software that may never get updates, therefore we can save its status

    Show-Border
    Write-Host "Video encoding toolchain generator" -ForegroundColor Cyan
    Show-Border
    Write-Host ''
    Show-Info "Usage:"
    Write-Host "1. Subsequent scripts will generate 'encoding batch' based on this 'pipeline/toolchain batch' (encode_template.bat)."
    Write-Host "   Therefore, once this step fnishes, step 2 can be entirely skipped until new tools needs to be added"
    Write-Host "2. This tool will attempt to search for encoding tools in the script's local directory, common install pathes and environment variables"
    Write-Host "   You may copy/move encoding tools to this script's current directory, or configure Common\Core.ps1 to streamline importing process"
    Write-Host ("─" * 50)
    
    Show-Info "Select path to export batch file..."
    $outputPath = $null
    do {
        $outputPath = Select-Folder -Description "Select a path to export batch file"
        if (-not (Test-NullablePath $outputPath)) {
            if ('q' -eq (Read-Host "No path selection, please try again. Input 'q' to force exit")) {
                return
            }
        }
    }
    while (-not $outputPath)
    
    $batchFullPath = Join-Path -Path $outputPath -ChildPath "encode_template.bat"

    Show-Success "Output file: $batchFullPath"

    Write-Host ("─" * 60)
    Show-Info "Importing upstream executable tools..."

    # Attempt to read saved tools.json, but it can be outdated, therefore manual confirmation is required
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Get-Content $toolsJson -Raw -Encoding UTF8 | ConvertFrom-Json
            Show-Info "Detecting path configuration file (saved at: $($savedConfig.SaveDate)), loading now..."

            # Upstream，Downstream，Analysis
            if ($savedConfig.Upstream) {
                foreach ($prop in $savedConfig.Upstream.psobject.Properties) {
                    if ($prop.Value) {
                        $upstreamTools[$prop.Name] = $prop.Value
                    }
                }
            }
            if ($savedConfig.Downstream) {
                foreach ($prop in $savedConfig.Downstream.psobject.Properties) {
                    if ($prop.Value) {
                        $downstreamTools[$prop.Name] = $prop.Value
                    }
                }
            }
            if ($savedConfig.Analysis) {
                foreach ($prop in $savedConfig.Analysis.psobject.Properties) {
                    if ($prop.Value) {
                        $analysisTools[$prop.Name] = $prop.Value
                    }
                }
            }
            # User may up-downgrade VS (old path in new API), therefore we should check every time
        }
        catch { Show-Info "Tool path configuration file corrupted, manual import required" }
    }

    # Upstream tools import
    $i=0
    foreach ($tool in @($upstreamTools.Keys)) {
        $i++
        $savedPath = $upstreamTools[$tool]
        $isSwapNeeded = $true # Mark if tool path is confirmed

        # If there is saved path, select from 'update or import', otherwise 'import or not'
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n Detecting saved path for $tool in $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Upstream] ($i/$($upstreamTools.Count)) Replace $tool ? (y=swap，Enter=keep)"
            $isSwapNeeded = if ('y' -eq $c) { $true } else { $false }
        }
        else {
            Write-Host "`r`n No path saved for $tool, manual import needed" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Upstream] ($i/$($upstreamTools.Count)) Import $tool executable? (y=yes，Enter=skip)"
            $isSwapNeeded = if ('y' -eq $c) { $true } else { $false }
        }

        # Auto path detect with Invoke-AutoSearch
        if ($isSwapNeeded) {
            $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir
            if ($autoPath) {
                Write-Host " $tool found in: $autoPath" -ForegroundColor Green
                $useAuto = Read-Host "Proceed with this? (Enter=confirm, n=not this one)"
                if ($useAuto -eq 'n') {
                    $upstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
                }
                else {
                    $upstreamTools[$tool] = $autoPath
                }
            }
            else {
                Write-Host " Could not find $tool, manual import needed"
                if ($tool -eq 'svfi') {
                    Write-Host " Steam installation path of SVFI (one_line_shot_args.exe) is X:\SteamLibrary\steamapps\common\SVFI\"
                }
                elseif ($tool -eq 'vspipe') {
                    Write-Host " Default instal path for VapourSynth: C:\Program Files\VapourSynth\core\vspipe.exe"
                }
                elseif ($tool -eq 'avs2yuv') {
                    Write-Host " Both AviSynth (0.26) & AviSynth+ (0.30) are supported"
                }
                $upstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
            }
        }
        Show-Success "$tool imported: $($upstreamTools[$tool])"
        
        # Detect API version for vspipe, no matter tool swapping is not isn't needed
        if ($tool -eq 'vspipe' -and $upstreamTools[$tool]) {
            Write-Host ''
            Show-Info "Detecting VapourSynth pipe command..."
            $vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $upstreamTools[$tool]
            Show-Success $($vspipeInfo.Note)
        }
        elseif ($tool -eq 'avs2yuv' -and $upstreamTools[$tool]) {
            # AviSynth is not imported, cannot detect its version, requires manual specification
            while ($true) {
                Show-Info "Please select the version of avs2yuv(64).exe used:"
                $avs2yuvVer = Read-Host " [Default Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
                if ([string]::IsNullOrWhiteSpace($avs2yuvVer) -or 'a' -eq $avs2yuvVer) {
                    $isAVSPlus = $true
                    break
                }
                elseif ('b' -eq $avs2yuvVer) {
                    $isAvsPlus = $false
                    break
                }
                Show-Warning "Input value is beyond comprehension, please try again"
            }
        }
    }
    
    Write-Host ("─" * 60)
    Show-Info "Importing downstream tools..."
    $i=0
    foreach ($tool in @($downstreamTools.Keys)) {
        $i++
        $savedPath = $downstreamTools[$tool]

        # If there is saved path, select from 'update or import', otherwise 'import or not'
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n Detecting saved path for $tool in $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Downstream] ($i/$($downstreamTools.Count)) Replace $tool ? (y=swap，Enter=keep)"
            if ('y' -ne $c) { continue }
        }
        else {
            Write-Host "`r`n No path saved for $tool, manual import needed" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Downstream] ($i/$($downstreamTools.Count)) Import $tool executable? (y=yes，Enter=skip)"
            if ('y' -ne $c) { continue }
        }

        # Auto path detect with Invoke-AutoSearch
        $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir

        if ($autoPath) {
            Write-Host " $tool found in: $autoPath" -ForegroundColor Green
            $useAuto = Read-Host "Proceed with this? (Enter=confirm, n=not this one)"
            if ($useAuto -eq 'n') {
                $downstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
            }
            else { $downstreamTools[$tool] = $autoPath }
        }
        else {
            Write-Host " Could not find $tool, please locate it manually"
            $downstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
        }

        Show-Success "$tool imported: $($downstreamTools[$tool])"
    }

    Write-Host ("─" * 60)
    Show-Info "Importing analysis tools..."
    $i=0
    foreach ($tool in @($analysisTools.Keys)) {
        $i++
        $savedPath = $analysisTools[$tool]

        # If there is saved path, select from 'update or import', otherwise 'import or not'
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n Detecting saved path for $tool in $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Analysis] ($i/$($analysisTools.Count)) Replace $tool ? (y=swap，Enter=keep)"
            if ('y' -ne $c) { continue }
        }
        else {
            Write-Host "`r`n No path saved for $tool, manual import needed, `r`n skipping here makes manual import in step 3 necessary" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [Analysis] ($i/$($analysisTools.Count)) Import $tool executable? (y=yes，Enter=skip)"
            if ('y' -ne $c) { continue }
        }

        # Auto path detect with Invoke-AutoSearch
        $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir
        if ($autoPath) {
            Write-Host " $tool found in: $autoPath" -ForegroundColor Green
            $useAuto = Read-Host "Proceed with this? (Enter=confirm, n=not this one)"
            if ($useAuto -eq 'n') {
                $analysisTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
            }
            else { $analysisTools[$tool] = $autoPath }
        }
        else {
            Write-Host " Could not find $tool, please locate it manually"
            $analysisTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
        }

        Show-Success "$tool imported: $($analysisTools[$tool])"
    }

    # Merge all tools (using manual merge to avoid object reference/type issues caused by Clone())
    $tools = @{}
    # Copy upstream, downstream and analysis tools
    foreach ($k in $upstreamTools.Keys) { $tools[$k] = $upstreamTools[$k] }
    foreach ($k in $downstreamTools.Keys) { $tools[$k] = $downstreamTools[$k] }
    foreach ($k in $analysisTools.Keys) { $tools[$k] = $analysisTools[$k] }

    <#
    Show-Debug "Merged encoding tool list..."
    foreach ($k in $tools.Keys) {
        $type = if ($tools[$k]) { $tools[$k].GetType().Name } else { "Null" }
        Write-Host "  Key: [$k] | Value: [$($tools[$k])] | Type: $type"
    }
    #>

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
    $hasAnalysisTool =
        @('ffprobe') | Where-Object {
            $toolPath = $tools[$_]
            ($null -ne $toolPath) -and ($toolPath -ne '')
        }

    if (($hasUpstreamTool.Count -eq 0) -or ($hasDownstreamTool.Count -eq 0)) {
        Show-Error "At least 1 upstream tool and 1 downstream tool need to be selected`r`n (e.g. ffmpeg + x265 or ffmpeg + svtav1)"
        exit 1
    }
    if (!$hasAnalysisTool) {
        Show-Info "No analysis tool imported, manually import required in later scripts"
    }

    # Show toochains that could work
    Show-Info "Available encoding toolchains:"
    Write-Host ("─" * 60)

    # Construct “ID → PresetName” map
    $presetIdMap = [ordered]@{}
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
    
    foreach ($ap in $availablePresets) {
        $id   = $ap.Value.ID
        $name = $ap.Key
        $up   = $ap.Value.Upstream
        $down = $ap.Value.Downstream
        
        # [ordered]@{} Creates a System.Collections.Specialized.OrderedDictionary class
        # When $presetIdMap[$id] = $value and $id is an integer, it will be bound to Item[int index] first
        # This vandalises ID field, resulting into an empty dictionary
        $presetIdMap["$id"] = $name # Force string key
        Write-Host ("[{0,-2}]  {1,-22} {2,-12} {3}" -f $id, $name, $up, $down)
    }
    
    Write-Host ("─" * 60)

    $selectedPreset = $null
    if ($presetIdMap.Count -eq 0) {
        Show-Error "No complete toolchain combination available"
        exit 1
    }
    elseif ($presetIdMap.Count -eq 1) {
        # Select automatically if there's only one toolchain
        $first = $presetIdMap.GetEnumerator() | Select-Object -First 1
        $selectedId = $first.Key
        $selectedPreset = $first.Value
        Show-Success "Only one toolchain available, selecting: [$selectedId] $selectedPreset"
    }
    else { # Select a toolchain
        while ($true) {
            Write-Host ''
            $inputId = Read-Host "Please enter toolchain number (postive integer)"

            if ($inputId -match '^\d+$' -and $presetIdMap.Contains($inputId)) {
                $selectedPreset = $presetIdMap[$inputId]
                Show-Success "Toolchain selected: [$inputId] $selectedPreset"
                break
            }
            Show-Error "Invalid number, please enter a number from the list above"
        }
    } 

    # Generate batch processing content and append pipeline specifying commands
    # 1. Generate the currently selected main command
    $command =
        Get-CommandFromPreset $selectedPreset -tools $tools -vsAPI $vspipeInfo

    # 2. Generate alternate commands for other imported lines (REM write)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # Note: calling the Key property, not $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vsAPI $vspipeInfo
        $otherCommands += "REM PRESET[$presetName]: $cmdStr"
    }
    $remCommands = $otherCommands -join "`r`n"

    # Build batch file (needs double line break at the beginning of the file)
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

REM ========================================
REM Aux encoding cmdlines (Manual switch;
REM Remains empty with singular encoder import)
REM ========================================

{3}

echo.
echo Encoding Finished, input exit to exit...
echo.

timeout /t 1 /nobreak >nul
endlocal
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
        Write-Host ''
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
    
    # Save tool path config to JSON
    try {
        Confirm-FileDelete $toolsJson

        $configToSave = [ordered]@{
            Upstream   = $upstreamTools
            Downstream = $downstreamTools
            Analysis   = $analysisTools
            IsAvsPlus  = $isAvsPlus
            # VSPipeInfo = $vspipeInfo # User may up-downgrade VS (old path in new API), therefore we should check every time
            SaveDate   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        Write-JsonFile $toolsJson $configToSave
        Show-Success "Path configuration file saved: $toolsJson"
    }
    catch {
        Show-Warning ("Path configuration file save failed: " + $_)
    }

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