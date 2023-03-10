cls #开发人员的Github: https://github.com/iAvoe
$mode="s"
Function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #检测文件名是否符合Windows命名规则, 大批量版不需要

Function whereisit($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件的GUI交互窗
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName} #打开选择文件的GUI交互窗, 用if拦截误操作
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗, 通过SelectedPath将GUI交互窗锁定到桌面文件夹, 效果一般
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="选择路径用的窗口. 拖拽边角可放大以便操作"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #打开选择文件的GUI交互窗, 用if拦截误操作
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}
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

Set-PSDebug -Strict
Write-Output "ffmpeg -i [源] -an -f yuv4mpegpipe -strict unofficial - | x265.exe - --y4m --output`r`n"
Write-Output "ffmpeg 缩放滤镜: -sws_flags <bicubic bitexact gauss bicublin lanczos spline><+full_chroma_int +full_chroma_inp +accurate_rnd>"
Write-Output "ffmpeg .ass渲染: -filter_complex `"ass=`'F\:/字幕.ass`'`""
Write-Output "ffmpeg可变转恒定帧率: -vsync cfr`r`n"
Write-Output "压制分场隔行视频 - x265: --tff/--bff; - x264: --interlaced<tff/bff>`r`n"
Write-Output "VSpipe      [.vpy] --y4m               - | x265.exe --y4m - --output"
Write-Output "avs2yuv     [.avs] -csp<串> -depth<整> - | x265.exe --input-res <串> --fps <整/小/分数> - --output"
Write-Output "avs2pipemod [.avs] -y4mp                 | x265.exe --y4m - --output`r`n"

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
                default {Write-Warning "输入错误, 重试"}
            }
        } While ($leadCHK -eq "")
        [string]$zroStr="0"*$ldZeros #得到.ToString('000')所需的'000'部分, 如果关闭补零则$zroStr为0, 补零计算仍然存在但没有效果
    } else {[string]$zroStr="0"}
}
#「启动C」定位导出主控文件用路径
Read-Host "将打开[导出主控批处理]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$exptPath = whichlocation
Write-Output "√ 选择的路径为 $exptPath`r`n"

#「启动D」选择pipe上游程序, 同时使用y4m pipe和ffprobe两者来实现冗余/fallback. 步骤2选择上游程序, 步骤3选择片源
Do {$IMPchk=$fmpgPath=$vprsPath=$avsyPath=$avspPath=$svfiPath=""
    Switch (Read-Host "选择pipe上游程序 [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI]") {
        a {$IMPchk="a"; Write-Output "`r`n选择了ffmpeg----A线路. 已打开[定位ffmpeg.exe]的选窗"; $fmpgPath=whereisit}
        b {$IMPchk="b"; Write-Output "`r`n选择了vspipe----B线路. 已打开[定位vspipe.exe]的选窗"; $vprsPath=whereisit}
        c {$IMPchk="c"; Write-Output "`r`n选择了avs2yuv---C线路. 已打开[定位avs2yuv.avs]的选窗"; $avsyPath=whereisit}
        d {$IMPchk="d"; Write-Output "`r`n选了avs2pipemod-D线路. 已打开[定位avs2pipemod.exe]的选窗"; $avspPath=whereisit}
        e {$IMPchk="e"; Write-Output "`r`n选了svfi--------E线路. 已打开[定位one_line_shot_args.exe]的选窗`r`nSteam发布端的路径如 X:\SteamLibrary\steamapps\common\SVFI\one_line_shot_args.exe"; $svfiPath=whereisit}
        default {Write-Output "输入错误, 重试"}
    }
} While ($IMPchk -eq "")
$impEXT=$fmpgPath+$vprsPath+$avsyPath+$avspPath+$svfiPath
Write-Output "√ 选择了 $impEXT`r`n"

#「启动E」选择pipe下游程序, x264或x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "选择pipe下游程序 [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`n选择了x265--A线路. 已打开[定位x265.exe]的选窗"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`n选择了x264--B线路. 已打开[定位x264.exe]的选窗"; $x264Path=whereisit}
        default {Write-Output "输入错误, 重试"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "√ 选择了 $encEXT`r`n"

[string]$MUXwrt=[string]$tempGen=[string]$sChar=""

#「启动F」定位导出临时MP4封装的路径, x264有libav所以用$ENCops排除并直接导出MP4. 步骤3才会定义导出压制文件路径
$MUXops="b"
[string]$vidEXP=[string]$serial=""
if ($ENCops -eq "a") {
    Read-Host "将打开[导出临时封装文件]的路径选择窗, 因为ffmpeg禁止封装hevc/avc流到MKV. 可能会在窗口底层弹出. 按Enter继续"
    $fileEXP = whichlocation 
    Write-Output "√ 选择的路径为 $fileEXP`r`n"

    Do {Switch (Read-Host "选择导出临时封装的文件名[A: 从现有文件复制 | B: 手动填写]") {
            a { Write-Output "已打开[复制文件名]的选择窗"
                $vidEXP=whereisit
                $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
                if ($mode -eq "m") {$vidEXP+='_$serial'} #!使用单引号防止$serial变量被激活
                Write-Output "`r`n大批量模式下, 选项A会在末尾添加序号`r`n"
            }
            b { if ($mode -eq "m") {#大批量模式用
                    Do {$vidEXP=Read-Host "`r`n填写文件名(无后缀), 大批量模式下要求于集数变化处填 `$serial, 并隔开`$serial后的英文字母, 两个方括号间要隔开. 如[YYDM-11FANS] [Yuru Yuri 2]`$serial[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "文件名中缺少变量`$serial, 输入了空值, 或拦截了不可用字符/ | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false))
                }
                if ($mode -eq "s") {#单文件模式用
                    Do {$vidEXP=Read-Host "`r`n填写文件名(无后缀), 两个方括号间要隔开. 如 [YYDM-11FANS] [Yuru Yuri 2]01[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "单文件模式下文件名中含变量`$serial; 输入了空值; 或拦截了不可用字符/ | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false))
                }
                #[string]$serial=($s).ToString($zroStr) #赋值示例. 用于下面的for循环(提供变量$s)
                #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #下面的for循环中, 用户输入的变量只能通过Expand方法才能作为变量激活$serial
            }
            default {Write-Output "输入错误, 重试`r`n"}
        }
    } While ($vidEXP -eq "")
    Write-Output "√ 写入了导出文件名 $vidEXP`r`n"
    Write-Output "手动在脚本中更改`$MUXops=[`r`n| a: 写入临时封装为MP4的命令 | b: 写入<A>但注释掉 | c: 写入<A>, 并且删除未封装流]`r`n"
    $MUXops="a"
} #关闭ENCops的if选项

$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #导出utf-8NoBOM文本编码hack
$tempEncOut=$vidEXP+".hevc" #此处和大批量版完全不同, 对照参考失效
$tempMuxOut=$vidEXP+".mp4"

#单任务封装模式下的临时封装ffmpeg参数+x265, x264线路切换. $MUXwrt在上方已经初始化, 所以默认是""
#单任务模式下没有$sChar变量
if ($ENCops -eq "a") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA% %x265VarA%"}
elseif ($ENCops -eq "b") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA% %x264VarA%"}
else {Write-Error "× 失败: 未选择编码器"; pause; exit}

if ($MUXops -eq "a") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
::del `"$fileEXP$tempEncOut`""}
elseif ($MUXops -eq "b") {$MUXwrt="::$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
::del `"$fileEXP$tempEncOut`""}
elseif ($MUXops -eq "c") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
del `"$fileEXP$tempEncOut`""}

#[string]$banner=[string]$cVO=[string]$fVO=[string]$xVO=[string]$aVO=""
[string]$trueExpPath="" #trueExpPath即完整导出路径, 由导出路径$exptPath和文件名enc_[数字].bat组成, 同时以防加号分隔变量$exptPath和文本enc_输出到文件名

#单任务封装模式下的文件输出功能
Switch ($IMPchk) { a {

    Write-Output "  正在生成enc_0S.bat"

    $enc_gen="REM 「标题」

@echo.
@echo -----------Starting encode 001-----------

REM 「debug部分」正常使用时注释掉
REM @echo %ffmpegParA%
REM @echo %ffmpegVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「压制部分」debug时注释掉

"+$ENCwrt+"

REM 「临时封装部分」x265下游线路下启用

"+$MUXwrt+"

REM 「选择续y/暂n/止z」5秒后自动y, 除外字符被choice命令屏蔽, 暂停代表仍可继续.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #由于要用加号分隔文本和变量, 而加号会被输出到文件名中, 所以增加一道变量赋值
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码

} b {
    
    Write-Output "  正在生成enc_0S.bat"
    
    $enc_gen="REM 「标题」

@echo.
@echo -----------Starting encode 001-----------

REM 「debug部分」正常使用时注释掉
REM @echo %vspipeParA%
REM @echo %vspipeVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「压制部分」debug时注释掉

"+$ENCwrt+"

REM 「临时封装部分」x265下游线路下启用

"+$MUXwrt+"

REM 「选择续y/暂n/止z」5秒后自动y, 除外字符被choice命令屏蔽, 暂停代表仍可继续.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #由于要用加号分隔文本和变量, 而加号会被输出到文件名中, 所以增加一道变量赋值
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码

} c {

    Write-Output "`r`n正在生成enc_0S.bat"
    
    $enc_gen="REM 「标题」

@echo.
@echo -----------Starting encode 001-----------

REM 「debug部分」正常使用时注释掉
REM @echo %avsyuvParA%
REM @echo %avsyuvVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「压制部分」debug时注释掉

"+$ENCwrt+"

REM 「临时封装部分」x265下游线路下启用

"+$MUXwrt+"

REM 「选择续y/暂n/止z」5秒后自动y, 除外字符被choice命令屏蔽, 暂停代表仍可继续.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #由于要用加号分隔文本和变量, 而加号会被输出到文件名中, 所以增加一道变量赋值
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码

} d {
    
    Write-Output "  正在生成enc_0S.bat"
    
    $enc_gen="REM 「标题」

@echo.
@echo -----------Starting encode 001-----------

REM 「debug部分」正常使用时注释掉
REM @echo %avsmodVarParA%
REM @echo %avsmodVarVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「压制部分」debug时注释掉

"+$ENCwrt+"

REM 「临时封装部分」x265下游线路下启用

"+$MUXwrt+"

REM 「选择续y/暂n/止z」5秒后自动y, 除外字符被choice命令屏蔽, 暂停代表仍可继续.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #由于要用加号分隔文本和变量, 而加号会被输出到文件名中, 所以增加一道变量赋值
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码
    }#关闭Switch选项
}#关闭Switch
Write-Output 完成
pause