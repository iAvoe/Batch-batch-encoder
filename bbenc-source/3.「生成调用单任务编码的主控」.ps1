cls #「启动-」大批量版生成的主控缺失文件名, 所以要提醒
Read-Host "大批量模式下, 生成的主控里没有导入用的文件名, 因此需要手动逐个填写导入文件名`r`nx264一般自带libav, x265一般不带, 因此x265输出文件后缀一般是未封装成.mp4的.hevc. 按Enter继续"

function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #检测文件名是否符合Windows命名规则

Function whereisit($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件的GUI交互窗
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName}
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ SelectedPath = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    #打开选择文件的GUI交互窗, 用if拦截误操作
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    #if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}#只有路径才加"\", 单文件模式下注释掉
    return $endPath
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

#「启动A」生成1~n个"enc_[序号].bat"单文件版不需要
#[array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
#[int]$qty=0#从0开始数
#Do {[int]$qty = (Read-Host -Prompt "指定[之前生成压制批处理]的[整数数量]")
#        if ($qty -eq 0) {"输入了非整数或空值"} elseif ($qty -gt 15625) {Write-Warning "编码次数超过15625"; pause; exit}
#} While ($qty -eq 0)

#「启动B」定位导出主控文件用路径
Read-Host "将打开[导出主控批处理]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$exptPath = whichlocation
Write-Output "选择的路径为 $exptPath`r`n"

#「启动C」选择是否在导出文件序号上补零, 由于int变量$qty得不到字长Length, 所以先转string再取值. 单文件下不需要
#if ($qty -gt 9) {#个位数下关闭补零
#    Do {[string]$leadCHK=""; [int]$ldZeros=0
#        Switch (Read-Host "选择之前[y启用了 | n关闭了]导出压制文件名的[序号补0]. 如导出十位数文件时写作01, 02...") {
#            y {$leadCHK="y"; Write-Output "√ 启用补零`r`n"; $ldZeros=$qty.ToString().Length}
#            n {$leadCHK="n"; Write-Output "× 关闭补零`r`n"}
#            default {Write-Warning "输入错误, 重试"}
#        }
#    } While ($leadCHK -eq "")
#    [string]$zroStr="0"*$ldZeros #得到.ToString('000')所需的'000'部分, 如果关闭补零则$zroStr为0, 补零计算仍然存在但没有效果
#} else {[string]$zroStr="0"}

#「启动D」定位导出压制结果用路径
Read-Host "将打开[导出压制文件]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$fileEXP = whichlocation
Write-Output "选择的路径为 $fileEXP`r`n"

#「启动E」导入原文件, 注意步骤2中已经导入了ffmpeg等工具的路径. 所以步骤3只导入源. 注意变量也为此而改了名
Write-Output "参考[视频文件类型]https://en.wikipedia.org/wiki/Video_file_format"
Write-Output "由于步骤2已填写ffmpeg, vspipe, avs2yuv, avs2pipemod的所在路径, 所以步骤3中选择的是待压制文件`r`n"
Do {$IMPchk=$vidIMP=$vpyIMP=$avsIMP=$apmIMP=""
    Switch (Read-Host "之前选择的pipe上游方案是[A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod]") {
        a {$IMPchk="a"; Write-Output "`r`n选择了ffmpeg----视频源. 已打开[定位源]的选窗"; $vidIMP=whereisit}
        b {$IMPchk="b"; Write-Output "`r`n选择了vspipe----.vpy源. 已打开[定位源]的选窗"; $vpyIMP=whereisit}
        c {$IMPchk="c"; Write-Output "`r`n选择了avs2yuv---.avs源. 已打开[定位源]的选窗"; $avsIMP=whereisit}
        d {$IMPchk="d"; Write-Output "`r`n选了avs2pipemod-.avs源. 已打开[定位源]的选窗"; $apmIMP=whereisit}
        default {Write-Warning "输入错误, 重试"}
    }
} While ($IMPchk -eq "")

#「启动F1S」整合并反馈选取的路径/文件
$impEXTc=$vidIMP+$vpyIMP+$avsIMP+$apmIMP
Write-Output "`r`n大批量/单文件模式下选择的路径/文件为 $impEXTc`r`n"

#「启动F2」单文件模式下获取文件名与后缀, 用于生成默认导出文件名. 由于变量污染问题摒弃了Get-ChildItem
if (($impEXTc -eq "") -eq $true) {Write-Error "× 没有导入任何文件"; pause; exit}
else {
    $impEXTc=[io.path]::GetExtension($impEXTc)
    $impFNM=[io.path]::GetFileNameWithoutExtension($impEXTc)
}

#检测输入文件格式是否匹配选择的线路 (vspipe=".vpy", avs2yuv=".avs")
if (($IMPchk -eq "d") -or ($IMPchk -eq "c")) {
    if (($impEXTc -eq ".avs") -eq $false) {Write-Warning "文件后缀名是 $impEXTc 而非 .avs`r`n"} #if选项用于防止ffmpeg线路下输入了空值$impEXTc
} elseif ($IMPchk -eq "b") {
    if (($impEXTc -eq ".vpy") -eq $false) {Write-Warning "文件后缀名是 $impEXTc 而非 .vpy`r`n"} #大批量模式下输入的是路径所以失效
} #注: 导入路径: $impEXTa, 导入文件: $impEXTc, 导出路径: $fileEXP

#「启动E」Avs2pipemod需要的文件
if ($IMPchk -eq "d") {
    Read-Host "将为Avs2pipemod打开[选择avisynth.dll]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
    $apmDLL=whereisit #Avs2pipemod需要导入avisynth.dll
    $DLLchk=(Get-ChildItem $apmDLL).Extension #检查文件后缀是否为.dll并报错
    if (($DLLchk -eq ".dll") -eq $false) {Write-Warning "文件后缀名是 $apmDLL 而非 .dll"}
    Write-Output "√ 已添加avs2pipemod参数: $apmDLL`r`n"
} else {$apmDLL="X:\Somewhere\avisynth.dll"}

#「启动F1」非ffmpeg上游方案下, 导入一份视频文件给ffprobe检测. 唯独单文件版的ffmpeg线路下会直接导入视频, 所以和大批量版全部线路导入路径不同
if ($IMPchk -eq "a") {$impEXTc=$vidIMP}
else {
    Read-Host "将为ffprobe打开[送检用源视频]的路径选择窗, 因为大批量版下只会导入路径, 而单文件版下ffprobe无法检测.vpy和.avs"
    $impEXTc=whereisit
}
#「启动F2」大批量模式, 所有线路导入的都是路径, 所以要另导入一份视频文件给ffprobe检测
#Read-Host "将为ffprobe打开[送检用源视频]的路径选择窗. 注意ffprobe无法检测.vpy和.avs"
#$impEXTc=whereisit

#「启动G」定位ffprobe
Read-Host "将打开[定位ffprobe.exe]的选择窗. 按Enter继续"
$fprbPath=whereisit

#「ffprobeA2」开始检测片源, 由于mkv有给不同视频流标注多种视频总帧数的tag功能, 导致封装视频的人会错标 NUMBER_OF_FRAMES 成 NUMBER_OF_FRAMES-eng (两者分别占据csv的第24,25号), 所以同时尝试读取两者, 缺少任意一值则X位中显示另一值, 所以只检测X位
$parsProbe = $fprbPath+" -i '$impEXTc' -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
Invoke-Expression $parsProbe > "C:\temp_v_info.csv"

#例: $parsProbe = "D:\ffprobe.exe -i `"F:\Asset\Video\BDRip私种\[Beatrice-Raws] Anne Happy [BDRip 1920x1080 x264 FLAC]\[Beatrice-Raws] Anne Happy 01 [BDRip 1920x1080 x264 FLAC].mkv`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#例: $parsProbe = "D:\ffprobe.exe -i `"N:\SolLevante_HDR10_r2020_ST2084_UHD_24fps_1000nit.mov`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#Invoke-Expression $parsProbe > "C:\temp_v_info.csv"
#Notepad "C:\temp_v_info.csv"

#「ffprobeB2」用CSV读取模块映射array数据, 由于源文件没有所以添加目录A~F, 由于ffprobe生成的CSV不能直接导入进变量, 并且为方便debug(Remove-Item换成Notepad), 所以创建了中间文件
$ffprobeCSV = Import-Csv "C:\temp_v_info.csv" -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA
Remove-Item "C:\temp_v_info.csv" #由于多数Windows系统只有C盘, 所以临时生成CSV在C盘

$WxH="--input-res "+$ffprobeCSV.B+"x"+$ffprobeCSV.C+""
$color_matrix="--colormatrix "+$ffprobeCSV.F
$trans_chrctr="--transfer "+$ffprobeCSV.G
$fps="--fps "+$ffprobeCSV.H
$fmpgfps="-r "+$ffprobeCSV.H
Write-Output "√ 已添加x264/5参数: $color_matrix $trans_chrctr $fps $WxH`r`n√ 已添加ffmpeg参数: $fmpgfps`r`n"

#「ffprobeC」ffprobe获取视频总帧数并赋值到$x265VarA中, 唯单文件版可用
if ($ffprobeCSV.I -match "^\d+$") {
    $nbrFrames = "--frames "+$ffprobeCSV.I
    Write-Output "检测到MPEGtag视频总帧数`r`n√ 已添加x264/5参数: $nbrFrames"
} elseif ($ffprobeCSV.AA -match "^\d+$") {
    $nbrFrames = "--frames "+$ffprobeCSV.AA
    Write-Output "检测到MKVtag视频总帧数`r`n√ 已添加x264/5参数: $nbrFrames"
} else {Write-Output "× 总帧数的数据被删, 将留空x264/5参数--frames, 缺点是不再显示ETA（预计完成时间）"}
#获得视频总帧数$nbrFrames

#「ffprobeD1」获取色彩空间格式, 给ffmpeg, VapourSynth, AviSynth, AVS2PipeMod, x264和x265赋值
[string]$avsCSP=[string]$avsD=[string]$encCSP=[string]$ffmpegCSP=[string]$encD=$null
Do {Switch ($ffprobeCSV.D) {
        yuv420p     {Write-Output "检测到源的色彩空间==[yuv420p 8bit ]"; $avsCSP="-csp i420"; $avsD="-depth 8";  $encCSP="--input-csp i420"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv420p"}
        yuv420p10le {Write-Output "检测到源的色彩空间==[yuv420p 10bit]"; $avsCSP="-csp i420"; $avsD="-depth 10"; $encCSP="--input-csp i420"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv420p10le"}
        yuv420p12le {Write-Output "仅x265支持的色彩空间[yuv420p 12bit]"; $avsCSP="-csp i420"; $avsD="-depth 12"; $encCSP="--input-csp i420"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv420p12le"}
        yuv422p     {Write-Output "检测到源的色彩空间==[yuv422p 8bit ]"; $avsCSP="-csp i422"; $avsD="-depth 8";  $encCSP="--input-csp i422"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv422p"}
        yuv422p10le {Write-Output "检测到源的色彩空间==[yuv422p 10bit]"; $avsCSP="-csp i422"; $avsD="-depth 10"; $encCSP="--input-csp i422"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv422p10le"}
        yuv422p12le {Write-Output "仅x265支持的色彩空间[yuv422p 12bit]"; $avsCSP="-csp i422"; $avsD="-depth 12"; $encCSP="--input-csp i422"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv422p12le"}
        yuv444p     {Write-Output "检测到源的色彩空间==[yuv444p 8bit ]"; $avsCSP="-csp i444"; $avsD="-depth 8";  $encCSP="--input-csp i444"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv444p"}
        yuv444p10le {Write-Output "检测到源的色彩空间==[yuv444p 10bit]"; $avsCSP="-csp i444"; $avsD="-depth 10"; $encCSP="--input-csp i444"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv444p10le"}
        yuv444p12le {Write-Output "仅x265支持的色彩空间[yuv444p 12bit]"; $avsCSP="-csp i444"; $avsD="-depth 12"; $encCSP="--input-csp i444"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv444p12le"}
        gray        {Write-Output "检测到源的色彩空间==[yuv400p 8bit ]"; $avsCSP="-csp i400"; $avsD="-depth 8";  $encCSP="--input-csp i400"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt gray"}
        gray10le    {Write-Output "检测到源的色彩空间==[yuv400p 10bit]"; $avsCSP="-csp i400"; $avsD="-depth 10"; $encCSP="--input-csp i400"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt gray10le"}
        gray12le    {Write-Output "仅x265支持的色彩空间[yuv400p 12bit]"; $avsCSP="-csp i400"; $avsD="-depth 12"; $encCSP="--input-csp i400"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt gray12le"}
        nv12        {Write-Output "仅x265支持的色彩空间[ nv12 12bit ]";  $avsCSP="-csp AUTO"; $avsD="-depth 12"; $encCSP="--input-csp nv12"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt nv12"}
        nv16        {Write-Output "仅x265支持的色彩空间[ nv16 16bit ]";  $avsCSP="-csp AUTO"; $avsD="-depth 16"; $encCSP="--input-csp nv16"; $encD="--input-depth 16"; $ffmpegCSP="-pix_fmt nv16"}
        default     {Write-Warning "! 不兼容的色彩空间"($ffprobeCSV.D)}
    }
} While ($ffmpegCSP -eq $null)
if ($ffmpegCSP -ne $null) {Write-Output "√ 已添加ffmpeg参数: $ffmpegCSP`r`n√ 已添加avs2yuv参数: $avsCSP $avsD`r`n"}
if ($avsCSP -eq "-csp AUTO") {Write-Warning "avs2yuv可能不兼容nv12/nv16色彩空间"}

#「启动H」选择程序. x264或x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "选择pipe下游程序 [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`n选择了x265--A线路. 已打开[定位x265.exe]的选窗"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`n选择了x264--B线路. 已打开[定位x264.exe]的选窗"; $x264Path=whereisit}
        default {Write-Warning "输入错误, 重试"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "√ 选择了 $encEXT`r`n"

#「启动I」选择导出压制结果文件名的多种方式, 集数变量$serial于下方的循环中实现序号叠加
$vidEXP=[io.path]::GetFileNameWithoutExtension($impEXTc)
Do {Switch (Read-Host "`r`n 选择导出压制结果的文件名[A: 手动填写 | B: 选择文件并拷贝 | C: $vidEXP]`r`n注意PowerShell默认紧挨的方括号为一般表达式, 如[随便][什么]之间要隔开") {
        a { Do {$vidEXP=Read-Host "`r`n填写导出用的文件名(无后缀), 于序号处填 `$serial. `$serial后不能紧挨英文字母. 如 [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)"
                if (($vidEXP.Contains("`$serial")) -eq $false) {Write-Warning "文件名中不含序号变量`$serial, 或输入了空值"}
            } While (($vidEXP.Contains("`$serial")) -eq $false)
            #[string]$serial=($s).ToString($zroStr) #下面的for循环提供$s后才会用到的变量储存
            #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #下面的for循环中, 用户输入的变量需要Expand才能激活$serial. 用时由于$s随着循环变化, 所以每个循环都要重新赋值
        }
        b { Write-Output "已打开[复制文件名]的选择窗"
            $vidEXP=whereisit
            $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
            $vidEXP+="_$serial" #单文件模式下移除
            Write-Output "选项A会在末尾添加序号, 所以文件名尾会多出`"_`"`r`n"
        }
        c {$vidEXP+="_$serial"} #单文件模式下移除
        default {Write-Warning "输入错误, 重试`r`n"}
    }
} While (($vidEXP.Contains("$serial")) -eq $false)
Write-Output "√ 写入了导出文件名 $vidEXP`r`n"

#「启动I, J」1: 根据选择x264/5来决定输出.hevc/.mp4. 2: x265下据cpu核心数量, 节点数量添加pme/pools. x265一般不自带libav(不支持导出MP4), x264一般带libav但不支持pme和pools
if ($ENCops -eq "b") {$vidEXP+=".mp4"}
elseif ($ENCops -eq "a") {
    $vidEXP+=".hevc"
    $pme=$pool=""
    $procNodes=0
    
    [int]$cores=(wmic cpu get NumberOfCores)[2]
    if ($cores -gt 21) {$pme="--pme"; Write-Output "检测到处理器核心数达22`r`n√ 已添加x265参数: --pme"}

    $AllProcs=Get-CimInstance Win32_Processor | Select Availability
    ForEach ($_ in $AllProcs) {if ($_.Availability -eq 3) {$procNodes+=1}}
    if ($procNodes -eq 2) {$pools="--pools +,-"}
    elseif ($procNodes -eq 4) {$pools="--pools +,-,-,-"}
    elseif ($procNodes -eq 6) {$pools="--pools +,-,-,-,-,-"}
    elseif ($procNodes -eq 8) {$pools="--pools +,-,-,-,-,-,-,-"}
    elseif ($procNodes -gt 8) {Write-Warning "？ 检测到安装了超过8颗处理器($procNodes), 需手动填写--pools"} #不能用else, 否则-eq 1也会被算进去
    if ($procNodes -gt 1) {Write-Output "检测到安装了 $procNodes 颗处理器`r`n√ 已添加x265参数: $pools"}
} 

Set-PSDebug -Strict
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #导出utf-8NoBOM文本编码用

#注: 导入: $impEXTc 导出: $fileEXP
#「初始化」$ffmpegPar(固定参数变量)的末尾不带空格
#「限制」$ffmpegPar-ameters不能写在输入文件命令(-i)前面, ffmpeg参数 "-hwaccel"不能写在输入文件后面. 导致了字符串重组的流程变复杂, 及更多字符串变量的参与
$ffmpegParA="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -an -f yuv4mpegpipe -strict unofficial" #步骤2已添加pipe参数"- | -", 所以此处省略
$ffmpegParB="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -c:v copy" #生成临时mp4封装来兼容ffmpeg封装mkv用
$vspipeParA="--y4m"
$avsyuvParA="$avsCSP $avsD"
$avsmodParA="`"$apmDLL`" -y4mp" #注: avs2pipemod使用"| -"而非其他工具的"- | -"pipe参数(左侧无"-"). y4mp, y4mt, y4mb代表逐行, 上场优先隔行, 下场优先隔行. 为了降低代码复杂度所以不做隔行

#「初始化」ffmpeg, vspipe, avs2yuv, avs2pipemod变化参数, 和大批量版不同
$ffmpegVarA=$vspipeVarA=$avsyuvVarA=$avsmodVarA="-i `"$impEXTc`""

#「初始化」x264/5固定参数, 末尾加空格, 3C版之外没有--fps参数, 唯独单文件版有$nbrFrames
$x265ParA="$encD $color_matrix $trans_chrctr $fps $WxH $encCSP $pme $pools --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --me umh --subme 3 --merange 48 --weightb --max-merge 4 --early-skip --ref 3 --no-open-gop --min-keyint 5 --keyint 250 --fades --bframes 16 --b-adapt 2 --radl 3 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --tskip --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rc-lookahead 68 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --qp-adaptation-range 4 --deblock -1:0 --limit-sao --sao-non-deblock --hash 2 --allow-non-conformance --single-sei --y4m -"
$x264ParA="$encD $color_matrix $trans_chrctr $fps $WxH $encCSP --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightb --keyint 360 --min-keyint 5 --bframes 12 --b-adapt 2 --ref 3 --rc-lookahead 90 --crf 20 --qpmin 9 --chromaqp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22 --fgo 10 --y4m -"
#「初始化」x264/5变化参数, 添加--frames, debug时注释掉, 末尾不加空格, 仅单文件版可用
$x265VarA=$x264VarA="$nbrframes --output `"$fileEXP$vidEXP`""

#「生成ffmpeg, vspipe, avs2yuv, avspipemod主控批处理」
$ctrl_gen="::「兼容 UTF-8文件名」弃用ANSI文本编码格式
::「要求 变量回收」set+endlocal, 在编码bat中停止也触发清理
::utf-8文本编码, 关闭命令输入显示, 5秒倒数
chcp 65001 && @echo off && timeout 5
setlocal

::「非正常退出时」用taskkill /F /IM cmd.exe /T才能清理打开的批处理, 否则重复使用可会乱码
@echo 「Non-std exits」cleanup with `"taskkill /F /IM cmd.exe /T`" is necessary to prevent residual variable's presence from previously ran sripts.
@echo. && @echo --Starting multi-batch-enc workflow v2--

::「ffmpeg debug」删-loglevel 16
::「-thread_queue_size过小」加-thread_queue_size<压制平均码率kbps+1000>, 但最好换ffmpeg
::「ffmpeg, vspipe, avsyuv, avs2pipemod固定参数」
@set ffmpegParA="+$ffmpegParA+"
@set vspipeParA="+$vspipeParA+"
@set avsyuvParA="+$avsyuvParA+"
@set avsmodParA="+$avsmodParA+"

::「ffmpeg, vspipe, avsyuv, avs2pipemod变化参数」
@set ffmpegVarA=-hwaccel auto "+$ffmpegVarA+"
@set vspipeVarA="+$vspipeVarA+"
@set avsyuvVarA="+$avsyuvVarA+"
@set avsmodVarA="+$avsmodVarA+"

::「x264-5固定参数」
@set x265ParA="+$x265ParA+"
@set x264ParA="+$x264ParA+"

::「x264-5变化参数」测试时注释掉. 因莫名其妙的错误, 这段话必须和下面命令隔一行

@set x265VarA="+$x265VarA+"
@set x264VarA="+$x264VarA+"

::「debug与测试」平时注释掉, 末尾不加空格

::@set x265VarA=`"--crf 22 $x265VarA`"
::@set x265VarB=`"--crf 23 $x265VarA`"
::@set x264VarA=`"--crf 22 $x264VarA`"
::@set x264VarA=`"--crf 23 $x264VarA`"

::「编码部分」用注释或删除编码批处理跳过不需要的编码

call enc_0S.bat

::「最后」保留命令输入行, 用/k而非-k可略过输出Windows build号
endlocal
cmd -k"

if ($IMPchk -eq "a") {$exptPath+="4A.S.「编码主控」.bat"
} elseif ($IMPchk -eq "b") {$exptPath+="4B.S.「编码主控」.bat"
} elseif ($IMPchk -eq "c") {$exptPath+="4C.S.「编码主控」.bat"
} elseif ($IMPchk -eq "d") {$exptPath+="4D.S.「编码主控」.bat"}

Write-Output "`r`n正在生成 $exptPath"
[System.IO.File]::WriteAllLines($exptPath, $ctrl_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码
Write-Output 完成
pause