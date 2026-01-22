<#
.SYNOPSIS
    腳本運行環境檢測工具
.DESCRIPTION
    檢查系統是否支持運行 PowerShell 和批處理腳本。繁體在地化由繁化姬實現：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# 載入共用代碼
. "$PSScriptRoot\Common\Core.ps1"

#region 輔助函數
function Test-Administrator {
    <#
    .SYNOPSIS
        檢查當前會話是否以管理員權限運行
    #>
    [Security.Principal.WindowsPrincipal]$principal = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdministratorElevation {
    Show-Info "正在請求管理員權限..."
    
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
        Write-Error "權限提升失敗：$_"
        Write-Host "按任意鍵退出..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 1
    }
}

function Test-FileSystemPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -Path $_ -IsValid })]
        [string]$Path
    )
    
    $report = [System.Text.StringBuilder]::new()
    
    try {
        # 確保路徑存在
        if (-not (Test-Path -Path $Path)) {
            [void]$report.AppendLine("× 路徑不存在: $Path")
            return $report.ToString()
        }
        
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        
        # 獲取當前用戶的身份
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $userName = $currentUser.Name
        $userSid = $currentUser.User
        
        # 檢查權限
        $hasModify = $false
        $hasFullControl = $false
        
        foreach ($access in $acl.Access) {
            # 檢查用戶是否匹配（考慮SID、使用者名稱、組等）
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
            [void]$report.AppendLine("√ 用戶 $env:USERNAME 擁有對 $Path 的一般讀寫權限")
        }
        else {
            [void]$report.AppendLine("× 用戶 $env:USERNAME 沒有對 $Path 的一般讀寫權限")
        }
        
        if ($hasFullControl) {
            [void]$report.AppendLine("√ 用戶 $env:USERNAME 擁有對 $Path 的完全控制權限")
        }
        else {
            [void]$report.AppendLine("× 用戶 $env:USERNAME 沒有對 $Path 的完全控制權限")
        }
    }
    catch {
        [void]$report.AppendLine("× 無法檢查 $Path 的權限: $_")
    }
    
    return $report.ToString()
}

function Get-UACRegistryValues {
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        
        if (-not (Test-Path -Path $regPath)) {
            throw "UAC 註冊表損壞（如果你看到這行，則建議盡快運行 Windows 修復）"
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
        Write-Warning "無法讀取 UAC 註冊表設置: $_"
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
        
        # 備份當前設置
        $backup = Get-UACRegistryValues
        if ($backup) {
            $backupJson = $backup | ConvertTo-Json -Compress
            $backupPath = "$env:TEMP\UAC_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $backupJson | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Host "已備份 UAC 設置到: $backupPath" -ForegroundColor Green
        }
        
        # 設置新值
        foreach ($key in $Values.Keys) {
            Set-ItemProperty -Path $regPath -Name $key -Value $Values[$key] -Type DWord -ErrorAction Stop
            Write-Host "已設置 $key = $($Values[$key])" -ForegroundColor Green
        }
        
        Write-Host "UAC 設置已更新，需要重啟系統才能生效。" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Error "設置 UAC 失敗: $_"
        return $false
    }
}

function Show-HardwareInformation {
    # 操作系統資訊
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Show-Info "操作系統: $($os.Caption) (Build $($os.BuildNumber))"
    }
    catch {
        Show-Warning "無法獲取操作系統資訊: $_"
    }
    
    Show-Border
    Show-Info "主板資訊"
    Show-Border
    
    try {
        $baseboard = Get-CimInstance -ClassName Win32_Baseboard -ErrorAction Stop
        
        $info = @(
            "名稱: $($baseboard.Product)",
            "廠商: $($baseboard.Manufacturer)",
            "型號: $($baseboard.Model)",
            "序號: $($baseboard.SerialNumber)",
            "版本: $($baseboard.Version)"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "無法獲取主板資訊: $_"
    }
    
    Show-Border
    Show-Info "BIOS資訊"
    Show-Border
    
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        
        $info = @(
            "名稱: $($bios.Name)",
            "版本: $($bios.SMBIOSBIOSVersion)",
            "發布日期: $(($bios.ReleaseDate).ToString('yyyy-MM-dd'))"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "無法獲取BIOS資訊: $_"
    }
    
    Show-Border
    Show-Info "處理器資訊"
    Show-Border
    
    try {
        $processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        
        foreach ($processor in $processors) {
            $info = @(
                "處理器: $($processor.Name)",
                "插槽: $($processor.SocketDesignation)",
                "當前頻率: $($processor.CurrentClockSpeed) MHz",
                "最大頻率: $($processor.MaxClockSpeed) MHz",
                "核心數: $($processor.NumberOfCores)",
                "執行緒數: $($processor.NumberOfLogicalProcessors)",
                "L2 快取: $([math]::Round($processor.L2CacheSize/1KB, 2)) MB",
                "L3 快取: $([math]::Round($processor.L3CacheSize/1KB, 2)) MB",
                "當前負載: $($processor.LoadPercentage)%"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
    }
    catch {
        Show-Warning "無法獲取處理器資訊: $_"
    }
    
    Show-Border
    Show-Info "記憶體資訊"
    Show-Border
    
    try {
        $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        
        $totalMemory = 0
        foreach ($module in $memoryModules) {
            $sizeGB = [math]::Round($module.Capacity / 1GB, 2)
            $totalMemory += $sizeGB
            
            $info = @(
                "模組: $($module.Tag)",
                "容量: $sizeGB GB",
                "廠商: $($module.Manufacturer)",
                "型號: $($module.PartNumber)",
                "速度: $($module.Speed) MHz",
                "序號: $($module.SerialNumber)"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
        
        Show-Success "總記憶體: $totalMemory GB"
    }
    catch {
        Show-Warning "無法獲取記憶體資訊: $_"
    }
}
#endregion

#region 主邏輯
function Main {
    # 1. 檢查 PowerShell 版本
    Show-Info "PowerShell 版本檢查"
    if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
        Show-Warning "PowerShell 版本低於 5.1 ($($PSVersionTable.PSVersion)), 某些功能可能無法正常工作"
    }
    else {
        Show-Success "PowerShell 版本符合要求 ($($PSVersionTable.PSVersion))"
    }
    
    # 2. 僅在需要管理員權限時請求提升
    
    # 3. 檢查文件系統權限
    Show-Info "文件系統權限檢查"
    Show-Info "檢查 C:\ 根目錄權限（僅供故障排查）..."
    $cDriveReport = Test-FileSystemPermission -Path "C:\"
    Write-Host $cDriveReport
    
    Show-Info "檢查用戶設定檔目錄權限..."
    $profileReport = Test-FileSystemPermission -Path $env:USERPROFILE
    Write-Host $profileReport
    
    # 4. UAC 管理
    Show-Info "用戶帳戶控制（UAC）管理"
    
    $currentUAC = Get-UACRegistryValues
    if ($currentUAC) {
        if ($currentUAC.EnableLUA -eq 1) {
            Show-Info "UAC 當前已啟用"
        }
        else {
            Show-Warning "UAC 當前已禁用"
        }
    }
    
    do {
        Write-Host @"
 選擇 UAC 操作選項：
 A: 禁用 UAC（每次執行腳本不再彈出警告）
 B: 不更改（繼續檢測）
 C: 恢復 UAC（公用電腦建議）
 Q: 退出腳本
"@ -ForegroundColor Yellow
        
        $choice = Read-Host " 選擇 (A/B/C/Q)"
        
        switch ($choice.ToUpper()) {
            'A' {
                # 禁用 UAC
                if (-not (Test-Administrator)) {
                    Show-Warning "需要管理員權限來修改 UAC 設置"
                    Write-Host " 你也可以在控制面板/設置裡自行調整" -ForegroundColor Yellow
                    if ((Read-Host "是否請求管理員權限?（Y/N）").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "已跳過 UAC 修改"
                        break
                    }
                }
                
                $uacValues = @{
                    ConsentPromptBehaviorAdmin = 0
                    ConsentPromptBehaviorUser  = 0
                    PromptOnSecureDesktop      = 0
                    EnableLUA                  = 0
                }
                
                Show-Warning "警告：禁用 UAC 會降低系統安全性！"
                if ((Read-Host "確認要禁用 UAC 嗎? (輸入 'CONFIRM' 以確認)") -eq 'CONFIRM') {
                    if (Set-UACRegistryValues -Values $uacValues) {
                        Show-Success "UAC 已禁用，需要重啟系統生效"
                    }
                }
                else {
                    Show-Info "已取消操作"
                }
                
                break
            }
            
            'C' {
                # 恢復 UAC
                if (-not (Test-Administrator)) {
                    Show-Warning "需要管理員權限來修改 UAC 設置"
                    Write-Host " 你也可以在控制面板/設置裡自行調整" -ForegroundColor Yellow
                    if ((Read-Host "是否請求管理員權限?（Y/N）").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "已跳過 UAC 修改"
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
                    Show-Success "UAC 已恢復到默認設置，需要重啟系統生效"
                }
                
                break
            }
            
            'B' {
                Show-Info "跳過 UAC 修改"
                break
            }
            
            'Q' {
                Show-Info "退出腳本"
                exit 0
            }
            
            default {
                Show-Error "無效的選擇，請重新輸入"
            }
        }
    } while ($choice.ToUpper() -notin @('A', 'B', 'C', 'Q'))
    
    # 5. 顯示系統硬體資訊
    Show-Info "系統硬體資訊" -ForegroundColor
    Show-HardwareInformation
    
    # 6. 完成提示
    Show-Border
    Show-Success "系統檢測完成"
    
    if ($currentUAC -and $currentUAC.EnableLUA -eq 0) {
        Show-Warning "注意：UAC 當前已禁用，建議在處理完畢後重新啟用以提高安全性"
    }
    
    Write-Host ""
    Write-Host "按任意鍵退出..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
#endregion

# 執行主函數
try { Main }
catch {
    Show-Error "腳本執行出錯: $_"
    Write-Host "按任意鍵退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}