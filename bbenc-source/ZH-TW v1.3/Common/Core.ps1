# 由於測試時容易丟失 :PipePresets 變量，因此允許重載
# if ($script:__CORE_LOADED) { return }
# $script:__CORE_LOADED = $true

# UTF-8 No BOM
$Global:utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
# UTF-8 帶 BOM，以便 CMD 正確識別
$Global:utf8BOM = New-Object System.Text.UTF8Encoding($true)

# 定義工具鏈組合（必須與導入時的 Key 一致）
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

# 定義緩存文件夾，如果不存在就創建
$Global:TempFolder = $env:USERPROFILE + "\bbenc\"
if (-not (Test-Path -PathType Container $Global:TempFolder)) {
    New-Item -ItemType Directory -Force -Path $Global:TempFolder
}
Clear-Host

# 加載子模塊
$base = $PSScriptRoot
. "$base\Console.ps1"
. "$base\UI.ps1"
. "$base\FileUtils.ps1"