cls #Dev's Github: https://github.com/iAvoe
$mode="s"
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

#「Bootstrap A」Generate 1~n amount of "enc_[numbers].bat". Not needed in singular encode mode
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #Start counting from 0 instead of 1
    Do {[int]$qty = (Read-Host -Prompt "Specify the integer amount of [individual encoding batches] to generate. Range from 1~15625")
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
Read-Host "-----Welcome-----`r`nHit Enter to proceed open a selection window that locates [path for exporting batch files]...`r`nThis selection window might pop up at rear of current PowerShell instance."
$exptPath = whichlocation
Write-Output "√ Selected $exptPath`r`n"

#「Bootstrap D」Choose upstream program of file pipe, y4m pipe & ffprobe analysis were both used for info-gathering fallback. Only Step 3 chooses video file to import
Do {$IMPchk=$fmpgPath=$vprsPath=$avsyPath=$avspPath=$svfiPath=""
    Switch (Read-Host "Choose an upstream pipe program [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI]") {
        a {$IMPchk="a"; Write-Output "`r`nChoosing ffmpeg------route A. Opening a selection window to [locate ffmpeg.exe]"; $fmpgPath=whereisit}
        b {$IMPchk="b"; Write-Output "`r`nChoosing vspipe------route B. Opening a selection window to [locate vspipe.exe]"; $vprsPath=whereisit}
        c {$IMPchk="c"; Write-Output "`r`nChoosing avs2yuv-----route C. Opening a selection window to [locate avs2yuv.avs]"; $avsyPath=whereisit}
        d {$IMPchk="d"; Write-Output "`r`nChoosing avs2pipemod-route D. Opening a selection window to [locate avs2pipemod.exe]"; $avspPath=whereisit}
        e {$IMPchk="e"; Write-Output "`r`nChoosing svfi--------route E. Opening a selection window to [locate one_line_shot_args.exe]`r`ni.e. under Steam distro: X:\SteamLibrary\steamapps\common\SVFI\one_line_shot_args.exe"; $svfiPath=whereisit}
        default {Write-Output "Bad input, try again"}
    }
} While ($IMPchk -eq "")
$impEXT=$fmpgPath+$vprsPath+$avsyPath+$avspPath+$svfiPath
Write-Output "`r`n√ Selected $impEXT`r`n"

#「Bootstrap E」Choose downstream program of file pipe, x264 or x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "Choose a downstream pipe program [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`nSelecting x265--route A. Opening a selection window to [locate x265.exe]"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`nSelecting x264--route B. Opening a selection window to [locate x264.exe]"; $x264Path=whereisit}
        default {Write-Output "Bad input, try again"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "`r`n√ Selected $encEXT`r`n"

[string]$MUXwrt=[string]$tempGen=[string]$sChar=""

#「Bootstrap F」Locate path to export temporary multiplexed MP4 files for x265. x264 usually has libav & therefore filtered by $ENCops. Only Step 3 locates the path to export encoded files
$MUXops="b"
[string]$vidEXP=[string]$serial=""
if ($ENCops -eq "a") {
    Read-Host "Hit Enter to proceed open a window that locates [path to export temporary MP4 files] (may pop up at rear of current window)`r`nThis is a workaround for ffmpeg denies multiplexing straight from hevc/avc to MKV."
    $fileEXP = whichlocation 
    Write-Output "√ 选择的路径为 $fileEXP`r`n"

    Do {Switch (Read-Host "Choose [A: Copy from a file | B: Input] as the temporary MP4's filename") {
            a { Write-Output "Opening a selection window to [get filename from a file]"
                $vidEXP=whereisit
                $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
                if ($mode -eq "m") {$vidEXP+='_$serial'} #!Using single quotes to prevent variable expansion of $serial
                Write-Output "`r`nIn multi-encode mode, choosing A will add a trailing counter in filename`r`n"
            }
            b { if ($mode -eq "m") {#Multi-encoding mode
                    Do {$vidEXP=Read-Host "`r`nSpecify the filename without extension. Under multi-encode mode, specify episode counter `$serial in desired location`r`n`$serial should be padded from trailing alphabets.`r`nSpace is needed inbetween 2 square brackets e.g., [YYDM-11FANS] [Yuru Yuri 2]`$serial[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "Missing variable `$serial under multi-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false))
                }
                if ($mode -eq "s") {#Single-encoding mode
                    Do {$vidEXP=Read-Host "`r`nSpecify the filename without extension`r`nSpace is needed inbetween 2 square brackets e.g., [YYDM-11FANS] [Yuru Yuri 2]01[BDRIP 720P]"
                        $chkme=namecheck($vidEXP)
                        if  (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "Detecting variable `$serial in single-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                    } While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false))
                }
                #[string]$serial=($s).ToString($zroStr) #Example of parsing leading zeros to $serial. Used in for loop below (supplies variable $s)
                #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #Activating $serial as a variable with expand string method. Used in for loop below
            }
            default {Write-Output "Bad input, try again`r`n"}
        }
    } While ($vidEXP -eq "")
    Write-Output "√ Added exporting filename $vidEXP`r`n"
    Write-Output "Manually edit option `$MUXops=[`r`n| a: Write command to export temp-MP4 files (default)`r`n| b: write <A>, but comment it out`r`n| c: write <A> & delete source file after multiplex]`r`n"
    $MUXops="a"
} #Closing if statement from $ENCops

$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #export batch file w/ utf-8NoBOM text codec
$tempEncOut=$vidEXP+".hevc" #Here is the difference from multi-encode mode
$tempMuxOut=$vidEXP+".mp4"

#single-encode mode's temporary MP4 multiplex ffmpeg options, under x264, x265 routing. $MUXwrt was initialized as "" above
#single-encode mode doesn't have variable $sChar
if ($ENCops -eq "a") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA% %x265VarA%"}
elseif ($ENCops -eq "b") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA% %x264VarA%"}
else {Write-Error "× Failure: missing selection of video encoding program"; pause; exit}

if ($MUXops -eq "a") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
::del `"$fileEXP$tempEncOut`""}
elseif ($MUXops -eq "b") {$MUXwrt="::$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
::del `"$fileEXP$tempEncOut`""}
elseif ($MUXops -eq "c") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$fileEXP$tempMuxOut`"
del `"$fileEXP$tempEncOut`""}

#[string]$banner=[string]$cVO=[string]$fVO=[string]$xVO=[string]$aVO=""
[string]$trueExpPath="" #trueExpPath is the actual variable used to export temporary MP4s, to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a "+"

Switch ($IMPchk) { a {

    Write-Output "  Generating enc_0S.bat"

    $enc_gen="REM 「Title」

@echo.
@echo -----------Starting encode 001-----------

REM 「Debug」Comment out during normal usage
REM @echo %ffmpegParA%
REM @echo %ffmpegVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「Encode」Comment out during debugging

"+$ENCwrt+"

REM 「Temp-MP4-mux」Works with x265 (downstream of pipe)

"+$MUXwrt+"

REM Choose「y:Continue/n:Pause/z:END」Continuing after 5s sleep, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #Another variable assignment is needed to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a +
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec

} b {
    
    Write-Output "  Generating enc_0S.bat"
    
    $enc_gen="REM 「Title」

@echo.
@echo -----------Starting encode 001-----------

REM 「Debug」Comment out during normal usage
REM @echo %vspipeParA%
REM @echo %vspipeVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「Encode」Comment out during debugging

"+$ENCwrt+"

REM 「Temp-MP4-mux」Works with x265 (downstream of pipe)

"+$MUXwrt+"

REM Choose「y:Continue/n:Pause/z:END」Continuing after 5s sleep, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #Another variable assignment is needed to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a +
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec

} c {

    Write-Output "`r`nGenerating enc_0S.bat"
    
    $enc_gen="REM 「Title」

@echo.
@echo -----------Starting encode 001-----------

REM 「Debug」Comment out during normal usage
REM @echo %avsyuvParA%
REM @echo %avsyuvVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「Encode」Comment out during debugging

"+$ENCwrt+"

REM 「Temp-MP4-mux」Works with x265 (downstream of pipe)

"+$MUXwrt+"

REM Choose「y:Continue/n:Pause/z:END」Continuing after 5s sleep, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #Another variable assignment is needed to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a +
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec

} d {
    
    Write-Output "  Generating enc_0S.bat"
    
    $enc_gen="REM 「Title」

@echo.
@echo -----------Starting encode 001-----------

REM 「Debug」Comment out during normal usage
REM @echo %avsmodVarParA%
REM @echo %avsmodVarVarA%
REM @echo %x265ParA%
REM @echo %x265VarA%
REM @echo %x264ParA%
REM @echo %x264VarA%
REM pause

REM 「Encode」Comment out during debugging

"+$ENCwrt+"

REM 「Temp-MP4-mux」Works with x265 (downstream of pipe)

"+$MUXwrt+"

REM Choose「y:Continue/n:Pause/z:END」Continuing after 5s sleep, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    $trueExpPath=$exptPath+"enc_0S.bat" #Another variable assignment is needed to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a +
    #Out-File -InputObject $enc_gen -FilePath $trueExpPath -Encoding utf8
    [IO.File]::WriteAllLines($trueExpPath, $enc_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec
    }#Closing Switch selection
}#Closing Switch statement

Write-Output "Task completed"
pause