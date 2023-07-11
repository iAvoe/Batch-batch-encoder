cls #「启动-」大批量版生成的主控缺失文件名, 所以要提醒
Read-Host "[单任务模式]大批量模式下, 生成的主控里没有导入用的文件名, 因此需要手动逐个填写导入文件名`r`nx264一般内置lavf, x265一般不带, 不内置lavf库的编码器需要通过ffmpeg等上游pipe端工具导入视频流，输出未封装的流. 按Enter继续"
$mode="s"
Function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #检测文件名是否符合Windows命名规则

Function whereisit($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件的GUI交互窗
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #打开选择文件的GUI交互窗, 通过重新打开选择窗来反取消用户的取消操作
    return $startPath.FileName
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗, 通过SelectedPath将GUI交互窗锁定到桌面文件夹, 效果一般
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="选择路径用的窗口. 拖拽边角可放大以便操作"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #打开选择文件的GUI交互窗, 用Do-While循环拦截误操作（取消/关闭选择窗）
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") 
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    if (($startPath.SelectedPath.SubString($startPath.SelectedPath.Length-1) -eq "\") -eq $false) {$startPath.SelectedPath+="\"}
    return $startPath.SelectedPath
}

Function setencoutputname ([string]$mode, [string]$switchOPS) {
    $DebugPreference="Continue" #function里不能用Write-Output/Host,或" "来输出交互信息, 所以用Write-Debug

    Switch ($switchOPS) { #函数中不支持「Switch + Readhost " $变量名 "」，所以把原本由Switch问的问题在进入函数前就要回答，只把答案导入进函数中
        a { Write-Debug "已打开[复制文件名]的选择窗"
            $vidEXP=whereisit
            $chkme=namecheck($vidEXP)
            $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
            if ($mode -eq "m") {$vidEXP+='_$serial'} #!使用单引号防止$serial变量被激活
            Write-Debug "大批量模式下选项A会在末尾添加序号, 文件名尾会多出`"_`"`r`n"
        } b {
            if ($mode -eq "m") {#大批量模式用
                Do {$vidEXP=Read-Host "`r`n填写文件名(无后缀), 大批量模式下要于集数变化处填 `$serial, 并隔开`$serial后的英文字母, 两个方括号间要隔开. 如 [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)"
                    $chkme=namecheck($vidEXP)
                    if  (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "文件名中缺少变量`$serial, 输入了空值, 或拦截了不可用字符/ | \ < > : ? * `""}
                } While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false))
            }
            if ($mode -eq "s") {#单文件模式用
                Do {$vidEXP=Read-Host "`r`n填写文件名(无后缀), 两个方括号间要隔开. 如 [Zzz] Memories – 01 (BDRip 1764x972 HEVC)"
                    $chkme=namecheck($vidEXP)
                    if  (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "单文件模式下文件名中含变量`$serial; 输入了空值; 或拦截了不可用字符/ | \ < > : ? * `""}
                } While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false))
            }
            #[string]$serial=($s).ToString($zroStr) #赋值示例. 用于下面的for循环(提供变量$s)
            #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #下面的for循环中, 用户输入的变量只能通过Expand方法才能作为变量激活$serial
        } default {#相比于settmpoutputname, 此函数不存在空值输入，所以default状态下就是原始的$vidEXP文件名
            if ($mode -eq "m") {$vidEXP+='_$serial'} #!使用单引号防止$serial变量被激活
        }
    }
    Write-Debug "√ 写入了导出文件名 $vidEXP`r`n"
    return $vidEXP
}

Function hevcparwrapper {
    Param ([Parameter(Mandatory=$true)]$PICKops)
    Switch ($PICKops) {
        a {return "--tu-intra-depth 3 --tu-inter-depth 3 --limit-tu 1 --rdpenalty 1 --me umh --merange 48 --weightb--ref 3 --max-merge 3 --early-skip --no-open-gop --min-keyint 5 --fades --bframes 8 --b-adapt 2 --radl 3 --b-intra --constrained-intra --crf 21 --crqpoffs -3 --crqpoffs -1 --rdoq-level 2 --aq-mode 4 --aq-strength 0.8 --rd 3 --limit-modes --limit-refs 1 --rskip 3 --tskip-fast --rect --amp --psy-rd 1 --splitrd-skip --qp-adaptation-range 4 --limit-sao --sao-non-deblock --deblock 0:-1 --hash 2 --allow-non-conformance"} #generalPurpose
        b {return "--tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --me star --merange 48 --weightb --ref 3 --max-merge 4 --no-open-gop --min-keyint 3 --keyint 310 --fades --bframes 8 --b-adapt 2 --radl 3 --constrained-intra --b-intra --crf 21.8 --qpmin 8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --qg-size 8 --rd 3 --limit-refs 0 --rskip 0 --rect --amp --psy-rd 1.6 --deblock 0:0 --limit-sao --sao-non-deblock --selective-sao 3 --hash 2 --allow-non-conformance"} #filmCustom
        c {return "--tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --me star --merange 48 --weightb --ref 3 --max-merge 4 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --radl 3 --constrained-intra --b-intra --crf 21.8 --qpmin 8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1 --qg-size 8 --rd 3 --limit-refs 0 --rskip 0 --rect --amp --psy-rd 1 --qp-adaptation-range 3 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3 --hash 2 --allow-non-conformance"} #stockFootag
        d {return "--tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --me umh --merange 48 --weightb --max-merge 4 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --radl 3 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --tskip --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --qp-adaptation-range 4 --deblock -1:0 --limit-sao --sao-non-deblock --hash 2 --allow-non-conformance --single-sei"} #animeFansubCustom
        e {return "--tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 4 --limit-tu 1 --me star --merange 52 --analyze-src-pics --weightb --max-merge 4 --ref 3 --no-open-gop --min-keyint 1 --fades --bframes 16 --b-adapt 2 --radl 2 --b-intra --crf 17 --crqpoffs -5 --cbqpoffs -2 --ipratio 1.67 --pbratio 1.33 --cu-lossless --psy-rdoq 2.5 --rdoq-level 2 --hevc-aq --aq-strength 1.4 --qg-size 8 --rd 5 --limit-refs 0 --rskip 0 --rect --amp --no-cutree --psy-rd 1.5 --rdpenalty 2 --qp-adaptation-range 5 --deblock -2:-2 --limit-sao --sao-non-deblock --selective-sao 1 --hash 2 --allow-non-conformance"} #animeBDRipColdwar
    }
}

Function avcparwrapper {
    Param ([Parameter(Mandatory=$true)]$PICKops)
    Switch ($PICKops) {
        a {return "--me umh --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 5 --bframes 12 --b-adapt 2 --ref 3 --crf 19 --qpmin 9 --chroma-qp-offset -2 --aq-mode 3 --aq-strength 0.9 --trellis 2 --deblock0:-1 --psy-rd 0.6:1.1"} #generalPurpose
        b {return "--me umh --merange 48 --no-fast-pskip --direct auto --weightb --min-keyint 1 --bframes 12 --b-adapt 2 --ref 3 --sliced-threads --crf 17 --tune grain --trellis 2"} #stockFootage
    }
}

Function x265submecalc{ # 24fps=3, 48fps=4, 60fps=5, ++=6
    Param ([Parameter(Mandatory=$true)]$CSVfps)
    if     ((Invoke-Expression $CSVfps) -lt 25) {return "--subme 3"}
    elseif ((Invoke-Expression $CSVfps) -lt 49) {return "--subme 4"}
    elseif ((Invoke-Expression $CSVfps) -lt 61) {return "--subme 5"}
    else {return "--subme 6"}
}

Function keyintcalc{ # fps×9
    Param ([Parameter(Mandatory=$true)]$CSVfps)
    try {return "--keyint "+[math]::Round((Invoke-Expression $CSVfps)*9)} catch {return "--keyint 249"} #故意设定稀有值以同时方便debug和常用
}

Function poolscalc{
    $allprocs=Get-CimInstance Win32_Processor | Select Availability
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a Function as it would trigger a value return, modify Write-Debug instead
    [int]$procNodes=0
    ForEach ($_ in $allprocs) {if ($_.Availability -eq 3) {$procNodes+=1}} #只添加正常的处理器，否则未安装的槽也算
    if ($procNodes -gt 1) {
        if     ($procNodes -eq 2) {return "--pools +,-"}
        elseif ($procNodes -eq 4) {return "--pools +,-,-,-"}
        elseif ($procNodes -eq 6) {return "--pools +,-,-,-,-,-"}
        elseif ($procNodes -eq 8) {return "--pools +,-,-,-,-,-,-,-"}
        elseif ($procNodes -gt 8) {Write-Debug "？ 检测到安装了超过8颗处理器($procNodes), 需手动填写--pools"; return ""} #不能用else, 否则-eq 1也会被算进去
    } else {Write-Debug "√ 检测到安装了1颗处理器, 将不会填写--pools"; return ""}
}

Function framescalc{
    Param ([Parameter(Mandatory=$true)]$fcountCSV, [Parameter(Mandatory=$false)]$fcountAUX)
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a Function as it would trigger a value return, modify Write-Debug instead
    if     ($fcountCSV -match "^\d+$") {Write-Debug "√ 检测到MPEGtag视频总帧数"; return "--frames "+$fcountCSV}
    elseif ($fcountAUX -match "^\d+$") {Write-Debug "√ 检测到MKV-tag视频总帧数"; return "--frames "+$fcountAUX}
    else {return ""}
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
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #从0而非1开始数
    Do {[int]$qty = (Read-Host -Prompt "指定[之前生成压制批处理]的[整数数量]")
        if ($qty -eq 0) {"输入了非整数或空值"} elseif ($qty -gt 15625) {Write-Error "× 编码次数超过15625"; pause; exit}
    } While ($qty -eq 0)
    #「启动B」选择是否在导出文件序号上补零, 由于int变量$qty得不到字长Length, 所以先转string再取值
    if ($qty -gt 9) {#个位数下关闭补零
        Do {[string]$leadCHK=""; [int]$ldZeros=0
            Switch (Read-Host "选择之前[y启用了 | n关闭了]导出压制文件名的[序号补0]. 如导出十位数文件时写作01, 02...") {
                y {$leadCHK="y"; Write-Output "√ 启用补零`r`n"; $ldZeros=$qty.ToString().Length}
                n {$leadCHK="n"; Write-Output "× 关闭补零`r`n"}
                default {Write-Warning "`r`n× 输入错误, 重试"}
            }
        } While ($leadCHK -eq "")
        [string]$zroStr="0"*$ldZeros #得到.ToString('000')所需的'000'部分, 如果关闭补零则$zroStr为0, 补零计算仍然存在但没有效果
    } else {[string]$zroStr="0"}
}
#「启动C」定位导出主控文件用路径
Read-Host "将打开[导出主控批处理]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$exptPath = whichlocation
Write-Output "√ 选择的路径为 $exptPath`r`n"

#「启动D」定位导出压制结果用路径
Read-Host "将打开[导出压制文件]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$fileEXPpath = whichlocation
Write-Output "选择的路径为 $fileEXPpath`r`n"

#「启动E」导入原文件, 注意步骤2中已经导入了ffmpeg等工具的路径. 所以步骤3只导入源. 注意变量也为此而改了名
Write-Output "参考[视频文件类型]https://en.wikipedia.org/wiki/Video_file_format`r`n由于步骤2已填写ffmpeg, vspipe, avs2yuv, avs2pipemod的所在路径, 所以步骤3中选择的是待压制文件`r`n"
Do {$IMPchk=$vidIMP=$vpyIMP=$avsIMP=$apmIMP=""
    Switch (Read-Host "之前选择的pipe上游方案是[A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI (alpha)]") {
        a {$IMPchk="a"; Write-Output "`r`n选择了ffmpeg----视频源. 已打开[定位源]的文件选窗"; $vidIMP=whereisit}
        b {$IMPchk="b"; Write-Output "`r`n选择了vspipe----.vpy源. 已打开[定位源]的文件选窗"; $vpyIMP=whereisit}
        c {$IMPchk="c"; Write-Output "`r`n选择了avs2yuv---.avs源. 已打开[定位源]的文件选窗"; $avsIMP=whereisit}
        d {$IMPchk="d"; Write-Output "`r`n选了avs2pipemod-.avs源. 已打开[定位源]的文件选窗"; $apmIMP=whereisit}
        e {$IMPchk="e"; Write-Output "`r`n选了SVFI(alpha)-视频源. 已打开[定位源]的文件选窗"; $vidIMP=whereisit}
        default {Write-Warning "`r`n× 输入错误, 重试"}
    }
    if (($vidIMP+$vpyIMP+$avsIMP+$apmIMP).Contains(".exe")) {$IMPchk=""; Write-Error "`r`n× 该输入不是导入上游方案，而是要编码的源"}
} While ($IMPchk -eq "")

#「启动F1」整合并反馈选取的路径/文件
$impEXTs=$vidIMP+$vpyIMP+$avsIMP+$apmIMP
if ($mode -eq "m") {Write-Output "`r`n√ 选择的路径为 $impEXTm`r`n"}
if ($mode -eq "s") {Write-Output "`r`n√ 选择的文件为 $impEXTs`r`n"
    if ($impEXTs -eq "") {Write-Error "× 没有导入任何文件"; pause; exit}
    else {#「启动F2」单文件模式下生成默认导出文件名, 而需获取文件名与后缀的方法. 由于变量污染问题摒弃了Get-ChildItem
        $impEXTs=[io.path]::GetExtension($impEXTs)
        $impFNM =[io.path]::GetFileNameWithoutExtension($impEXTs)
    }
    #「启动F3」avs2yuv, avs2pipemod线路检查文件后缀名是否正常
    if (($IMPchk -eq "d") -or ($IMPchk -eq "c")) {
        if ($impEXTs -ne ".avs") {Write-Warning "文件后缀名是 $impEXTs 而非 .avs`r`n"} #if选项用于防止ffmpeg线路下输入了空值$impEXTs
    } elseif ($IMPchk -eq "b") {#「启动F4」vspipe线路检查文件后缀名是否正常
        if ($impEXTs -ne ".vpy") {Write-Warning "文件后缀名是 $impEXTs 而非 .vpy`r`n"} #大批量模式下输入的是路径所以失效
    } #注: 导入路径: $impEXTm, 导入文件: $impEXTs, 导出路径: $fileEXPpath
}
#「启动G1」Avs2pipemod需要的文件
if ($IMPchk -eq "d") {
    Read-Host "将为Avs2pipemod打开[选择avisynth.dll]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
    $apmDLL=whereisit
    $DLLchk=(Get-ChildItem $apmDLL).Extension #检查文件后缀是否为.dll并报错
    if (($DLLchk -eq ".dll") -eq $false) {Write-Warning "文件后缀名是 $apmDLL 而非 .dll `r`n"}
    Write-Output "√ 已添加avs2pipemod参数: $apmDLL`r`n"
} else {
    $apmDLL="X:\Somewhere\avisynth.dll"
    Write-Output "未选择Avs2pipemod线路, AVS动态链接库路径将临时设为 $apmDLL `r`n"
}
#「启动G2」SVFI需要的文件
if ($IMPchk -eq "e") {
    Write-Warning "本程序会自动修改渲染配置ini文件中的target_fps值, 目的是将下游x264/5编码器设置x264Par, x265Par中的--fps设置统一起来`r`n但缺点是自定义的插帧设置会失效, 若需插帧则手动修改target_fps及x264/5Par设置的--fps参数."
    Read-Host "`r`n将为SVFI打开[自定渲染配置.ini]的路径选择窗, 可能会在窗口底层弹出.`r`nSteam发布端的路径如 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini 按Enter继续"
    $olsINI=whereisit
    $INIchk=(Get-ChildItem $olsINI).Extension #检查文件后缀是否为.ini并报错
    if (($INIchk -eq ".ini") -eq $false) {Write-Warning "文件后缀名是 $olsINI 而非 .ini"}
    Write-Output "√ 已添加SVFI参数: $olsINI`r`n"
} else {
    $olsINI="X:\Somewhere\SVFI-render-customize.ini"
    Write-Output "未选择SVFI线路, 配置文件路径将临时设为 $olsINI `r`n"
}
#「启动H」四种情况下需要专门导入视频给ffprobe检测: VS(1), AVS(2), 大批量模式(1)
if (($mode -eq "m") -or (($IMPchk -ne "a") -and ($IMPchk -ne "e"))) {
    Do {$continue="n"
        Read-Host "`r`n将为ffprobe打开[送检用源视频]的文件选择窗, 因为大批量版下只会导入路径, 而单文件版下ffprobe无法检测.vpy和.avs; 按Enter继续..."
        $impEXTs=whereisit
        if ((Read-Host "[检查]输入的文件 $impEXTs 是否为视频 [Y: 确认操作 | N: 更换源]") -eq "y") {$continue="y"; Write-Output "继续"} else {Write-Output "重试"}
    } While ($continue -eq "n")
} else {$impEXTs=$vidIMP}

if ($impEXTs.Contains(".mov")) {
    $is_mov=$true;  Write-Output "√ 导入视频 $impEXTs 的封装格式为MOV`r`n"
} else {
    $is_mov=$false; Write-Output "√ 导入视频 $impEXTs 的封装格式非MOV`r`n"
}

#「启动I」定位ffprobe
Read-Host "将打开[定位ffprobe.exe]的选择窗. 按Enter继续"
$fprbPath=whereisit

#「ffprobeA2」开始检测片源, 由于mkv有给不同视频流标注多种视频总帧数的tag功能, 导致封装视频的人会错标 NUMBER_OF_FRAMES 成 NUMBER_OF_FRAMES-eng (两者分别占据csv的第24,25号), 所以同时尝试读取两者, 缺少任意一值则X位中显示另一值, 所以只检测X位
#             由于MOV封装格式下区别于MP4，MKV的stream_tags，所以全部无效
#「ffprobeB2」用CSV读取模块映射array数据, 由于源文件没有所以添加目录A~F, 由于ffprobe生成的CSV不能直接导入进变量, 并且为方便debug(Remove-Item换成Notepad), 所以创建了中间文件
#             由于stream作为标题会被写入CSV，所以自动忽略A项
#             例: $parsProbe = "D:\ffprobe.exe -i `"F:\Asset\Video\BDRip私种\[Beatrice-Raws] Anne Happy [BDRip 1920x1080 x264 FLAC]\[Beatrice-Raws] Anne Happy 01 [BDRip 1920x1080 x264 FLAC].mkv`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#             例: $parsProbe = "D:\ffprobe.exe -i `"N:\SolLevante_HDR10_r2020_ST2084_UHD_24fps_1000nit.mov`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#                 Invoke-Expression $parsProbe > "C:\temp_v_info.csv"
#                 Notepad "C:\temp_v_info.csv"
Switch ($is_mov) {
    $true {
        [String]$parsProbe = $fprbPath+" -i `"$impEXTs`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries -of csv"
        Invoke-Expression $parsProbe > "C:\temp_v_info_is_mov.csv" #由于多数Windows系统只有C盘, 所以临时生成CSV在C盘
        $ffprobeCSV = Import-Csv "C:\temp_v_info_is_mov.csv" -Header A,B,C,D,E,F,G,H,I
    }
    $false{
        [String]$parsProbe = $fprbPath+" -i `"$impEXTs`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
        Invoke-Expression $parsProbe > "C:\temp_v_info.csv"        #由于多数Windows系统只有C盘, 所以临时生成CSV在C盘
        $ffprobeCSV = Import-Csv "C:\temp_v_info.csv" -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA
    }
}
if     (Test-Path "C:\temp_v_info.csv")        {Remove-Item "C:\temp_v_info.csv"}
elseif (Test-Path "C:\temp_v_info_is_mov.csv") {Remove-Item "C:\temp_v_info_is_mov.csv"}

#「ffprobeB3」根据视频帧数自动填写x265的--subme，H=第8个$ffprobeCSV序列值
$x265subme=x265submecalc -CSVfps $ffprobeCSV.H
Write-Output "√ 已添加x265参数: $x265subme"

#「ffprobeB4」根据视频帧数自动填写x265, x264的--keyint
$keyint=keyintcalc -CSVfps $ffprobeCSV.H
Write-Output "√ 已添加x264/5参数: $keyint"

$WxH="--input-res "+$ffprobeCSV.B+"x"+$ffprobeCSV.C+""
$color_mtx="--colormatrix "+$ffprobeCSV.F
$trans_chrctr="--transfer "+$ffprobeCSV.G
if ($ffprobeCSV.F -eq "unknown") {$avc_mtx="--colormatrix undef"} else {$avc_mtx=$color_mtx}    #x264: ×--colormatrix unknown √--colormatrix undef
if ($ffprobeCSV.G -eq "unknown") {$avc_tsf="--colormatrix undef"} else {$avc_tsf=$trans_chrctr} #x264: ×--transfer unknown    √--transfer undef
$fps="--fps "+$ffprobeCSV.H
$fmpgfps="-r "+$ffprobeCSV.H
Write-Output "√ 已添加x264参数: $fps $WxH`r`n√ 已添加x265参数: $color_mtx $trans_chrctr $fps $WxH`r`n√ 已添加ffmpeg参数: $fmpgfps`r`n"

#「ffprobeC1」自动替换SVFI渲染配置文件的target_fps, 并导出新文件. 唯SVFI线路需要
if ($IMPchk -eq "e") {
    $iniEXP="C:\bbenc_svfi_targetfps_mod_"+(Get-Date).ToString('yyyy.MM.dd.hh.mm.ss')+".ini"
    $olsfps="target_fps="+$ffprobeCSV.H
    $iniCxt=Get-Content $olsINI
    $iniTgt=$iniCxt | Select-String target_fps | Select-Object -ExpandProperty Line
    $iniCxt | ForEach-Object {$_ -replace $iniTgt,$olsfps}>$iniEXP
    Write-Output "√ 已将渲染配置文件 $olsINI 的target_fps行替换为 $olsfps,`r`n√ 新的渲染配置文件已导出为 $iniEXP"
} else {$iniEXP=$olsINI}

#「ffprobeC2」ffprobe获取视频总帧数并赋值到$x264/5VarA中, 唯单文件版可用
if ($mode -eq "s")     {$nbrFrames=framescalc -fcountCSV $ffprobeCSV.I -fcountAUX $ffprobeCSV.AA}
if ($nbrFrames -ne "") {Write-Output "√ 已添加x264/5参数: $nbrFrames"}
else {Write-Warning "× 总帧数的数据被删, 将留空x264/5参数--frames, 缺点是不再显示ETA（预计完成时间）"}

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
        yuva444p10le{Write-Output "检测到源的色彩空间==[yuv444p 10bit]"; $avsCSP="-csp i444"; $avsD="-depth 10"; $encCSP="--input-csp i444"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv444p10le"}
        yuva444p12le{Write-Output "仅x265支持的色彩空间[yuv444p 12bit]"; $avsCSP="-csp i444"; $avsD="-depth 12"; $encCSP="--input-csp i444"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv444p12le"}
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

#「启动J」选择下游程序. x264或x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "选择pipe下游程序 [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`n选择了x265--A线路. 已打开[定位x265.exe]的选窗"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`n选择了x264--B线路. 已打开[定位x264.exe]的选窗"; $x264Path=whereisit}
        default {Write-Warning "`r`n× 输入错误, 重试"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "√ 选择了 $encEXT `r`n"

#「启动K1」选择导出压制结果文件名的多种方式, 集数变量$serial于下方的循环中实现序号叠加, 单文件模式不需要集数变量
$vidEXP=[io.path]::GetFileNameWithoutExtension($impEXTs)
Do {$switchOPS=""
    $switchOPS=Read-Host "`r`n选择导出压制结果的文件名`r`n[A: 选择文件并拷贝 | B: 手动填写 | C: $vidEXP]"
    if  (($switchOPS -ne "a") -and ($switchOPS -ne "b") -and ($switchOPS -ne "c")) {Write-Error "× 输入错误，重试"}
} While (($switchOPS -ne "a") -and ($switchOPS -ne "b") -and ($switchOPS -ne "c"))
    
if (($switchOPS -eq "a") -or ($switchOPS -eq "b")) {$vidEXP = setencoutputname($mode, $switchOPS)}
else {Write-Output "√ 写入了导出文件名 $vidEXP`r`n"}

#「启动K2」x264线路下，选择导出压制结果的后缀名（x265线路下默认.hevc）
if       ($ENCops -eq "b") {$vidFMT=""
    Do {Switch (Read-Host "「x264线路」选择导出压制结果的文件后缀名/格式`r`n[A: MKV | B: MP4 | C: FLV]`r`n") {
            a {$vidFMT=".mkv"} b {$vidFMT=".mp4"} c {$vidFMT=".flv"} Default {Write-Error "`r`n× 输入错误，重试"}
        }
    } While ($vidFMT -eq "")
} elseif ($ENCops -eq "a") {$vidFMT=".hevc"}

#「启动L, M」1: 根据选择x264/5来决定输出.hevc/.mp4. 2: x265下据cpu核心数量, 节点数量添加pme/pools
if ($ENCops -eq "b") {
    Do {$PICKops=$x264ParWrap=""
        Switch (Read-Host "选择x264压制参数预设 [A: 高画质高压缩 | B: 剪辑素材存档]") {
            a {$x264ParWrap=avcparwrapper -PICKops "a"; Write-Output "`r`n√ 选择了高画质高压缩预设"}
            b {$x264ParWrap=avcparwrapper -PICKops "b"; Write-Output "`r`n√ 选择了剪辑素材存档预设"}
            default {Write-Warning "`r`n× 输入错误, 重试"}
        }
    } While ($x264ParWrap -eq "")
    Write-Output "√ 已定义x264压制参数: $x264ParWrap"
}
elseif ($ENCops -eq "a") {
    $pme=$pool=""
    $procNodes=0
    [int]$cores=(wmic cpu get NumberOfCores)[2]
    if ($cores -gt 21) {$pme="--pme"; Write-Output "`r`n√ 检测到处理器核心数达22, 已添加x265参数: --pme"}

    $pools=poolscalc
    if ($pools -ne "") {Write-Output "`r`n√ 已添加x265参数: $pools"}

    Do {$PICKops=$x265ParWrap=""
        Switch (Read-Host "`r`n选择x265压制参数预设 [A: 通用-自定义 | B: 高压-录像 | C: 剪辑素材存档 | D: 高压-动漫字幕组 | E: HEDT-动漫BDRip冷战]") {
            a {$x265ParWrap=hevcparwrapper -PICKops "a"; Write-Output "`r`n√ 选择了通用-自定义预设"}
            b {$x265ParWrap=hevcparwrapper -PICKops "b"; Write-Output "`r`n√ 选择了高压-录像预设"}
            c {$x265ParWrap=hevcparwrapper -PICKops "c"; Write-Output "`r`n√ 选择了剪辑素材存档预设"}
            d {$x265ParWrap=hevcparwrapper -PICKops "d"; Write-Output "`r`n√ 选择了高压-动漫字幕组预设"}
            e {$x265ParWrap=hevcparwrapper -PICKops "e"; Write-Output "`r`n√ 选择了HEDT-动漫BDRip冷战预设"}
            default {Write-Warning "`r`n× 输入错误, 重试"}
        }
    } While ($x265ParWrap -eq "")
    Write-Output "√ 已定义x265压制参数: $x265ParWrap"
}

#「启动N」如果使用了支持Film grain optimization的x264, 则开启
#Do {$x264fgo=$FGOops=""
#    Switch (Read-Host "选择x264 [A: 是 | B: 否] 支持基于高频信号量的率失真优化策略 (--fgo参数/Film grain optimization)注: AVC标准外") {
#        a {$FGOops="A";Write-Output "`r`n修改率失真优化策略"; $x264fgo="--fgo 15"}
#        b {$FGOops="B";Write-Output "`r`n保持率失真优化策略"; $x264fgo=""}
#        default {Write-Warning "`r`n× 输入错误, 重试"}
#    }
#} While ($FGOops -eq "")

Set-PSDebug -Strict
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #导出utf-8NoBOM文本编码用

#注: 导入路径: $impEXTm, 导入文件: $impEXTs 导出路径: $fileEXPpath
#「初始化」$ffmpegPar(固定参数变量)的末尾不带空格
#「限制」$ffmpegPar-ameters不能写在输入文件命令(-i)前面, ffmpeg参数 "-hwaccel"不能写在输入文件后面. 导致了字符串重组的流程变复杂, 及更多字符串变量的参与
$ffmpegParA="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -an -f yuv4mpegpipe -strict unofficial" #步骤2已添加pipe参数"- | -", 所以此处省略
$ffmpegParB="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -c:v copy" #生成临时mp4封装来兼容ffmpeg封装mkv用
$vspipeParA="--y4m"
$avsyuvParA="$avsCSP $avsD"
$avsmodParA="`"$apmDLL`" -y4mp" #注: avs2pipemod使用"| -"而非其他工具的"- | -"pipe参数(左侧无"-"). y4mp, y4mt, y4mb代表逐行, 上场优先隔行, 下场优先隔行. 为了降低代码复杂度所以不做隔行
$olsargParA="-c `"$iniEXP`" --pipe-out" #注: svfi不支持y4m pipe格式

#「初始化」x264/5固定参数
if ($IMPchk -eq "e") {
    $x265y4m=$x264y4m=""; Write-Output "√ 由于SVFI不支持yuv for mpeg pipe格式, 所以x264, x265参数设定为使用raw pipe格式"
} else {
    $x265y4m="--y4m"
    $x264y4m="--demuxer y4m" #x264，x265的书写格式不同
}
$x265ParA="$encD $x265subme $color_mtx $trans_chrctr $fps $WxH $encCSP $pme $pools $keyint $x265ParWrap $x265y4m -"
$x264ParA="$encD $avc_mtx $avc_tsf $fps $WxH $encCSP $keyint $x264ParWrap $x264y4m -"
$x265ParA=$x265ParA -replace "  ", " " #由于某些情况下只能生成空的参数变量, 所以会导致双空格出现, 但保留也不影响运行
$x264ParA=$x264ParA -replace "  ", " "

#「初始化」ffmpeg, vspipe, avs2yuv, avs2pipemod, one_line_shot_args变化参数, 大批量版需要单独计算每个视频的文件名所以不能直接赋值
if ($mode -eq "s") {
    $ffmpegVarA=$vspipeVarA=$avsyuvVarA=$avsmodVarA=$olsargVarA="-i `"$impEXTs`"" #上游变化参数
    $x265VarA=$x264VarA="$nbrframes --output `"$fileEXPpath$vidEXP$vidFMT`"" #下游变化参数
}

#「生成ffmpeg, vspipe, avs2yuv, avspipemod主控批处理」
$ctrl_gen="
chcp 65001
REM 「兼容 UTF-8文件名」弃用ANSI文本编码格式
REM 「要求 变量回收」set+endlocal, 在编码bat中停止也触发清理
REM UTF-8文本编码, 关闭命令输入显示, 5秒倒数

@echo off
timeout 5
setlocal

REM 「非正常退出时」用taskkill /F /IM cmd.exe /T才能清理打开的批处理, 否则重复使用可会乱码

@echo 「Non-std exits」cleanup with `"taskkill /F /IM cmd.exe /T`" is necessary to prevent residual variable's presence from previously ran sripts.
@echo. && @echo --Starting multi-batch-enc workflow v2--

REM 「ffmpeg debug」删-loglevel 16
REM 「-thread_queue_size过小」加-thread_queue_size<每核心内存带宽Kbps>, 但最好换ffmpeg
REM 「ffmpeg, vspipe, avsyuv, avs2pipemod固定参数」
REM 修改为批量编码时，需要确认视频格式（如-pix_fmt，-r）不变，否则应运行步骤3另建一个主控

@set `"ffmpegParA="+$ffmpegParA+"`"
@set `"vspipeParA="+$vspipeParA+"`"
@set `"avsyuvParA="+$avsyuvParA+"`"
@set `"avsmodParA="+$avsmodParA+"`"
@set `"olsargParA="+$olsargParA+"`"

REM 「ffmpeg, vspipe, avsyuv, avs2pipemod变化参数」
REM 可以通过在对应线路增加@set `"ffmpegVarX=-i `"X:\视频2.mp4`"`"的命令来进行批量编码

@set `"ffmpegVarA=-hwaccel auto "+$ffmpegVarA+"`"
@set `"vspipeVarA="+$vspipeVarA+"`"
@set `"avsyuvVarA="+$avsyuvVarA+"`"
@set `"avsmodVarA="+$avsmodVarA+"`"
@set `"olsargVarA="+$olsargVarA+"`"

REM 「x264-5固定参数」
REM 可以通过增加@set `"x264ParX=...`"的命令来进行批量编码

@set `"x265ParA="+$x265ParA+"`"
@set `"x264ParA="+$x264ParA+"`"

REM 「x264-5变化参数」测试时注释掉

@set `"x265VarA="+$x265VarA+"`"
@set `"x264VarA="+$x264VarA+"`"

REM 「debug与测试」平时注释掉, 末尾不加空格

REM @set `"x265VarA=--crf 23 ... --output ...`"
REM @set `"x265VarB=--crf 26 ... --output ...`"
REM @set `"x264VarA=--crf 23 ... --output ...`"
REM @set `"x264VarA=--crf 26 ... --output ...`"

REM 「编码部分」用注释或删除编码批处理跳过不需要的编码
REM 可以通过在对应线路增加call enc_x.bat的命令来进行批量的编码

call enc_0S.bat

REM 「最后」保留命令输入行, 用/k而非-k可略过输出Windows build号

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