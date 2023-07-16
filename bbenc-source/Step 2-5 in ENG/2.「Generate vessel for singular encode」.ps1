cls #Dev's Github: https://github.com/iAvoe
$mode="s" #Signular encoding mode
Function badinputwarning{Write-Warning "`r`n× Bad input, try again"}
Function nosuchrouteerr {Write-Error   "`r`n× No such route, try again"}
Function nonintinputerr {Write-Error   "`r`n× Input was not an integer"}
Function tmpmuxreminder {return        "x265 downstream supports .hevc output only. If you are multiplexing .mkv, then a .mp4 multiplexing is needed due to ffmpeg's restriction`r`n"}
Function modeparamerror {Write-Error   "`r`n× Crash: Variable `$mode broken, unable to distingulish operating mode"; pause; exit}
Function skip {return "`r`n. Skipped"}
Function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #Checking if input filename compliants to Windows file naming scheme, not needed in multiple encoding mode

Function whereisit($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a file
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath('DESKTOP') }#Starting path set to Desktop
    Do {$dInput = $startPath.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost=$true}))} While ($dInput -eq "Cancel") #Opens a file selection window, re-open until receive inputs, 2.Window is too small, TopMost ON
    return $startPath.FileName
}

Function whichlocation($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a folder/path/dir
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="Select a directory. Drag bottom corner to enlarge for convenience"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #Intercepting failed inputs (user presses close/cancel button) with Do-While looping
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #Opens a path selection window, TopMost off since the window is big enough
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
Write-Output "avs2pipemod [.avs] -y4mp                      | x265.exe --y4m - --output <<No `"-`" on upstream commandline>>`r`n"

#「Bootstrap A-B」Only needed in multiple encoding mode, skipped in sigular encoding mode

#「Bootstrap C」Locate path to export batch files
Read-Host "-----Welcome-----`r`nHit Enter to proceed open a selection window that locates [path for exporting batch files]..."
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
                Read-Host "Hit Enter to proceed open a window that locates [path to export temporary MP4 files]..."
                $EXPpath = whichlocation
                Write-Output "√ Selected $EXPpath`r`n"

                $vidEXP = settmpoutputname($mode) #Configure file output name for the temporary MP4

            }b{ $MUXhevc="b"
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

$tmpStrmOut=$vidEXP+".hevc" #Path, filename & extension of temporary .hevc stream output (Stream Output - export stream to MUXwrt commandline)
$tempMuxOut=$vidEXP+".mp4"  #Path, filename & extension of temporary MP4 file multiplexed (This get commented out when Switch above is not A)

#single-encode mode's temporary MP4 multiplex ffmpeg options, under x264, x265 routing. $MUXwrt was initialized as "" above
#single-encode mode doesn't have variable $sChar
if     ($ENCops -eq "a") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA% %x265VarA%"}
elseif ($ENCops -eq "b") {$ENCwrt="$impEXT %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA% %x264VarA%"}
else                     {Write-Error "× Failure: missing selection of video encoding program"; pause; exit}

#Manually change `$MUXops specified on top, C is auto-selected under x264 downstream
if ($MUXops -eq "a") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$tempMuxOut`"
::del `"$EXPpath$tmpStrmOut`""
} elseif ($MUXops -eq "b") {$MUXwrt="$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$tempMuxOut`"
del `"$EXPpath$tmpStrmOut`""
} elseif ($MUXops -eq "c") {$MUXwrt="::$impEXT %ffmpegVarA% %ffmpegParB% `"$EXPpath$tempMuxOut`"
::del `"$EXPpath$tmpStrmOut`""
} else {
    Write-Error "`r`n× Script broken: bad `$MUXops value [A|B|C], please correct manually"; pause; exit
}

#[string]$banner=[string]$cVO=[string]$fVO=[string]$xVO=[string]$aVO=""
[string]$trueExpPath="" #trueExpPath is the actual variable used to export temporary MP4s, to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a "+"

#export batch file w/ utf-8NoBOM text codec
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false 
Write-Output "`r`n... Generating enc_0S.bat`r`n"
$enc_gen="REM 「Title」
@echo.
@echo -------------Starting encode--------------

REM 「Debug」Comment out during normal usage
REM @echo %ffmpegParA% %ffmpegVarA%
REM @echo %vspipeParA% %vspipeVarA%
REM @echo %avsyuvParA% %avsyuvVarA%
REM @echo %avsmodParA% %avsmodVarA%
REM @echo %olsargParA% %olsargVarA%
REM @echo %x265ParA% %x265VarA%
REM @echo %x264ParA% %x264VarA%
REM pause

REM 「Encode」Comment out during debugging
REM Var is used to specify dynamic values such as input-output and tuned-by-source options

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

Write-Output "Completed, as long as up-downstream remains the same, any controller batch generated by step 3 could always use enc_0S.bat / enc_X.bat"
pause