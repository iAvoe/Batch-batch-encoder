cls
Function testwritemodify {
    Param ([Parameter(Mandatory=$true)]$tstxt)
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a function as it would trigger a value return, modify Write-Debug instead
    $modifyAcl=$true
    if ((Test-Path $tstxt) -eq $true) {
        Try {[io.file]::OpenWrite($tstxt).close()} Catch {$modifyAcl=$false}
        Remove-Item $tstxt
        if ($modifyAcl -eq $true) {return 3} elseif ($modifyAcl -eq $false){return 2}
    } else {return 1}
}
$tstxt="C:\tmp-testWriteModify.txt"
Write-Output "Testing write access only, this file should be deleted - 检测写入权限用, 该文件应被删除">$tstxt

Function loweruaclvl {
    Try{Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Type DWord -Value 0
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Type DWord -Value 0
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "PromptOnSecureDesktop" -Type DWord -Value 0
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Type DWord -Value 0
    } Catch {return 1}
    return 0
}

Function raiseuaclvl {
    Try{Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Type DWord -Value 5
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorUser" -Type DWord -Value 3
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "PromptOnSecureDesktop" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Type DWord -Value 1
    } Catch {return 0}
    return 1
}

$txtst=(testwritemodify -tstxt $tstxt)
if     ($txtst -eq 3) {Write-Output "√ Write & modify privilege to C drive is normal - C盘文件写入和编辑权限正常`r`n"}
elseif ($txtst -eq 2) {Write-Warning "× Write privilege to C drive is normal, but missing modify privilege - C盘文件写入权限正常, 但没有编辑权限`r`n"}
elseif ($txtst -eq 1) {Write-Warning "× No write access to C drive - 没有C盘写入权限`r`n"; pause; exit} 

if ($PSVersionTable.PSVersion -lt 5.1) {Write-Warning "× PowerShell version is below 5.1, this script may not work - PowerShell版本低于5.1, 可能无法运行`r`n"}
else {Write-Output "√ PowerShell version is 5.1 or higher - PowerShell版本为5.1或更高`r`n"}

"Workstation name / 计算机名: "+$env:computername+", "+(Get-WmiObject -class Win32_OperatingSystem).Caption
Write-Output "`r`n-------------Motherboard主板--------------"
$MB = Get-WmiObject Win32_Baseboard | Select Status,Product,Manufacturer,Model,SerialNumber,Version
"Name 名称: "+$MB.Product
"Brand厂商: "+$MB.Manufacturer
"Stat 状况: "+$MB.Status
"Model型号: "+$MB.Model
"S/N序列号: "+$MB.SerialNumber
"Rev. 版本: "+$MB.Version
Write-Output "`r`n-------------------BIOS-------------------"
$BiosCond = Get-CimInstance Win32_BIOS | Select Status,Name,BIOSVersion,SMBIOSBIOSVersion,ReleaseDate
"Name 名称:         "+$BiosCond.Name
"Stat 状况:         "+$BiosCond.Status
"Ver. 版本:         "+$BiosCond.BIOSVersion
"Reles.date 发布于: "+$BiosCond.ReleaseDate
"Rng.ver. 现用版本: "+$BiosCond.SMBIOSBIOSVersion
Write-Output "`r`n-------------Processor处理器--------------"
$AllProcs = Get-CimInstance Win32_Processor | Select Availability,CurrentClockSpeed,MaxClockSpeed,Name,DeviceID,NumberOfCores,ThreadCount,LoadPercentage,VoltageCaps,VirtualizationFirmwareEnabled,L2CacheSize,L3CacheSize,SocketDesignation
#Lopped for multi-node systems 为多路处理器系统准备的循环
ForEach ($_ in $AllProcs) {
    #Distingulishi devices' status 区分设备运行与供电状态
    Switch ($_.Availability) {
        2{[string]$prState = "Unknown 未知"}
        3{[string]$prState = "Running/Full-Power/Normal 运行中/正常"}
        4{[string]$prState = "Warning - 报警中"}
        5{[string]$prState = "Under Test 处于测试状态"}
        18{[string]$prState = "Paused - 暂停中"}
        11{[string]$prState = "Not Installed - 未安装"}
        12{[string]$prState = "Install Error - 安装错误"}
        16{[string]$prState = "Powercycle - 重新启动中"}
        17{[string]$prState = "Powersave: Warning - 省电模式: 警告"}
        13{[string]$prState = "Powersave: Unknown - 省电模式: 未知"}
        14{[string]$prState = "Powersave: LowPower - 省电模式: 节能"}
        15{[string]$prState = "Powersave: Standby - 省电模式: 待机"}
        20{[string]$prState = "Not Configured - 处理器缺少状态参数"}
        21{[string]$prState = "Quiesced - 反馈被阻止"}
        Default{$prState = $_.Availability}
    }
    "Name     型号:         "+$_.Name
    "Socket   插槽:         "+$_.SocketDesignation
    "Status   状态:         "+$prState
    "Cur.freq.当前频率:     "+$_.CurrentClockSpeed+"Mhz"
    "Max.freq.最大频率:     "+$_.MaxClockSpeed+"Mhz"
    "L2cache size 二缓:     "+$_.L2CacheSize / 1024+"MB"
    "L3cache size 三缓:     "+$_.L3CacheSize / 1024+"MB"
    "Voltage cap  最大电压: "+$_.VoltageCaps / 1000+"V"
    "Loads percent当前负载: "+$_.LoadPercentage+"%"
    "Virtualize on虚拟化开: "+$_.VirtualizationFirmwareEnabled
}
Write-Output "`r`n----------------Memory内存-----------------"

$AllMemos = Get-WmiObject -Class Win32_PhysicalMemory | Select Manufacturer,ConfiguredVoltage,MaxVoltage,PartNumber,Speed,Tag,Capacity
ForEach ($_ in $AllMemos) {
    
    #标题和居中计算
    [string]$heading = $_.Tag
    [int]$eCenter = $tCenter - $heading.Length/2
    [int]$gCenter = $eCenter/4

    #Calcualte memory size - 计算内存容量
    [int]$MemSize = $_.Capacity / 1GB
    Write-Output "`r`n------$heading------"
    "Size  容量: "+$MemSize+"GB"
    "Make  厂商: "+$_.Manufacturer
    "Model 型号: "+$_.PartNumber
    "Freq. 频率: "+$_.Speed+"MT/s(Mbps)"
    "Max. voltage 最大电压: "+$_.MaxVoltage / 1000+"V"
    "Defined volt.设定电压: "+$_.ConfiguredVoltage / 1000+"V"
}
Write-Output "`r`n----Debugging enc-options检查编码设定中----"
$pme=$pool=""
[int]$cores=(wmic cpu get NumberOfCores)[2]
if ($cores -gt 21) {$pme="--pme"; Write-Output "√ Detecting processor's core count reaching 22, added x265 option: --pme`r`n√ 检测到处理器核心数达22, 已添加x265参数: --pme`r`n"}
else {Write-Output "√ Detecting processor core counts are less than 22, evicted x265 option: --pme`r`n√ 检测到处理器核心数小于22, 已去除x265参数: --pme`r`n"}

$procNodes=0
$AllProcs=Get-CimInstance Win32_Processor | Select Availability
ForEach ($_ in $AllProcs) {if ($_.Availability -eq 3) {$procNodes+=1}}
if ($procNodes -eq 1)     {Write-Output "√ Detected $procNodes installed processor, evited x265 option: --pools`r`n√ 检测到安装了 $procNodes 颗处理器, 已去除x265参数: --pools"}
elseif ($procNodes -eq 2) {$pools="--pools +,-"}
elseif ($procNodes -eq 4) {$pools="--pools +,-,-,-"}
elseif ($procNodes -eq 6) {$pools="--pools +,-,-,-,-,-"}
elseif ($procNodes -eq 8) {$pools="--pools +,-,-,-,-,-,-,-"}
elseif ($procNodes -gt 8) {Write-Warning "? Detecting an unusal amount of installed processor nodes ($procNodes), please add option --pools manually`r`n？ 检测到异常: 安装了超过8颗处理器($procNodes), 需手动填写--pools"} #Cannot use else, otherwise -eq 1 gets accounted for "unusual amount of comp nodes"
if ($procNodes -gt 1) {Write-Output "√ Detected $procNodes installed processors, added x265 option: $pools`r`n√ 检测到安装了 $procNodes 颗处理器, 已添加x265参数: $pools"}

Write-Warning "`r`n接下来的操作会更改注册表/The following operation involves registry value alteration"
Do {Switch (Read-Host "`r`n「User Access Control」由于每次运行PowerShell脚本都会弹出用户账户控制警告，选择/Each time running PSscripts would panic UAC, select:`r`n`r`n[A: 关闭/Disable UAC | B: 不更改/Don't make changes | C: 恢复(公用电脑)/Restore UAC (public computers)]") {
        a {$UACops=1; Write-Output "`r`nLowering UAC level.../正在降低用户账户控制通知级别..."; $uacc=loweruaclvl} #UAC_ON=1, UAC_OFF=0
        c {$UACops=3; Write-Output "`r`nRestoring UAC level.../正在恢复用户账户控制通知级别..."; $uacc=raiseuaclvl} #UAC_ON=1, UAC_OFF=0
        b {$UACops=2; Write-Output "`r`nSkipped/已跳过!"}
        default {$UACops=0; Write-Output "输入错误, 重试"}
    }
} While ($UACops -eq 0)

$UACreg=(Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System | Select ConsentPromptBehaviorAdmin,ConsentPromptBehaviorUser,PromptOnSecureDesktop,EnableLUA)
if     ($UACreg.EnableLUA -eq 1) {Write-Output "`r`nUAC is currently ON. `r`n用户账户控制通知目前已启用."}
elseif ($UACreg.EnableLUA -eq 0) {Write-Output "`r`nUAC is currently OFF.`r`n用户账户控制通知目前已关闭."}

if ($uacc -eq $UACreg.EnableLUA) {#确认用户账户控制返回结果$uacc与注册表符合. Cross referencing registry for UAC on/off status, to make sure $uacc works
    if     (($UACops -eq 1) -and ($uacc -eq 1)) {Write-Warning "`r`nFailed to lower UAC level. Please type UAC in Start menu, and lower the warning manually...`r`n关闭用户账户控制通知失败. 请在开始菜单输入UAC，然后手动降低警告阈限."}
    elseif (($UACops -eq 3) -and ($uacc -eq 0)) {Write-Warning "`r`nRestore UAC level failed.  Please type UAC in Start menu, and raise the warning manually...`r`n恢复用户账户控制通知失败. 请在开始菜单输入UAC，然后手动提高警告阈限."}
} else {Write-Warning "`r`nFailed to determine UAC level. Please type UAC in Start menu, and raise/lower the warning manually `r`n获取用户账户控制通知状态失败. 请在开始菜单输入UAC，然后手动提高/降低警告阈限."}

pause