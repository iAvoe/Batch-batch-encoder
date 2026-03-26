<#
.SYNOPSIS
    脚本运行环境检测工具
.DESCRIPTION
    检查系统是否支持运行 PowerShell 和批处理脚本。繁体本地化由繁化姬实现：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.5
#>

# 加载共用代码
. "$PSScriptRoot\Common\Core.ps1"

#region 辅助函数
function Test-Administrator {
    <#
    .SYNOPSIS
        检查当前会话是否以管理员权限运行
    #>
    [Security.Principal.WindowsPrincipal]$principal = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdministratorElevation {
    Show-Info "正在请求管理员权限..."
    
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
        Write-Error "权限提升失败：$_"
        Write-Host "按任意键退出..." -ForegroundColor Yellow
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
        # 确保路径存在
        if (-not (Test-Path -Path $Path)) {
            [void]$report.AppendLine("× 路径不存在: $Path")
            return $report.ToString()
        }
        
        $acl = Get-Acl -Path $Path -ErrorAction Stop
        
        # 获取当前用户的身份
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $userName = $currentUser.Name
        $userSid = $currentUser.User
        
        # 检查权限
        $hasModify = $false
        $hasFullControl = $false
        
        foreach ($access in $acl.Access) {
            # 检查用户是否匹配（考虑SID、用户名、组等）
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
            [void]$report.AppendLine("√ 用户 $env:USERNAME 拥有对 $Path 的一般读写权限")
        }
        else {
            [void]$report.AppendLine("× 用户 $env:USERNAME 没有对 $Path 的一般读写权限")
        }
        
        if ($hasFullControl) {
            [void]$report.AppendLine("√ 用户 $env:USERNAME 拥有对 $Path 的完全控制权限")
        }
        else {
            [void]$report.AppendLine("× 用户 $env:USERNAME 没有对 $Path 的完全控制权限")
        }
    }
    catch {
        [void]$report.AppendLine("× 无法检查 $Path 的权限: $_")
    }
    
    return $report.ToString()
}

function Get-UACRegistryValues {
    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        
        if (-not (Test-Path -Path $regPath)) {
            throw "UAC 注册表损坏（如果你看到这行，则建议尽快运行 Windows 修复）"
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
        Write-Warning "无法读取 UAC 注册表设置: $_"
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
        
        # 备份当前设置
        $backup = Get-UACRegistryValues
        if ($backup) {
            $backupJson = $backup | ConvertTo-Json -Compress
            $backupPath = "$env:TEMP\UAC_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $backupJson | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Host "已备份 UAC 设置到: $backupPath" -ForegroundColor Green
        }
        
        # 设置新值
        foreach ($key in $Values.Keys) {
            Set-ItemProperty -Path $regPath -Name $key -Value $Values[$key] -Type DWord -ErrorAction Stop
            Write-Host "已设置 $key = $($Values[$key])" -ForegroundColor Green
        }
        
        Write-Host "UAC 设置已更新，需要重启系统才能生效。" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Error "设置 UAC 失败: $_"
        return $false
    }
}

function Show-HardwareInformation {
    # 操作系统信息
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Show-Info "操作系统: $($os.Caption) (Build $($os.BuildNumber))"
    }
    catch {
        Show-Warning "无法获取操作系统信息: $_"
    }
    
    Show-Border
    Show-Info "主板信息"
    Show-Border
    
    try {
        $baseboard = Get-CimInstance -ClassName Win32_Baseboard -ErrorAction Stop
        
        $info = @(
            "名称: $($baseboard.Product)",
            "厂商: $($baseboard.Manufacturer)",
            "型号: $($baseboard.Model)",
            "序列号: $($baseboard.SerialNumber)",
            "版本: $($baseboard.Version)"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "无法获取主板信息: $_"
    }
    
    Show-Border
    Show-Info "BIOS信息"
    Show-Border
    
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        
        $info = @(
            "名称: $($bios.Name)",
            "版本: $($bios.SMBIOSBIOSVersion)",
            "发布日期: $(($bios.ReleaseDate).ToString('yyyy-MM-dd'))"
        )
        
        $info | ForEach-Object { Write-Host "  $_" }
    }
    catch {
        Show-Warning "无法获取BIOS信息: $_"
    }
    
    Show-Border
    Show-Info "处理器信息"
    Show-Border
    
    try {
        $processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        
        foreach ($processor in $processors) {
            $info = @(
                "处理器: $($processor.Name)",
                "插槽: $($processor.SocketDesignation)",
                "当前频率: $($processor.CurrentClockSpeed) MHz",
                "最大频率: $($processor.MaxClockSpeed) MHz",
                "核心数: $($processor.NumberOfCores)",
                "线程数: $($processor.NumberOfLogicalProcessors)",
                "L2 缓存: $([math]::Round($processor.L2CacheSize/1KB, 2)) MB",
                "L3 缓存: $([math]::Round($processor.L3CacheSize/1KB, 2)) MB",
                "当前负载: $($processor.LoadPercentage)%"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
    }
    catch {
        Show-Warning "无法获取处理器信息: $_"
    }
    
    Show-Border
    Show-Info "内存信息"
    Show-Border
    
    try {
        $memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop
        
        $totalMemory = 0
        foreach ($module in $memoryModules) {
            $sizeGB = [math]::Round($module.Capacity / 1GB, 2)
            $totalMemory += $sizeGB
            
            $info = @(
                "模块: $($module.Tag)",
                "容量: $sizeGB GB",
                "厂商: $($module.Manufacturer)",
                "型号: $($module.PartNumber)",
                "速度: $($module.Speed) MHz",
                "序列号: $($module.SerialNumber)"
            )
            
            $info | ForEach-Object { Write-Host "  $_" }
            Write-Host ""
        }
        
        Show-Success "总内存: $totalMemory GB"
    }
    catch {
        Show-Warning "无法获取内存信息: $_"
    }
}
#endregion

#region 主逻辑
function Main {
    # 1. 检查 PowerShell 版本
    Show-Info "PowerShell 版本检查"
    if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
        Show-Warning "PowerShell 版本低于 5.1 ($($PSVersionTable.PSVersion)), 某些功能可能无法正常工作"
    }
    else {
        Show-Success "PowerShell 版本符合要求 ($($PSVersionTable.PSVersion))"
    }
    
    # 2. 仅在需要管理员权限时请求提升
    
    # 3. 检查文件系统权限
    Show-Info "文件系统权限检查"
    Show-Info "检查 C:\ 根目录权限（仅供故障排查）..."
    $cDriveReport = Test-FileSystemPermission -Path "C:\"
    Write-Host $cDriveReport
    
    Show-Info "检查用户配置文件目录权限..."
    $profileReport = Test-FileSystemPermission -Path $env:USERPROFILE
    Write-Host $profileReport
    
    # 4. UAC 管理
    Show-Info "用户账户控制（UAC）管理"
    
    $currentUAC = Get-UACRegistryValues
    if ($currentUAC) {
        if ($currentUAC.EnableLUA -eq 1) {
            Show-Info "UAC 当前已启用"
        }
        else {
            Show-Warning "UAC 当前已禁用"
        }
    }
    
    do {
        Write-Host @"
 选择 UAC 操作选项：
 A: 禁用 UAC（每次运行脚本不再弹出警告）
 B: 不更改（继续检测）
 C: 恢复 UAC（公用电脑建议）
 Q: 退出脚本
"@ -ForegroundColor Yellow
        
        $choice = Read-Host " 选择 (A/B/C/Q)"
        
        switch ($choice.ToUpper()) {
            'A' {
                # 禁用 UAC
                if (-not (Test-Administrator)) {
                    Show-Warning "需要管理员权限来修改 UAC 设置"
                    Write-Host " 你也可以在控制面板/设置里自行调整" -ForegroundColor Yellow
                    if ((Read-Host "是否请求管理员权限?（Y/N）").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "已跳过 UAC 修改"
                        break
                    }
                }
                
                $uacValues = @{
                    ConsentPromptBehaviorAdmin = 0
                    ConsentPromptBehaviorUser  = 0
                    PromptOnSecureDesktop      = 0
                    EnableLUA                  = 0
                }
                
                Show-Warning "警告：禁用 UAC 会降低系统安全性！"
                if ((Read-Host "确认要禁用 UAC 吗? (输入 'CONFIRM' 以确认)") -eq 'CONFIRM') {
                    if (Set-UACRegistryValues -Values $uacValues) {
                        Show-Success "UAC 已禁用，需要重启系统生效"
                    }
                }
                else {
                    Show-Info "已取消操作"
                }
                
                break
            }
            
            'C' {
                # 恢复 UAC
                if (-not (Test-Administrator)) {
                    Show-Warning "需要管理员权限来修改 UAC 设置"
                    Write-Host " 你也可以在控制面板/设置里自行调整" -ForegroundColor Yellow
                    if ((Read-Host "是否请求管理员权限?（Y/N）").ToUpper() -eq 'Y') {
                        Request-AdministratorElevation
                    }
                    else {
                        Show-Info "已跳过 UAC 修改"
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
                    Show-Success "UAC 已恢复到默认设置，需要重启系统生效"
                }
                
                break
            }
            
            'B' {
                Show-Info "跳过 UAC 修改"
                break
            }
            
            'Q' {
                Show-Info "退出脚本"
                exit 0
            }
            
            default {
                Show-Error "无效的选择，请重新输入"
            }
        }
    } while ($choice.ToUpper() -notin @('A', 'B', 'C', 'Q'))
    
    # 5. 显示系统硬件信息
    Show-Info "系统硬件信息" -ForegroundColor
    Show-HardwareInformation
    
    # 6. 完成提示
    Show-Border
    Show-Success "系统检测完成"
    
    if ($currentUAC -and $currentUAC.EnableLUA -eq 0) {
        Show-Warning "注意：UAC 当前已禁用，建议在处理完毕后重新启用以提高安全性"
    }
    
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
#endregion

# 执行主函数
try { Main }
catch {
    Show-Error "脚本执行出错: $_"
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}