cls #开发人员的Github: https://github.com/iAvoe
$mode="s" #单任务模式

Function badinputwarning {Write-Warning "`r`n× 输入错误, 重试"}
Function nosuchrouteerr  {Write-Error "`r`b× 该线路不存在, 重试"}
Function tmpmuxreminder {Write-Warning "x265线路下仅支持生成.hevc文件，若要封装为.mkv, 则受ffmpeg限制需要先封装为.mp4`r`n"}
Function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #检测文件名是否符合Windows命名规则，大批量版不需要

Function whereisit($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件的GUI交互窗，通过SelectedPath将GUI交互窗锁定到桌面文件夹, 效果一般
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #打开选择文件的GUI交互窗, 通过重新打开选择窗来反取消用户的取消操作
    return $startPath.FileName
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="选择路径用的窗口. 拖拽边角可放大以便操作"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #打开选择文件的GUI交互窗, 用Do-While循环拦截误操作（取消/关闭选择窗）
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") 
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    if (($startPath.SelectedPath.SubString($startPath.SelectedPath.Length-1) -eq "\") -eq $false) {$startPath.SelectedPath+="\"}
    return $startPath.SelectedPath
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
Write-Output "ffmpeg -i [源] -an -f yuv4mpegpipe -strict unofficial - | x265.exe - --y4m --output`r`n"
Write-Output "ffmpeg 缩放滤镜: -sws_flags <bicubic bitexact gauss bicublin lanczos spline><+full_chroma_int +full_chroma_inp +accurate_rnd>"
Write-Output "ffmpeg .ass渲染: -filter_complex `"ass=`'F\:/字幕.ass`'`""
Write-Output "ffmpeg可变转恒定帧率: -vsync cfr`r`n"
Write-Output "压制分场隔行视频 - x265: --tff/--bff; - x264: --interlaced<tff/bff>`r`n"
Write-Output "VSpipe      [.vpy] --y4m               - | x265.exe --y4m - --output"
Write-Output "avs2yuv     [.avs] -csp<串> -depth<整> - | x265.exe --input-res <串> --fps <整/小/分数> - --output"
Write-Output "avs2pipemod [.avs] -y4mp                 | x265.exe --y4m - --output <<上游无`"-`">>`r`n"
Write-Output "x265线路下，可手动在脚本中更改`$MUXops=[`r`n| a: 压制后封装(x265线路下默认)`r`n| b: 压制后封装并删除未封装流`r`n| c: 仅压制(封装命令注释掉，x264线路时自动选择)]`r`n"
$MUXops="a"

#「启动A」生成1~n个"enc_[序号].bat"单文件版不需要
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #从0而非1开始数
    Do {[int]$qty = (Read-Host -Prompt "指定[生成压制批处理]的整数数量, 从1开始数, 最大为15625次编码")
        if ($qty -eq 0) {"输入了非整数或空值"} elseif ($qty -gt 15625) {Write-Error "× 编码次数超过15625"; pause; exit}
    } While ($qty -eq 0)
    #「启动B」选择是否在导出文件序号上补零, 由于int变量$qty得不到字长Length, 所以先转string再取值
    if ($qty -gt 9) {#个位数下关闭补零
        Do {[string]$leadCHK=""; [int]$ldZeros=0
            Switch (Read-Host "选择之前[y启用了 | n关闭了]导出压制文件名的[序号补0]. 如导出十位数文件时写作01, 02...") {
                y {$leadCHK="y"; Write-Output "√ 启用补零`r`n"; $ldZeros=$qty.ToString().Length}
                n {$leadCHK="n"; Write-Output "× 关闭补零`r`n"}
                default {badinputwarning}
            }
        } While ($leadCHK -eq "")
        [string]$zroStr="0"*$ldZeros #得到.ToString('000')所需的'000'部分, 如果关闭补零则$zroStr为0, 补零计算仍然存在但没有效果
    } else {[string]$zroStr="0"}
}
#「启动C」定位导出主控文件用路径, 需要区分单任务和大批量模式
Read-Host "将打开[导出主控批处理]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
if     ($mode="s") {$bchExpPath = (whichlocation)+"enc_0S.bat"}
elseif ($mode="m") {$bchExpPath = (whichlocation)+"enc_$s.bat"; $s=0} #大批量模式下, `$s会在代码中后段被赋值, 提前赋值以防崩溃
else               {Write-Error "`r`n× 崩溃: 变量`$mode损坏, 无法区分单任务和大批量模式"; pause; exit}
Write-Output "√ 选择的路径与文件名为 $bchExpPath`r`n"

#「启动D-E1」循环选择所有pipe上游，下游程序, 同时使用y4m pipe和ffprobe两者来实现冗余/fallback. 步骤2选择上游程序, 步骤3选择片源
$impEND="n"
$fmpgPath=$vprsPath=$avsyPath=$avspPath=$svfiPath=$x265Path=$x264Path=""
Do {Do {
        Switch (Read-Host "`r`n导入上游程序路径 [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI]") {
            a {Write-Output "`r`nffmpeg------上游A线. 已打开[定位ffmpeg.exe]的选窗";            $fmpgPath=whereisit}
            b {Write-Output "`r`nvspipe------上游B线. 已打开[定位vspipe.exe]的选窗";            $vprsPath=whereisit}
            c {Write-Output "`r`navs2yuv-----上游C线. 已打开[定位avs2yuv.avs]的选窗";           $avsyPath=whereisit}
            d {Write-Output "`r`navs2pipemod-上游D线. 已打开[定位avs2pipemod.exe]的选窗";       $avspPath=whereisit}
            e {Write-Output "`r`nsvfi--------上游E线. 已打开[定位one_line_shot_args.exe]的选窗";$svfiPath=whereisit}
            default {badinputwarning}
        }
    } While ($fmpgPath+$vprsPath+$avsyPath+$avspPath+$svfiPath -eq "")
    Do {
        Switch (Read-Host "`r`n导入下游程序路径 [A: x265/hevc | B: x264/avc]") {
            a {Write-Output "`r`nx265--------下游A线. 已打开[定位x265.exe]的选窗";              $x265Path=whereisit}
            b {Write-Output "`r`nx264--------下游B线. 已打开[定位x264.exe]的选窗";              $x264Path=whereisit}
            default {badinputwarning}
        }
    } While ($x265Path+$x264Path -eq "")
    if ((Read-Host "`r`n√ 按Enter导入更多线路(推荐)或更换导入的程序, 输入y再Enter以进行下一步") -eq "y") {$impEND="y"} else {$impEND="n"}
    $impEND #用户选择是否完成导入操作并退出
} While ($impEND -eq "n")

#「启动F1」调用impOPS, extOPS生成被选中线路的命令行
$keyRoute=""
Switch ($impOps+$extOPS) {
    aa {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA% %x265VarA%"} #ffmpeg+x265
    ab {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA% %x264VarA%"} #ffmpeg+x264
    ba {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x265Path %x265ParA% %x265VarA%"} #VSPipe+x265
    bb {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x264Path %x264ParA% %x264VarA%"} #VSPipe+x264
    ca {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x265Path %x265ParA% %x265VarA%"} #AVSYUV+x265
    cb {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x264Path %x264ParA% %x264VarA%"} #AVSYUV+x264
    da {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x265Path %x265ParA% %x265VarA%"} #AVSPmd+x265, 上游无"-"
    db {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x264Path %x264ParA% %x264VarA%"} #AVSPmd+x264, 上游无"-"
    ea {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x265Path %x265ParA% %x265VarA%"} #OLSARG+x265
    eb {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x264Path %x264ParA% %x264VarA%"} #OLSARG+x264
}

#「启动F2」选择上下游线路, 通过impOPS, extOPS来判断注释掉剩余未选择的路线
Write-Output "`r`n√↑A=`"$fmpgPath`",↑B=`"$vprsPath`",↑C=`"$avsyPath`",`r`n  ↑D=`"$avspPath`",↑E=`"$svfiPath`"`r`n√↓A=`"$x265Path`", ↓B=`"$x264Path`""
$impOPS=$extOPS=""
Do {Switch (Read-Host "`r`n选择启用一条pipe上游线路 [A | B | C | D | E], 剩余线路会通过注释遮蔽掉") {
            a {if ($fmpgPath -ne "") {Write-Output "`r`nffmpeg------上游A线."; $impOPS="a"} else {nosuchrouteerr}}
            b {if ($vprsPath -ne "") {Write-Output "`r`nvspipe------上游B线."; $impOPS="b"} else {nosuchrouteerr}}
            c {if ($avsyPath -ne "") {Write-Output "`r`navs2yuv-----上游C线."; $impOPS="c"} else {nosuchrouteerr}}
            d {if ($avspPath -ne "") {Write-Output "`r`navs2pipemod-上游D线."; $impOPS="d"} else {nosuchrouteerr}}
            e {if ($svfiPath -ne "") {Write-Output "`r`nsvfi--------上游E线."; $impOPS="e"} else {nosuchrouteerr}}
            default {badinputwarning}
    }
    if ($impOPS -ne "") {#未选择上游时, 通过if跳过本段代码回到选择上游的部分
        Switch (Read-Host "`r`n选择启用一条pipe下游线路 [A | B], 剩余线路会通过注释遮蔽掉") {
            a {if ($x265Path -ne "") {Write-Output "`r`nx265--------下游A线."; $extOPS="a"} else {nosuchrouteerr}}
            b {if ($x264Path -ne "") {Write-Output "`r`nx264-------下游B线.";  $extOPS="b"} else {nosuchrouteerr}}
            default {badinputwarning}
        }
    }
} While (($impOPS -eq "") -or ($extOPS -eq ""))

#「启动E3」将已知可用的上下游线路列举并进行排列组合
[array]$upPipeStr=@("$fmpgPath %ffmpegVarA% %ffmpegParA%", "$vprsPath %vspipeVarA% %vspipeParA%", "$avsyPath %avsyuvVarA% %avsyuvParA%", "$avspPath %avsmodVarA% %avsmodParA%","$svfiPath %olsargVarA% %olsargParA%") | Where-Object {$_.Length -gt 26}
[array]$dnPipeStr=@("$x265Path %x265ParA% %x265VarA%", "$x264Path %x264ParA% %x264VarA%") | Where-Object {$_.Length -gt 25} #用字长过滤掉不存在的线路
[array]$altRoute=@() #注释符 + `$updnPipeStr值 = 备选线路
#          生成所有的备选线路命令行
for     ($x=0; $x -lt ($upPipeStr.Length); $x++) {#上游/横向可能性的循环迭代
    for ($y=0; $y -lt ($dnPipeStr.Length); $y++) {#下游/纵向可能性的循环迭代
        if ($upPipeStr -notlike "avsmod") {$altRoute="REM"+$upPipeStr[$x]+" - | "+$dnPipeStr[$y]} #AVSPmd, 上游无"-"
        else                              {$altRoute="REM"+$upPipeStr[$x]+"   | "+$dnPipeStr[$y]} #AVSPmd, 上游无"-"
    }
}
Write-Output "`r`n√ 可用线路数量为:"($updnPipeStr.Count)" `r`n" #此时已得出主选线路`$keyRoute和备选线路`$altRoute

if ($extOPS="a") {tmpmuxreminder} #选择x265下游时, 给出只能间接封装为.mkv的警告

#单任务封装模式下的文件输出功能
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #导出utf-8NoBOM文本编码hack
Write-Output "`r`n... 正在生成enc_0S.bat`r`n"
$enc_gen="REM 「标题」
@echo.
@echo -----------Starting encode 001-----------

REM 「debug部分」正常使用时注释掉
REM @echo %ffmpegParA%
REM @echo %ffmpegVarA%
REM @echo %vspipeParA%
REM @echo %vspipeVarA%
REM @echo %avsyuvParA%
REM @echo %avsyuvVarA%
REM @echo %avsmodParA%
REM @echo %avsmodVarA%
REM @echo %olsargParA%
REM @echo %olsargVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「压制-主要线路」debug时注释掉
REM Var被用于引用动态数据，如输入输出路径和根据源视频自动调整的部分参数值

"+$keyRoute+"

REM 「压制-备选线路」下方除REM注释外的命令复制并覆盖掉上方命令以更换主要线路

"+$altRoute+"

REM 「选择续y/暂n/止z」5秒后自动y, 除外字符被choice命令屏蔽, 暂停代表仍可继续.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

#Out-File -InputObject $enc_gen -FilePath $bchExpPath -Encoding utf8
[IO.File]::WriteAllLines($bchExpPath, $enc_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码

Write-Output "完成，只要线路不变，步骤3生成的各种批处理（步骤4）就可以一直调用enc_0S.bat / enc_X.bat"
pause