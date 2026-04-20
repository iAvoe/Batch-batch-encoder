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

<#
$toolHintsZHCN = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 发布版的路径是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安装版 VapourSynth 的默认可执行文件路径是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
$toolHintsZHTW = @{
    'svfi'    = " SVFI（one_line_shot_args.exe）Steam 發布版的路徑是 X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " 安裝版 VapourSynth 的默認可執行文件路徑是 C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv"
}
#>
$toolHintsEN = @{
    'svfi'    = " Steam SVFI installation (one_line_shot_args.exe) is at X:\SteamLibrary\steamapps\common\SVFI\"
    'vspipe'  = " Default install path for VapourSynth: C:\Program Files\VapourSynth\core\vspipe.exe"
    'avs2yuv' = " Both AviSynth (0.26) & AviSynth+ (0.30) are supported"
}

#region Helpers
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

# Instead of parsing versionss, just try some commands and find one that triggers deeper error
function Get-VSPipeY4MArgument {
    param([Parameter(Mandatory=$true)][string]$VSpipePath)
    $tests = @(
        @("-c", "y4m"),
        @("--container", "y4m"),
        @("--y4m")
    )

    foreach ($testArgs in $tests) {
        Write-Host (" Test: {0} {1}" -f $VSpipePath, ($testArgs -join " "))
        
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
    throw "Could not detect vspipe's Y4M parameter. Either VapourSynth or Python environment is corrupted"
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
        $debugInfo | ConvertTo-Json | Write-Host -ForegroundColor DarkGray
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

# Generalized path value assignment function
function Update-ToolMap {
    param ([System.Collections.IDictionary]$targetMap, $sourceObj)
    if (-not $sourceObj) { return }
    foreach ($prop in $sourceObj.psobject.Properties) {
        if ($prop.Value) {
            $targetMap[$prop.Name] = $prop.Value
        }
    }
}

# Generalized too path setter
function Import-ToolPaths {
    param (
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$ToolsToHave, # Not items in JSON
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [hashtable]$toolTips,
        [scriptblock]$PostImportAction = { } # Import logic for specific tools
    )

    $i = 0
    $total = $ToolsToHave.Count
    foreach ($tool in $ToolsToHave.Keys) {
        $i++
        $savedPath = $ToolsToHave[$tool] # $upstreamTools is updated by Read-Json before this function runs
        $isSwapNeeded = $false

        # 1. Ask to swap or add or not
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n Detecting saved path for $tool in $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$($upstreamTools.Count)) Replace $tool ? (y=yes，Enter=keep)"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }
        else {
            Write-Host "`r`n No path saved for $tool, manual import needed" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [$CategoryName] ($i/$total) Import $tool executable? (y=yes，Enter=skip)"
            if ('y' -eq $c) { $isSwapNeeded = $true }
        }

        # 2. Import logics
        if ($isSwapNeeded) {
            $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $ScriptDir
            if ($autoPath) {
                Write-Host " $tool found in: $autoPath" -ForegroundColor Green
                $useAuto = Read-Host "Proceed with this? (Enter=confirm, n=not this one)"
                if ($useAuto -eq 'n') {
                    $upstreamTools[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
                }
                else { $ToolsToHave[$tool] = $autoPath }
            }
            else {
                Write-Host " Could not find $tool, manual import needed"
                if ($toolHints.ContainsKey($tool)) {
                    Write-Host $toolHints[$tool] -ForegroundColor DarkGray
                }
                $ToolsToHave[$tool] = Select-File -Title "Select $tool executable" -ExeOnly
            }
        }

        # 3. Show results
        if ($ToolsToHave[$tool]) {
            Show-Success "$tool imported: $($ToolsToHave[$tool])"
            # 4. Run post import logics
            $PostImportAction.Invoke($tool, $ToolsToHave[$tool])
        }
    }
}
#endregion

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
    Write-Host ("─" * 50)

    # Attempt to read saved tools.json, but it can be outdated, therefore manual confirmation is required
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Info "Detecting config file ($($savedConfig.SaveDate)), loading now..."
            Update-ToolMap $upstreamTools   $savedConfig.Upstream
            Update-ToolMap $downstreamTools $savedConfig.Downstream
            Update-ToolMap $analysisTools   $savedConfig.Analysis
            # User may up-downgrade VS (old path in new API), therefore we should check every time
        }
        catch { Show-Info "Tool path configuration file corrupted, manual import required" }
    }

    Show-Info "Importing upstream encoding tools..."
    Import-ToolPaths -ToolsToHave $upstreamTools -CategoryName "Upstream" -ScriptDir $scriptDir -toolTips $toolHintsEN -PostImportAction {
        param($tool, $path)
        # Detect API version for vspipe no matter swapped or not
        if ($tool -eq 'vspipe') {
            Write-Host ''
            Show-Info "Detecting VapourSynth pipe parameters..."
            $global:vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $path
            Show-Success $global:vspipeInfo.Note
        }
        elseif ($tool -eq 'avs2yuv') {
            # Cannot detect AviSynth version as we don't import it, requires manual specification
            while ($true) {
                Show-Info "Please select the version of avs2yuv(64).exe used: "
                $avs2yuvVer = Read-Host " [Default Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
                if ([string]::IsNullOrWhiteSpace($avs2yuvVer) -or 'a' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $true; break
                }
                elseif ('b' -eq $avs2yuvVer) {
                    $global:isAvsPlus = $false; break
                }
                Show-Warning "Incomprehensible input value, please try again"
            }
        }
    }
    
    Write-Host ("─" * 50)
    Show-Info "Importing downstream tools..."
    Import-ToolPaths -ToolsToHave $downstreamTools -CategoryName "Downstream" -toolTips $toolHintsEN -ScriptDir $scriptDir

    Write-Host ("─" * 50)
    Show-Info "Importing analysis tools..."
    Import-ToolPaths -ToolsToHave $analysisTools -CategoryName "Analysis" -toolTips $toolHintsEN -ScriptDir $scriptDir

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
    Write-Host ("─" * 50)

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
    Write-Host ("─" * 50)
    
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
    
    Write-Host ("─" * 50)

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
        Get-CommandFromPreset $selectedPreset -tools $tools -vsAPI $global:vspipeInfo

    # 2. Generate alternate commands for other imported lines (REM write)
    $otherCommands = @()
    foreach ($p in $availablePresets) {
        Show-Debug "Generating based on preset: $($p.Key)"
        # Note: calling the Key property, not $p
        $presetName = $p.Key

        if ($presetName -eq $selectedPreset) { continue }

        $cmdStr =
            Get-CommandFromPreset $presetName -tools $tools -vsAPI $global:vspipeInfo
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