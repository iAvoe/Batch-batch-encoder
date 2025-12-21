cls #Dev's Github: https://github.com/iAvoe
$mode="m" #Multiple encoding mode
Function badinputwarning {Write-Warning "`r`n× Bad input, try again"}
Function nosuchrouteerr  {Write-Error   "`r`n× No such route, try again"}
Function nonintinputerr  {Write-Error   "`r`n× Input was not an integer"}
Function tmpmuxreminder  {return        "x265 downstream supports .hevc output only. If you are multiplexing .mkv, then a .mp4 multiplexing is needed due to ffmpeg's restriction`r`n"}
Function modeparamerror  {Write-Error   "`r`n× Crash: Variable `$mode broken, unable to distingulish operating mode"; pause; exit}
Function modeimpextopserr{Write-Error   "`r`n× Crash: `$mode, `$impOps or `$extOPS has an unidentifible or missing value"; pause; exit}
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
    Do {$dInput = $startPath.ShowDialog()} While ($dInput -eq "Cancel") #Opens a file selection window, re-open until receive inputs, 2.Window is big enough, TopMost OFF
    return $startPath.FileName
}

Function whichlocation($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a folder/path/dir
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="Select a directory. Drag bottom corner to enlarge for convenience"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #Intercepting failed inputs (user presses close/cancel button) with Do-While looping
    Do {$dInput = $startPath.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost=$true}))} While ($dInput -eq "Cancel") #1. Opens a path selection window. 2.Window is too small, TopMost ON
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
$upColumn= [System.Data.DataColumn]::new("\UNIX Pipe Upstream")
$dnColumn= [System.Data.DataColumn]::new("\UNIX Pipe Dnstream")
$updnTbl.Columns.Add($availRts); $updnTbl.Columns.Add($upColumn); $updnTbl.Columns.Add($dnColumn)
[void]$updnTbl.Rows.Add(" A:",$fmpgPath,$x265Path); [void]$updnTbl.Rows.Add(" B:",$vprsPath,$x264Path)
[void]$updnTbl.Rows.Add(" C:",$avsyPath,""); [void]$updnTbl.Rows.Add(" D:",$avspPath,""); [void]$updnTbl.Rows.Add(" E:",$svfiPath,"")
"`r`n"+($updnTbl | Out-String).Trim() #1. Trim used to trim out empty rows, 2. Piping to Out-String to force $updnTbl to return the result before Read-Host below gets executed

Read-Host "`r`nCheck whether the correct programs are imported and [Enter] to proceed, restart otherwise"

#「Bootstrap E」Choose up-downstream program for the encoding commandline, generates impOPS, extOPS variable for route selection parameter
$impOPS=$extOPS=""
Do {Switch (Read-Host "Choose an upstream program for encoding [A | B | C | D | E], the rest will be commented out in generated batch") {
            a {if ($fmpgPath -ne "") {$impOPS="a"} else {nosuchrouteerr}}
            b {if ($vprsPath -ne "") {$impOPS="b"} else {nosuchrouteerr}}
            c {if ($avsyPath -ne "") {$impOPS="c"} else {nosuchrouteerr}}
            d {if ($avspPath -ne "") {$impOPS="d"} else {nosuchrouteerr}}
            e {if ($svfiPath -ne "") {$impOPS="e"} else {nosuchrouteerr}}
            default {badinputwarning}
    }
    if ($impOPS -ne "") {#No-execusion when upstream input has failed, move to loop end and trigger a loopback instead
        Switch (Read-Host "`r`nChoose a downstream program for encoding [A | B], the rest will be commented out in generated batch") {
            a {if ($x265Path -ne "") {$extOPS="a"} else {nosuchrouteerr}}
            b {if ($x264Path -ne "") {$extOPS="b"} else {nosuchrouteerr}}
            default {badinputwarning}
        }
    }
} While (($impOPS -eq "") -or ($extOPS -eq ""))

#「Bootstrap F」Use impOPS, extOPS to generate the selected route as new variable keyRoute
$keyRoute=""; $sChar="AAA" #An accident-proof measure where in bootstrap F, G expands $sChar too early, which may cause empty value error
Switch ($mode+$impOps+$extOPS) {
    saa {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA% %x265VarA%"}         #ffmpeg+x265+single
    sab {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA% %x264VarA%"}         #ffmpeg+x264+single
    sba {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x265Path %x265ParA% %x265VarA%"}         #VSPipe+x265+single
    sbb {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x264Path %x264ParA% %x264VarA%"}         #VSPipe+x264+single
    sca {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x265Path %x265ParA% %x265VarA%"}         #AVSYUV+x265+single
    scb {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x264Path %x264ParA% %x264VarA%"}         #AVSYUV+x264+single
    sda {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x265Path %x265ParA% %x265VarA%"}         #AVSPmd+x265+single,   No "-" in AVSPipeMod upstream
    sdb {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x264Path %x264ParA% %x264VarA%"}         #AVSPmd+x264+single,   No "-" in AVSPipeMod upstream
    sea {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x265Path %x265ParA% %x265VarA%"}         #OLSARG+x265+single
    seb {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x264Path %x264ParA% %x264VarA%"}         #OLSARG+x264+single
    maa {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x265Path %x265ParA%"+' %x265Var$sChar%'} #ffmpeg+x265+multiple, single quoting to yield expansion
    mab {$keyRoute="$fmpgPath %ffmpegVarA% %ffmpegParA% - | $x264Path %x264ParA%"+' %x264Var$sChar%'} #ffmpeg+x264+multiple
    mba {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x265Path %x265ParA%"+' %x265Var$sChar%'} #VSPipe+x265+multiple
    mbb {$keyRoute="$vprsPath %vspipeVarA% %vspipeParA% - | $x264Path %x264ParA%"+' %x264Var$sChar%'} #VSPipe+x264+multiple
    mca {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x265Path %x265ParA%"+' %x265Var$sChar%'} #AVSYUV+x265+multiple
    mcb {$keyRoute="$avsyPath %avsyuvVarA% %avsyuvParA% - | $x264Path %x264ParA%"+' %x264Var$sChar%'} #AVSYUV+x264+multiple
    mda {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x265Path %x265ParA%"+' %x265Var$sChar%'} #AVSPmd+x265+multiple, No "-" in AVSPipeMod upstream
    mdb {$keyRoute="$avspPath %avsmodVarA% %avsmodParA%   | $x264Path %x264ParA%"+' %x264Var$sChar%'} #AVSPmd+x264+multiple, No "-" in AVSPipeMod upstream
    mea {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x265Path %x265ParA%"+' %x265Var$sChar%'} #OLSARG+x265+multiple
    meb {$keyRoute="$svfiPath %olsargVarA% %olsargParA% - | $x264Path %x264ParA%"+' %x264Var$sChar%'} #OLSARG+x264+multiple
    Default {modeimpextopserr}
}
#「Bootstrap G」Generate all possible possible upstream--downstream commandline layouts, which are the alternate routes
[array] $upPipeStr=@("$fmpgPath %ffmpegVarA% %ffmpegParA%", "$vprsPath %vspipeVarA% %vspipeParA%", "$avsyPath %avsyuvVarA% %avsyuvParA%", "$avspPath %avsmodVarA% %avsmodParA%","$svfiPath %olsargVarA% %olsargParA%") | Where-Object {$_.Length -gt 26}
Switch ($mode) {#Filter the non-existant route in dnPipeStr with length property, multile encoding mode has downstream commandline with $sChar variable which is 1 character less the nsingle encode mode, make use of the if split
    s {[array]$dnPipeStr=@( "$x265Path %x265ParA% %x265VarA%",          "$x264Path %x264ParA% %x264VarA%")          | Where-Object {$_.Length -gt 22}}
    m {[array]$dnPipeStr=@(("$x265Path%x265ParA%"+' %x265Var$sChar%'), ("$x264Path %x264ParA%"+' %x264Var$sChar%')) | Where-Object {$_.Length -gt 23}} #single quoting to yield expansion, extra () are used to prevent "+" & "," mixing up in Array
    Default {modeparamerror}
}
[array]$altRoute=@() #Commenting sign + `$updnPipeStr = altRoute. Thus generates all the alternate routes
for     ($x=0; $x -lt ($upPipeStr.Length); $x++) {#upstream/horizontal iteration of possibilities
    for ($y=0; $y -lt ($dnPipeStr.Length); $y++) {#downstream/vertical iteration of possibilities
        if ($upPipeStr -notlike "avsmod") {$altRoute+="REM "+$upPipeStr[$x]+" - | "+$dnPipeStr[$y]} #No "-" in AVSPipeMod upstream
        else                              {$altRoute+="REM "+$upPipeStr[$x]+"   | "+$dnPipeStr[$y]} #No "-" in AVSPipeMod upstream
    }
}
"√ Number of usable/alternate routes are: "+($altRoute.Count.ToString()) | Out-String #Variable `$keyRoute & `$altRoute are ready, only differs in single & multiple mode where variable expansion is needed in multiple encoding mode

if ($extOPS="a") {tmpmuxreminder} #Provide reminder for multiplexing to .mkv when selecting x265/hevc donwstream keyRoute

#「Bootstrap H.m」3 dimension axis placed in for-loop realized with $validChars[x]+$validChars[y]+$validChars[z]
#Simulated mathmatical carrying by: +1 to x-axis, +1 to y-axis & clear x after x-axis gets filled up; +1 to z-axis & clear x&y after filling up y-axis.
[int]$x=[int]$y=[int]$z=0
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #Enfore the output of UTB-8NoBom

#Iteration begins, carry as any axis reaches letter 27. Switch occupies temp-variable $_ which cannot be used to initialize this loop. Counts as a 3-digit twenty-hexagonal
For ($s=0; $s -lt $qty; $s++) {
    #$x+=1 is commented out at beginning as values are being parsed to filenames, therefore placed at the trailing of loop
    if ($x -gt 25) {$y+=1; $x=0}
    if ($y -gt 25) {$z+=1; $y=$x=0}
    [string]$sChar=$validChars[$z]+$validChars[$y]+$validChars[$x] #Start constructing variable $sChar in this loop
    #Due to the delection of (redundant) feature to generate temporary multiplexed container, variable $serial is no longer needed and therefore deleted
    #keyRoute & altRoute with collapsed $sChar will be expanded at lower printing statement
    #When expanding $sChar variable, Array would generate a multi-line text without line change, therefore a pipe to Out-String and then activatng the $sChar variable is needed, multiple encode only
    $banner = "-----------Starting encode "+$sChar+"-----------"
    Write-Output "  Generating enc_$s.bat"

    $enc_gen="REM 「Title」
@echo.
@echo "+$banner+"

REM 「Debug section」Comment out during normal usage
REM @echo %ffmpegParA% %ffmpegVar"+$sChar+"%
REM @echo %vspipeParA% %vspipeVar"+$sChar+"%
REM @echo %avsyuvParA% %avsyuvVar"+$sChar+"%
REM @echo %avsmodParA% %avsmodVar"+$sChar+"%
REM @echo %olsargParA% %olsargVar"+$sChar+"%
REM @echo %x265ParA% %x265Var"+$sChar+"%
REM @echo %x264ParA% %x264Var"+$sChar+"%
REM pause

REM 「Encode-KeyRoutes」Comment out during debugging
REM Var is used to specify dynamic values such as input-output, per-video encoding options

"+$ExecutionContext.InvokeCommand.ExpandString(($keyRoute | Out-String))+"

REM 「Encode-ALTRoutes」Copy and replace from lower to upper commandline wihtout REM commenting to change encoding programs

"+$ExecutionContext.InvokeCommand.ExpandString(($altRoute | Out-String))+"

REM Choose「y:Continue/n:Pause/z:END」Auto-continue after 5s, false input are blocked by choice statement, pause allows continue.

choice /C YNZ /T 5 /D Y /M `" Continue? (Sleep=5; Default: Y, Pause: N, Stop: Z)`"

if %ERRORLEVEL%==3 cmd /k
if %ERRORLEVEL%==2 pause
if %ERRORLEVEL%==1 endlocal && exit /b"

    #Out-File -InputObject $enc_gen -FilePath $bchExpPath -Encoding utf8
    if     ($mode -eq "m") {[IO.File]::WriteAllLines($ExecutionContext.InvokeCommand.ExpandString($bchExpPath), $enc_gen, $utf8NoBOM)}#Expanding variable $s is needed in multiple encoding mode
    elseif ($mode -eq "s") {[IO.File]::WriteAllLines($bchExpPath, $enc_gen, $utf8NoBOM)}
    else {modeparamerror}
    $x+=1
}#Closing For-loop

Write-Output "Completed, as long as up-downstream program doesn't update, any controller batch generated by step 3 could always use enc_0S.bat / enc_X.bat"
pause