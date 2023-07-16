cls #Dev's Github: https://github.com/iAvoe
$mode="m" #Multiple encoding mode
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

#「Bootstrap A」Generate 1~n amount of "enc_[numbers].bat". Not needed in singular encode mode
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #Start counting from 0 instead of 1
    Do {[int]$qty = (Read-Host -Prompt "Specify the amount of [generated encoding batches] (1~15625)")
        if ($qty -eq 0) {nonintinputerr} elseif ($qty -gt 15625) {Write-Error "× Greater than 15625 individual encodes"}
    } While (($qty -eq 0) -or ($qty -gt 15625))
    #「Bootstrap B」Locate path to export batch files
    if ($qty -gt 9) {#Skip questionare for single digit $qtys
        Do {[string]$leadCHK=""; [int]$ldZeros=0
            Switch (Read-Host "Choose [y|n] to [add leading zeros] on exporting filename's episode counter. E.g., use 01, 02... for 2-digit episodes") {
                y {$leadCHK="y"; Write-Output "√ enable leading 0s`r`n"; $ldZeros=$qty.ToString().Length}
                n {$leadCHK="n"; Write-Output "× disable leading 0s`r`n"}
                default {badinputwarning}
            }
        } While ($leadCHK -eq "")
        [string]$zroStr="0"*$ldZeros #Gaining '000' protion for ".ToString('000')" method. $zroStr would be 0 if leading zero feature is deactivated, the calculation still haves but takes no effect
    } else {[string]$zroStr="0"}
}
#「Bootstrap C」Locate path to export batch files, distingulishing single & multiple encoding mode is needed
Read-Host "`r`n[Enter] proceed open a window that locates [path for exporting batch files]..."
if     ($mode -eq "s") {$bchExpPath = (whichlocation)+"enc_0S.bat"}
elseif ($mode -eq "m") {$bchExpPath = (whichlocation)+'enc_$s.bat'} #Under multiple encding mode, using single quote on var $s 
else                   {modeparamerror}
Write-Output "`r`n√ Path & filename generated as: $bchExpPath"

#「Bootstrap D」Loop importing pipe up-downstream programs
$fmpgPath=$vprsPath=$avsyPath=$avspPath=$svfiPath=$x265Path=$x264Path=""
Do {Do {
        Switch (Read-Host "`r`nImport upstream program [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI], repeated selection will trigger a skip") {
            a {if ($fmpgPath -eq "") {Write-Output "`r`nffmpeg------up route A. Opening a window to [locate ffmpeg.exe]";            $fmpgPath=whereisit} else {skip}}
            b {if ($vprsPath -eq "") {Write-Output "`r`nvspipe------up route B. Opening a window to [locate vspipe.exe]";            $vprsPath=whereisit} else {skip}}
            c {if ($avsyPath -eq "") {Write-Output "`r`navs2yuv-----up route C. Opening a window to [locate avs2yuv.avs]";           $avsyPath=whereisit} else {skip}}
            d {if ($avspPath -eq "") {Write-Output "`r`navs2pipemod-up route D. Opening a window to [locate avs2pipemod.exe]";       $avspPath=whereisit} else {skip}}
            e {if ($svfiPath -eq "") {Write-Output "`r`nsvfi--------up route E. Opening a window to [locate one_line_shot_args.exe]";$svfiPath=whereisit} else {skip}}
            default {badinputwarning}
        }
    } While ($fmpgPath+$vprsPath+$avsyPath+$avspPath+$svfiPath -eq "")
    Do {
        Switch (Read-Host "`r`nImport downstream program [A: x265/hevc | B: x264/avc], repeated selection will trigger a skip") {
            a {if ($x265Path -eq "") {Write-Output "`r`nx265--------down route A. Opening a window to [locate x265.exe]";            $x265Path=whereisit} else {skip}}
            b {if ($x264Path -eq "") {Write-Output "`r`nx264--------down route B. Opening a window to [locate x264.exe]";            $x264Path=whereisit} else {skip}}
            default {badinputwarning}
        }
    } While ($x265Path+$x264Path -eq "")
    if ((Read-Host "`r`n√ [Enter] import more routes (recommneded); Or [y][Enter] to move on") -eq "y") {$impEND="y"} else {$impEND="n"} #User decides when to exit loop
} While ($impEND -eq "n")
#Generate a datatable to indicate imported programs
$updnTbl = New-Object System.Data.DataTable
$availRts= [System.Data.DataColumn]::new("Routes")
$upColumn= [System.Data.DataColumn]::new("UNIX Pipe Upstream")
$dnColumn= [System.Data.DataColumn]::new("UNIX Pipe Dnstream")
$updnTbl.Columns.Add($availRts); $updnTbl.Columns.Add($upColumn); $updnTbl.Columns.Add($dnColumn)
[void]$updnTbl.Rows.Add(" A:",$fmpgPath,$x265Path); [void]$updnTbl.Rows.Add(" B:",$vprsPath,$x264Path)
[void]$updnTbl.Rows.Add(" C:",$avsyPath,""); [void]$updnTbl.Rows.Add(" D:",$avspPath,""); [void]$updnTbl.Rows.Add(" E:",$svfiPath,"")
($updnTbl | Out-String).Trim() #1. Trim used to trim out empty rows, 2. Piping to Out-String to force $updnTbl to return the result before Read-Host below gets executed

Read-Host "`r`nCheck whether the correct programs are imported and [Enter] to proceed, restart otherwise"

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
                Read-Host "[Enter] proceed open a window that locates [path to export temporary MP4 files]..."
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

    $trueExpPath="" #trueExpPath is the actual variable used to export temporary MP4s, to not write "+"s into exporting files, as $exptPath cannot be connecting to enc_ without a "+"

    $banner = "-----------Starting encode "+$sChar+"-----------"
    Write-Output "  Generating enc_$s.bat (Upstream $impEXT)"

    $enc_gen="REM 「Title」
@echo.
@echo "+$banner+"
REM 「Debug」Comment out during normal usage
REM @echo %ffmpegParA% %ffmpegVarA%
REM @echo %ffmpegVar"+$sChar+"%
REM @echo %vspipeParA% %vspipeVarA%
REM @echo %vspipeVar"+$sChar+"%
REM @echo %avsyuvParA% %avsyuvVarA%
REM @echo %avsyuvVar"+$sChar+"%
REM @echo %avsmodParA% %avsmodVarA%
REM @echo %avsmodVar"+$sChar+"%
REM @echo %olsargParA% %olsargVarA%
REM @echo %olsargVar"+$sChar+"%
REM @echo %x265ParA% %x265VarA%
REM @echo %x265Var"+$sChar+"%
REM @echo %x264ParA% %x264VarA%
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