cls #Dev's Github: https://github.com/iAvoe
$mode="m" #Multiple encoding mode
Function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #Checking if input filename compliants to Windows file naming scheme

Function whereisit($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a file
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #Starting path set to Desktop
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #Opens a file selection window, un-cancel cancelled user inputs (close/cancel button) by reopening selection window again
    return $startPath.FileName
}

Function whichlocation($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a folder/path/dir
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="Select a directory. Drag bottom corner to enlarge for convenience"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #Intercepting failed inputs (user presses close/cancel button) with Do-While looping
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #Opens a path selection window
    #Root directory always have a "\" in return, whereas a folder/path/dir doesn't. Therefore an if statement is used to add "\" when needed, but comment out under single-encode mode
    if (($startPath.SelectedPath.SubString($startPath.SelectedPath.Length-1) -eq "\") -eq $false) {$startPath.SelectedPath+="\"}
    return $startPath.SelectedPath
}

Function settmpoutputname([string]$mode) {
    $DebugPreference="Continue" #Write-Output/Host does not work in a function, using Write-Debug instead

    Do {Switch (Read-Host "Choose [A: Copy from a file | B: Input] as the temporary MP4's filename") {
            a { Write-Debug "√ Opening a selection window to [get filename from a file]"
                $vidEXP=whereisit
                $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
                if ($mode -eq "m") {$vidEXP+='_$serial'} #! Using single quotes in codeline here to prevent variable `$serial from being executed
                Write-Debug "`r`nIn multi-encode mode, choosing A will add a trailing counter in filename`r`n"
            }
            b { if ($mode -eq "m") {#Multi-encoding mode
                    Do {[string]$vidEXP=Read-Host "`r`nSpecify filename w/out extension (multi-encode mode)  `r`n1. Specify episode counter `$serial in desired location`r`n2. `$serial should be padded from trailing alphabets.`r`n3. Space is needed inbetween 2 square brackets`r`n  e.g., [YYDM-11FANS] [Yuru Yuri 2]`$serial[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "Missing variable `$serial under multi-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false))
                }
                if ($mode -eq "s") {# Single encoding mode
                    Do {[string]$vidEXP=Read-Host "`r`nSpecify filename w/out extension (single encoding mode)`r`nSpace is needed inbetween 2 square brackets`r`ne.g., [YYDM-11FANS] [Yuru Yuri 2]01[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "Detecting variable `$serial in single-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false))
                }
                #[string]$serial=($s).ToString($zroStr) #Example of parsing leading zeros to $serial. Used in for loop below (supplies variable $s)
                #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #Activating $serial as a variable with expand string method. Used in for loop below
            }
            default {Write-Warning "× Bad input, try again`r`n"}
        }
    } While ($vidEXP -eq "")
    Write-Debug "√ Added exporting filename $vidEXP`r`n"
    return $vidEXP
}

#「@MrNetTek」Use high-DPI rendering, to fix blurry System.Windows.Forms
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class ProcessDPI {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetProcessDPIAware();      
}
'@
$null = [ProcessDPI]::SetProcessDPIAware()

Set-PSDebug -Strict
Write-Output "ffmpeg -i [input] -an -f yuv4mpegpipe -strict unofficial - | x265.exe - --y4m --output`r`n"
Write-Output "ffmpeg video scaling: -sws_flags <bicubic bitexact gauss bicublin lanczos spline><+full_chroma_int +full_chroma_inp +accurate_rnd>"
Write-Output "ffmpeg .ass rendring: -filter_complex `"ass=`'F\:/Subtitle.ass`'`""
Write-Output "ffmpeg convert from variable to constant framt rate: -vsync cfr`r`n"
Write-Output "Encode interlaced source with x265: --tff/--bff; x264: --interlaced<tff/bff>`r`n"
Write-Output "VSpipe      [.vpy] --y4m                    - | x265.exe --y4m - --output"
Write-Output "avs2yuv     [.avs] -csp<string> -depth<int> - | x265.exe --input-res <string> --fps <int/float/fraction> - --output"
Write-Output "avs2pipemod [.avs] -y4mp                      | x265.exe --y4m - --output`r`n"
Write-Output "Under x265 downstream, manually changing preference `$MUXops=[`r`n| a: Muxtiplex after encode (default)`r`n| b: Multiplex & delete raw hevc stream after encode`r`n| c: Encode only (comment multiplex commandline out, auto-selected under x264 downstream)]`r`n"
$MUXops="a"

#「Bootstrap A」Generate 1~n amount of "enc_[numbers].bat". Not needed in singular encode mode
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #Start counting from 0 instead of 1
    Do {[int]$qty = (Read-Host -Prompt "Specify the amount of [generated encoding batches]. Range from 1~15625")
        if ($qty -eq 0) {"Non-integer or no value was entered"} elseif ($qty -gt 15625) {Write-Error "× Greater than 15625 individual encodes"}
    } While (($qty -eq 0) -or ($qty -gt 15625))
    #「Bootstrap B」Locate path to export batch files
    if ($qty -gt 9) {#Skip questionare for single digit $qtys
        Do {[string]$leadCHK=""; [int]$ldZeros=0
            Switch (Read-Host "Choose [y|n] to [add leading zeros] on exporting filename's episode counter. E.g., use 01, 02... for 2-digit episodes") {
                y {$leadCHK="y"; Write-Output "√ enable leading 0s`r`n"; $ldZeros=$qty.ToString().Length}
                n {$leadCHK="n"; Write-Output "× disable leading 0s`r`n"}
                default {Write-Warning "Bad input, try again"}
            }
        } While ($leadCHK -eq "")
        [string]$zroStr="0"*$ldZeros #Gaining '000' protion for ".ToString('000')" method. $zroStr would be 0 if leading zero feature is deactivated, the calculation still haves but takes no effect
    } else {[string]$zroStr="0"}
}
#「Bootstrap C」Locate path to export batch files
Read-Host "`r`nHit Enter to proceed open a window that locates [path for exporting batch files]...`r`nThis selection window might pop up at rear of current PowerShell instance."
$exptPath = whichlocation
Write-Output "√ Selected $exptPath`r`n"

#「Bootstrap D」Choose upstream program of file pipe, y4m pipe & ffprobe analysis were both used for info-gathering fallback. Only Step 3 chooses video file to import
Do {$impEXT=$fmpgPath=$vprsPath=$avsyPath=$avspPath=$svfiPath=""
    Switch (Read-Host "Choose an upstream pipe program [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI]") {
        a {Write-Output "`r`nChoosing ffmpeg------route A. Opening a selection window to [locate ffmpeg.exe]";      $fmpgPath=whereisit}
        b {Write-Output "`r`nChoosing vspipe------route B. Opening a selection window to [locate vspipe.exe]";      $vprsPath=whereisit}
        c {Write-Output "`r`nChoosing avs2yuv-----route C. Opening a selection window to [locate avs2yuv.avs]";     $avsyPath=whereisit}
        d {Write-Output "`r`nChoosing avs2pipemod-route D. Opening a selection window to [locate avs2pipemod.exe]"; $avspPath=whereisit}
        e {Write-Output "`r`nChoosing svfi--------route E. Opening a selection window to [locate one_line_shot_args.exe]`r`ni.e. under Steam distro: X:\SteamLibrary\steamapps\common\SVFI\one_line_shot_args.exe"; $svfiPath=whereisit}
        default {Write-Output "Bad input, try again"}
    }
    $impEXT=$fmpgPath+$vprsPath+$avsyPath+$avspPath+$svfiPath
} While ($impEXT -eq "")
Write-Output "`r`n√ Selected $impEXT`r`n"

#「Bootstrap E」Choose downstream program of file pipe, x264 or x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "Choose a downstream pipe program [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`nSelecting x265--route A. Opening a selection window to [locate x265.exe]"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`nSelecting x264--route B. Opening a selection window to [locate x264.exe]"; $x264Path=whereisit}
        default {Write-Warning "× Bad input, try again"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "`r`n√ Selected $encEXT`r`n"

#「Bootstrap F」Locate path to export temporary multiplexed MP4 files for x265. x264 usually has libav & therefore filtered by $ENCops
#               Step 3 locates the path to export encoded files
[string]$vidEXP=[string]$serial=[string]$MUXhevc=""

if ($ENCops -eq "a") {
    Do {Switch (Read-Host "Select [ A: I'm planning to use MKV container format later (A hevc-to-MKV workaround process for ffmpeg by generating temporary MP4 files)`r`n | B: I'm not planning to use MKV format later ]") {
            a { $MUXhevc="a" #x265 downstream, consideration of whether to generate temporary MP4 is needed

                # "MUXops A/B" has been assigned on top, specified manually
                Read-Host "Hit Enter to proceed open a window that locates [path to export temporary MP4 files]...`r`nThis selection window might pop up at rear of current PowerShell instance"
                $EXPpath = whichlocation
                Write-Output "√ Selected $EXPpath`r`n"

                $vidEXP = settmpoutputname($mode) #Configure file output name for the temporary MP4

                $tempMuxOut=$vidEXP+".mp4"  #x265线路下的编码导出路径+文件名
            }b{ 
                $MUXhevc="b"
                $MUXops ="c"#Generate a commented-out multiplexing command
            }
            Default {
                Write-Warning "`r`n× Bad input, try again`r`n"
                $MUXhevc=""
            }
        }
    } While ($MUXhevc -eq "")
} elseif ($ENCops -eq "b") {#x264 downstream
    $MUXhevc="b"            #no temporary MP4 files are needed
    $MUXops="c"             #generate a commented-out multiplexing command
}

$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #export batch file w/ utf-8NoBOM text codec

$tmpStrmOut=$vidEXP+".hevc" #Path, filename & extension of temporary .hevc stream output (Stream Output - export stream to MUXwrt commandline)
$tempMuxOut=$vidEXP+".mp4"  #Path, filename & extension of temporary MP4 file multiplexed (This get commented out when Switch above is not A)

#「3 dimension axis placed in for-loop」Realized with $validChars[x]+$validChars[y]+$validChars[z]
#Simulated mathmatical carrying by: +1 to x-axis, +1 to y-axis & clear x after filling up x-axis; +1 to z-axis & clear x&y after filling up y-axis.
[int]$x=[int]$y=[int]$z=0

#Iteration begins, carry as any axis reaches letter 27. Switch occupies temp-variable $_ which cannot be used to initialize this loop. Counts as a 3-digit twenty-hexagonal
For ($s=0; $s -lt $qty; $s++) {
    #$x+=1 is commented out at beginning as values are being parsed to filenames, therefore placed at the trailing of loop
    if ($x -gt 25) {$y+=1; $x=0}
    if ($y -gt 25) {$z+=1; $y=$x=0}
    [string]$sChar=$validChars[$z]+$validChars[$y]+$validChars[$x]

    [string]$serial=($s).ToString($zroStr)
    
    $vidEXX=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #$vidEXP contains $serial. Expand is needed to convert $serial from string to variable

    $tmpStrmOut=$vidEXX+$sChar+".hevc" #multi-encode mode's temporary multiplex solution
    $tempMuxOut=$vidEXX+$sChar+".mp4"

    #Manually change `$MUXops specified on top, C is auto-selected under x264 downstream
    if       ($MUXops -eq "a") {$MUXwrt = "$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$vidEXP.hevc`"
    ::del `"$EXPpath$vidEXP.hevc`""
    } elseif ($MUXops -eq "b") {$MUXwrt = "$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$vidEXP.hevc`"
    del `"$EXPpath$vidEXP.hevc`""
    } elseif ($MUXops -eq "c") {$MUXwrt="::$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$vidEXP.hevc`"
    ::del `"$EXPpath$vidEXP.hevc`""
    } else {
        Write-Error "× Script broken: incorrect `$MUXops value"; pause; exit
    }
    
    #x265, x264 routing under multiple-encoding mode. Implemented differently from single encode mode. $MUXwrt was initialized before loops starts
    #Single encode mode doesn't have variable $sChar
    if ($ENCops -eq "a") {$ENCwrt="$impEXT %ffmpegVar$sChar% %ffmpegParA% - | $x265Path %x265ParA% %x265Var$sChar%"}
    elseif ($ENCops -eq "b") {$ENCwrt="$impEXT %ffmpegVar$sChar% %ffmpegParA% - | $x264Path %x264ParA% %x264Var$sChar%"}
    else {Write-Error "× Failure: missing selection of video encoding program"; pause; exit}

    [string]$trueExpPath=[string]$cVO=[string]$fVO=[string]$xVO=[string]$aVO="" #trueExpPath is the actual variable used to export temporary MP4s, to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a "+"

    $banner = "-----------Starting encode "+$sChar+"-----------"
    Write-Output "  Generating enc_$s.bat (Upstream $impEXT)"

    $enc_gen="REM 「Title」
@echo.
@echo "+$banner+"
REM 「Debug」Comment out during normal usage
REM @echo %ffmpegParA%
REM @echo %ffmpegVarA%
REM @echo %ffmpegVar"+$sChar+"%
REM @echo %vspipeParA%
REM @echo %vspipeVarA%
REM @echo %vspipeVar"+$sChar+"%
REM @echo %avsyuvParA%
REM @echo %avsyuvVarA%
REM @echo %avsyuvVar"+$sChar+"%
REM @echo %avsmodVarParA%
REM @echo %avsmodVarVarA%
REM @echo %avsmodVarVar"+$sChar+"%
REM @echo %olsargParA%
REM @echo %olsargVarA%
REM @echo %olsargVar"+$sChar+"%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x265Var"+$sChar+"%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM @echo %x264Var"+$sChar+"%
REM pause

REM 「Encode」Comment out during debugging
REM Var is used to specify dynamic values such as input-output and tuned-by-source options

"+$ENCwrt+"

REM 「Temp-MP4-mux」Works with x265 (pipe downstream)

"+$MUXwrt+"

REM Choose「y:Continue/n:Pause/z:END」Auto-continue after 5s, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_"+$s+".bat" #Another variable assignment is needed to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a +
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec
    $x+=1
}#Closing For-loop

Write-Output "Completed, as long as up-downstream remains the same, any controller batch generated by step 3 could always use enc_0S.bat / enc_X.bat"
pause