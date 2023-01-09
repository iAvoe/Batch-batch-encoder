cls
Function whereisit($startPath='DESKTOP') {
    #「启动」启用System.Windows.Forms选择文件的GUI交互窗
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    #打开选择文件的GUI交互窗, 用if拦截误操作
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName}
    return $endPath
}

"计算机名: "+$env:computername+", "+(Get-WmiObject -class Win32_OperatingSystem).Caption
Write-Output "-------------------主板-------------------"
$MB = Get-WmiObject Win32_Baseboard | Select Status,Product,Manufacturer,Model,SerialNumber,Version
"名称: "+$MB.Product
"厂商: "+$MB.Manufacturer
"状况: "+$MB.Status
"型号: "+$MB.Model
"序列号: "+$MB.SerialNumber
"版本: "+$MB.Version
Write-Output "-----------------主板BIOS-----------------"
$BiosCond = Get-CimInstance Win32_BIOS | Select Status,Name,BIOSVersion,SMBIOSBIOSVersion,ReleaseDate
"名称:          "+$BiosCond.Name
"状况:          "+$BiosCond.Status
"安装BIOS版本:   "+$BiosCond.BIOSVersion
"发行日期:       "+$BiosCond.ReleaseDate
"系统用BIOS版本: "+$BiosCond.SMBIOSBIOSVersion+"`n"
"注：MSI微星BIOS版号写作如7C91vA9的数字；其中vA9代表Version A.90或其它数字"
Write-Output "------------------处理器------------------"
$AllProcs = Get-CimInstance Win32_Processor | Select Availability,CurrentClockSpeed,MaxClockSpeed,Name,DeviceID,NumberOfCores,ThreadCount,LoadPercentage,VoltageCaps,VirtualizationFirmwareEnabled
#为多路处理器系统准备的循环
ForEach ($_ in $AllProcs) {
    #区分设备运行与供电状态
    Switch ($_.Availability) {
        3{[string]$prState = "正常"}
        2{[string]$prState = "未知"}
        14{[string]$prState = "处于低功耗模式"}
        13{[string]$prState = "状态未知, 休眠中"}
        15{[string]$prState = "待机，休眠中"}
        18{[string]$prState = "暂停中"}
        11{[string]$prState = "未装"}
        17{[string]$prState = "报警，待机省电中"}
        12{[string]$prState = "安装错误，报警中"}
        14{[string]$prState = "报警中"}
        Default{$prState = $_.Availability}
    }
    "型号:        "+$_.Name
    "频率:        当前"+$_.CurrentClockSpeed+"Mhz, 最大"+$_.MaxClockSpeed+"Mhz"
    "状态:        "+$prState
    "最大工作电压: "+$_.VoltageCaps / 1000+"V"
    "当前负载:     "+$_.LoadPercentage+"%"
    "虚拟化已开:   "+$_.VirtualizationFirmwareEnabled
}
Write-Output "-------------------内存-------------------"
$AllMemos = Get-WmiObject -Class Win32_PhysicalMemory | Select Manufacturer,ConfiguredVoltage,MaxVoltage,PartNumber,Speed,Tag,Capacity
ForEach ($_ in $AllMemos) {
    #计算内存容量
    [int]$MemSize = $_.Capacity / 1GB

    "容量："+$MemSize+"GB"
    "厂商: "+$_.Manufacturer
    "型号: "+$_.PartNumber
    "频率: "+$_.Speed+"MT/s(Mbps)"
    "最大工作电压: "+$_.MaxVoltage / 1000+"V, 目前："+$_.ConfiguredVoltage / 1000+"V"
}

#「@MrNetTek」高DPI显示渲染模式的System.Windows.Forms
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class ProcessDPI {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();      
}
'@
$null = [ProcessDPI]::SetProcessDPIAware()

Set-PSDebug -Strict

#「启动」手动更改ffprobe和视频源路径, 缺点是PowerShell要求路径-文件名不准含方括号[ ], 所以只能拷一份改名
Write-Output "----ffprobe-notepad view +param parser----"

#「启动」导入原文件
Read-Host "将打开[导入源文件]的选择窗, 可能会在窗口底层弹出. 按Enter继续"
$direPath = whereisit

#「启动」定位ffprobe
Read-Host "将打开[定位ffprobe.exe]的选择窗. 按Enter继续"
$fprbPath = whereisit

#「ffprobe获取源信息」尝试读取并生成参数, 增加了路径中空格的支持
$parsProbe = $fprbPath+" -i '$direPath' -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=pix_fmt,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
Invoke-Expression $parsProbe > "C:\temp_v_info.csv"

#「ffprobe获取源信息」用CSV读取模块映射array数据, 由于源文件没有所以添加目录A~F, 由于不能直接导入进变量所以创建了中间文件
$ffprobeCSV = Import-Csv "C:\temp_v_info.csv" -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X #防范mkv五花八门的视频帧量标注方法
Remove-Item "C:\temp_v_info.csv"

#「ffprobe获取源信息」debug时, 手动运行以上命令再尝试运行: $ffprobeCSV
#「组装csv中获取的参数」第一次组装, 分两次组装以提高未来可编辑性, 防范ffprobe输出值变卦
$pixel_format = "-pix_fmt "+$ffprobeCSV.B
$color_matrix = "--colormatrix "+$ffprobeCSV.C
$trans_chrctr = "--transfer "+$ffprobeCSV.D
$mpegtag_frames = "--frames "+$ffprobeCSV.F
$mkvtag_frames = "--frames "+$ffprobeCSV.X

Switch ($ffprobeCSV.B) {
    yuv420p {Write-Output "步骤3选择源视频的[色彩空间格式]中选: A"}
    yuv420p10le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: B"}
    yuv420p12le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: C"}
    yuv422p {Write-Output "步骤3选择源视频的[色彩空间格式]中选: D"}
    yuv422p10le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: E"}
    yuv422p12le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: F"}
    yuv444p {Write-Output "步骤3选择源视频的[色彩空间格式]中选: G"}
    yuv444p10le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: H"}
    yuv444p12le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: I"}
    gray {Write-Output "步骤3选择源视频的[色彩空间格式]中选: J"}
    gray10le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: K"}
    gray12le {Write-Output "步骤3选择源视频的[色彩空间格式]中选: L"}
    nv12 {Write-Output "步骤3选择源视频的[色彩空间格式]中选: M"}
    nv16 {Write-Output "步骤3选择源视频的[色彩空间格式]中选: N"}
    default {Write-Output "x265不兼容的色彩空间: "+$pixel_format.Substring(9)}
}

#「ffprobe获取源信息」组装出参数
$ffmpegAD = $pixel_format+" "
$x265AD = $color_matrix+" "+$trans_chrctr+"`r`nMPEGtag: "+$mpegtag_frames+"`r`nMKVtag:  "+$mkvtag_frames
Write-Output "ffmpeg参数添加: `r`n$ffmpegAD "
Write-Output "`r`nx265参数添加...unknown和N/A除外: `r`n$x265AD"
Write-Output "`r`n源视频量多时, 逐个清点总帧数--frames的步骤太繁琐故可略, 缺点是不再显示ETA（预计完成时间）"

#「ffprobe获取源信息」给人看, 使用了" ` "来保留双引号, 其实如果不传递变量, 直接写文件路径就可以能直接运行, 但是这里就要改为字符串string格式打包成变量
$readProbe = $fprbPath+" -i '$direPath' -select_streams v:0 -v error -hide_banner -show_streams -show_frames -read_intervals `"%+#1`" -show_entries frame=top_field_first:stream=codec_long_name,width,coded_width,height,coded_height,pix_fmt,color_range,field_order,r_frame_rate,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries -of ini"
#「ffprobe获取源信息」将字符串重新唤醒为命令行, 输出到文件, 但为整洁遂打开而删除, 所以要手动另存为保存, notepad实现了另一个窗口打开
Invoke-Expression $readProbe > "C:\视频流信息(用另存为保存).ini"
#「ffprobe获取源信息」由于垃圾优化导致速度太慢，必须手动添加1秒延迟。。。不信你删掉Timeout试试
Timeout /T 1 | out-null
notepad "C:\视频流信息(用另存为保存).ini"
Timeout /T 1 | out-null
Remove-Item "C:\视频流信息(用另存为保存).ini"

[int]$cores = (wmic cpu get NumberOfCores)[2]
if ($cores -gt 11) {"检测到本机处理器核心数达12, 步骤3会自动添加 --pme 参数"}

pause