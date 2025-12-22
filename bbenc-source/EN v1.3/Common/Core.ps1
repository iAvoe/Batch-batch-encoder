# Reloading is allowed because the :PipePresets variable is easily lost during testing.
# if ($script:__CORE_LOADED) { return }
# $script:__CORE_LOADED = $true

# UTF-8 No BOM
$Global:utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
# Use UTF-8 with BOM so that CMD can correctly recognize it.
$Global:utf8BOM = New-Object System.Text.UTF8Encoding($true)

# Define the toolchain composition (must match the key used during import)
$Global:PipePresets = @{
    'ffmpeg_x264'        = @{ ID=1;  Upstream='ffmpeg';      Downstream='x264' }
    'ffmpeg_x265'        = @{ ID=2;  Upstream='ffmpeg';      Downstream='x265' }
    'ffmpeg_svtav1'      = @{ ID=3;  Upstream='ffmpeg';      Downstream='svtav1' }
    'vspipe_x264'        = @{ ID=4;  Upstream='vspipe';      Downstream='x264' }
    'vspipe_x265'        = @{ ID=5;  Upstream='vspipe';      Downstream='x265' }
    'vspipe_svtav1'      = @{ ID=6;  Upstream='vspipe';      Downstream='svtav1' }
    'avs2yuv_x264'       = @{ ID=7;  Upstream='avs2yuv';     Downstream='x264' }
    'avs2yuv_x265'       = @{ ID=8;  Upstream='avs2yuv';     Downstream='x265' }
    'avs2yuv_svtav1'     = @{ ID=9;  Upstream='avs2yuv';     Downstream='svtav1' }
    'avs2pipemod_x264'   = @{ ID=10; Upstream='avs2pipemod'; Downstream='x264' }
    'avs2pipemod_x265'   = @{ ID=11; Upstream='avs2pipemod'; Downstream='x265' }
    'avs2pipemod_svtav1' = @{ ID=12; Upstream='avs2pipemod'; Downstream='svtav1' }
    'svfi_x264'          = @{ ID=13; Upstream='svfi';        Downstream='x264' }
    'svfi_x265'          = @{ ID=14; Upstream='svfi';        Downstream='x265' }
    'svfi_svtav1'        = @{ ID=15; Upstream='svfi';        Downstream='svtav1' }
}

# Define a cache folder; Create if missing
$Global:TempFolder = $env:USERPROFILE + "\bbenc\"
if (-not (Test-Path -PathType Container $Global:TempFolder)) {
    New-Item -ItemType Directory -Force -Path $Global:TempFolder
}
Clear-Host

# Load sub modules
$base = $PSScriptRoot
. "$base\Console.ps1"
. "$base\UI.ps1"
. "$base\FileUtils.ps1"