function Show-Error   ($Message) { Write-Host " [error]`r`n $Message" -ForegroundColor Red }
function Show-Warning ($Message) { Write-Host " [warning]`r`n $Message" -ForegroundColor Yellow }
function Show-Success ($Message) { Write-Host " [ok]      $Message" -ForegroundColor Green }
function Show-Info    ($Message) { Write-Host " [info]    $Message" -ForegroundColor Cyan }
function Show-Debug   ($Message) { Write-Host " [Debug]`r`n $Message" -ForegroundColor Magenta }
function Show-Border { Write-Host ("="*50) -ForegroundColor Blue }