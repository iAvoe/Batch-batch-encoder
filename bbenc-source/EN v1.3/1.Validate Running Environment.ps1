<#
.SYNOPSIS
    Script execution environment validator
.DESCRIPTION
    Verify if the current system supports running batch and PowerShell scripts
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# Load globals
. "$PSScriptRoot\Common\Core.ps1"

#region Functions
function Test-Administrator {
    <#
    .SYNOPSIS
        Check script user role level
    #>
    [Security.Principal.WindowsPrincipal]$principal = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdministratorElevation {
    <#
    .SYNOPSIS
        Request Administrator priviledge
    #>
    Show-Info "Requesting Administrator priviledge..."
    
    $scriptPath = $PSCommandPath
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$scriptPath`"",
        '-WorkingDirectory', "`"$PWD`""
    )
    
    try {
        $process = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $arguments `
            -Verb RunAs `
            -PassThru `
            -Wait
        
        exit $process.ExitCode
    }
    catch {
        Show-Error "Failed to elevate priviledge $_"
        Write-Host "Press any button to exit..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
}

# Caveat: we only care about NTFS
function Test-FileSystemPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -IsValid })]
        [string]$Path
    )
    
    $report = [System.Text.StringBuilder]::new()
    
    try {
        # Ensure path exists
        if (-not (Test-Path -Path $Path)) {
            [void]$report.AppendLine("× Path not exist: $Path")
            return $report.ToString()
        }
        
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        
        # Get user name and role
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $userName = $currentUser.Name
        $userSid = $currentUser.User
        
        # Check user priviledge
        $hasModify = $false
        $hasFullControl = $false
        
        # User should have access to their %USERPROFILE%, or this script suite won't work
        foreach ($access in $acl.Access) {
            # Try to find user (SID、user name、group...)
            if ($access.IdentityReference -eq $userName -or 
                $access.IdentityReference -eq $userSid.Value -or
                $access.IdentityReference -eq "BUILTIN\Users" -or
                $access.IdentityReference -eq "NT AUTHORITY\Authenticated Users" -or
                $access.IdentityReference -eq "Everyone") {
                
                if ($access.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) {
                    $hasModify = $true
                }
                
                if ($access.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) {
                    $hasFullControl = $true
                }
            }
        }
        
        if ($hasModify) {
            [void]$report.AppendLine("√ User $env:USERNAME has basic Read/Write permission on $Path")
        }
        else {
            [void]$report.AppendLine("× User $env:USERNAME lacks basic Read/Write permission on $Path")
        }
        
        if ($hasFullControl) {
            [void]$report.AppendLine("√ User $env:USERNAME has full access to $Path")
        }
        else {
            [void]$report.AppendLine("× User $env:USERNAME has full access to $Path")
        }
    }
    catch {
        [void]$report.AppendLine("× Could not validate access premission to $($Path): $_")
    }
    
    return $report.ToString()
}

function Get-UACRegistryValues {
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        
        if (-not (Test-Path -Path $regPath)) {
            throw "Broken UAC Registry (If you see this, try repair Windows sooner than later)"
        }
        
        $values = Get-ItemProperty -Path $regPath -ErrorAction Stop
        
        return @{
            ConsentPromptBehaviorAdmin = [int]($values.ConsentPromptBehaviorAdmin)
            ConsentPromptBehaviorUser  = [int]($values.ConsentPromptBehaviorUser)
            PromptOnSecureDesktop      = [int]($values.PromptOnSecureDesktop)
            EnableLUA                  = [int]($values.EnableLUA)
        }
    }
    catch {
        Write-Warning "Could not read UAC Registry: $_"
        return $null
    }
}

function Set-UACRegistryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )
    
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        
        # Backup current value
        $backup = Get-UACRegistryValues
        if ($backup) {
            $backupJson = $backup | ConvertTo-Json -Compress
            $backupPath = "$env:TEMP\UAC_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $backupJson | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Host " Stored UAC backup in: $backupPath" -ForegroundColor Green
        }
        
        # Set new value
        foreach ($key in $Values.Keys) {
            Set-ItemProperty -Path $regPath -Name $key -Value $Values[$key] -Type DWord -ErrorAction Stop
            Write-Host "Configured $key = $($Values[$key])" -ForegroundColor Green
        }
        
        Write-Host " UAC Setting updated. Reboot required" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Error "Failed to configure UAC: $_"
        return $false
    }
}

function Show-HardwareInformation {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Show-Info "OS: $($os.Caption) (Build $($os.BuildNumber))"
    }
    catch {
        Show-Warning "Could not read OS attributes: $_"
    }
    
    Show-Border
    Show-Info "Motherboard"
    Show-Border
    
    try {
        $baseboard = Get-CimInstance -ClassName Win32_Baseboard -ErrorAction Stop
        
        $info = @(
            "Name:     $($baseboard.Product)",
            "Brand:    $($baseboard.Manufacturer)",
            "Model:    $($baseboard.Model)",
            "Serial:   $($baseboard.SerialNumber)",
            "Revision: $($baseboard.Version)"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "Could not read Motherboard attributes: $_"
    }
    
    Show-Border
    Show-Info "BIOS"
    Show-Border
    
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $info = @(
            "Name:    $($bios.Name)",
            "Version: $($bios.SMBIOSBIOSVersion)",
            "Release: $(($bios.ReleaseDate).ToString('yyyy-MM-dd'))"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "Could not read BIOS attributes: $_"
    }
    
    Show-Border
    Show-Info "Processor"
    Show-Border
    
    try {
        $processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        
        foreach ($processor in $processors) {
            $info = @(
                "Name:         $($processor.Name)",
                "Socket:       $($processor.SocketDesignation)",
                "Current Freq: $($processor.CurrentClockSpeed) MHz",
                "Maximum Freq: $($processor.MaxClockSpeed) MHz",
                "Core(s):      $($processor.NumberOfCores)",
                "Thread(s):    $($processor.NumberOfLogicalProcessors)",
                "L2 Cache:     $([math]::Round($processor.L2CacheSize/1KB, 2)) MB",
                "L3 Cache:     $([math]::Round($processor.L3CacheSize/1KB, 2)) MB",
                "Current Load: $($processor.LoadPercentage)%"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
    }
    catch {
        Show-Warning "Could not read Processor attributes: $_"
    }
    
    Show-Border
    Show-Info "Memory"
    Show-Border
    
    try {
        $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        
        $totalMemory = 0
        foreach ($module in $memoryModules) {
            $sizeGB = [math]::Round($module.Capacity / 1GB, 2)
            $totalMemory += $sizeGB
            
            $info = @(
                "Module:   $($module.Tag)",
                "Capacity: $sizeGB GB",
                "Brand:    $($module.Manufacturer)",
                "Model:    $($module.PartNumber)",
                "Speed:    $($module.Speed) MHz",
                "Serial:   $($module.SerialNumber)"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
        
        Show-Success "Total Memory: $totalMemory GB"
    }
    catch {
        Show-Warning "Could not read Memory attributes: $_"
    }
}
#endregion

#region Main
function Main {
    Show-Info "PowerShell Version"
    if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
        Show-Warning "PowerShell version is below 5.1 ($($PSVersionTable.PSVersion)), this may be incompatible"
    }
    else {
        Show-Success "PowerShell version meets minimum execution requirements ($($PSVersionTable.PSVersion))"
    }
    
    # Request administrator priviledge only when needed
    
    Show-Info "File System Permission Check"
    Show-Info "Validating access to C:\ directory root (Debug only)..."
    $cDriveReport = Test-FileSystemPermission -Path "C:\"
    Write-Host $cDriveReport
    
    Show-Info "Validating access to %USERPROFILE% directory ($($env:USERPROFILE))..."
    $profileReport = Test-FileSystemPermission -Path $env:USERPROFILE
    Write-Host $profileReport
    
    # 4. UAC 管理
    Show-Info "User Access Control (UAC) Configuration"
    
    $currentUAC = Get-UACRegistryValues
    if ($currentUAC) {
        if ($currentUAC.EnableLUA -eq 1) {
            Show-Info "UAC is currently enabled"
        }
        else {
            Show-Warning "UAC is currently disabled"
        }
    }
    
    do {
        Write-Host @"
 Select an option：
 A: Disable UAC (Hide trust prompt when running scripts)
 B: Do nothing
 C: Restore UAC (Recommended on public systems)
 Q: Exit
"@ -ForegroundColor Yellow
        
        $choice = Read-Host " Please input (A/B/C/Q)"
        
        switch ($choice.ToUpper()) {
            'A' {
                if (-not (Test-Administrator)) {
                    Show-Warning "Requesting Administrator previledge to modify UAC"
                    Write-Host " You could do this manually in Control Panel or Settings" -ForegroundColor Yellow
                    if ((Read-Host "Request Administrator previledge? (Y/N)").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "Skipped UAC modification"
                        break
                    }
                }
                
                $uacValues = @{
                    ConsentPromptBehaviorAdmin = 0
                    ConsentPromptBehaviorUser  = 0
                    PromptOnSecureDesktop      = 0
                    EnableLUA                  = 0
                }
                
                Show-Warning "Warning：Dsiabling UAC lowers OS security!"
                if ((Read-Host "Are you sure? (Input 'CONFIRM' to proceed)") -eq 'CONFIRM') {
                    if (Set-UACRegistryValues -Values $uacValues) {
                        Show-Success "UAC Disabled. Reboot required"
                    }
                }
                else {
                    Show-Info "Skipped"
                }
                
                break
            }
            'C' { # Restore UAC
                if (-not (Test-Administrator)) {
                    Show-Warning "Requesting Administrator previledge to modify UAC"
                    Write-Host " You could do this manually in Control Panel or Settings" -ForegroundColor Yellow
                    if ((Read-Host "Request Administrator previledge? (Y/N)").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "Skipped"
                        break
                    }
                }
                
                $uacValues = @{
                    ConsentPromptBehaviorAdmin = 5
                    ConsentPromptBehaviorUser  = 3
                    PromptOnSecureDesktop      = 1
                    EnableLUA                  = 1
                }
                
                if (Set-UACRegistryValues -Values $uacValues) {
                    Show-Success "UAC Setting restored. Reboot required"
                }
                
                break
            }
            'B' {
                Show-Info "Skipped"
                break
            }
            'Q' {
                Show-Info "Exit"
                exit 0
            }
            default {
                Show-Error "Unknown option, please try again"
            }
        }
    }
    while ($choice.ToUpper() -notin @('A', 'B', 'C', 'Q'))
    
    # Show Hardware details
    Show-Info "System hardware information" -ForegroundColor
    
    Show-HardwareInformation
    
    # Complete
    Show-Border
    Show-Success "Script environment validation completed"
    
    if ($currentUAC -and $currentUAC.EnableLUA -eq 0) {
        Show-Warning "UAC is currently disabled, please consider raise UAC level after using this script suite"
    }
    
    Write-Host ""
    Write-Host "Press any button to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
#endregion

try { Main }
catch {
    Show-Error "Script execution failed: $_"
    Write-Host "Press any button to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}