cls #「Bootstrap -」Multi-encode methods require users to manually add importing filenames
Read-Host "Multiple encoding mode only specifies the path to import files to encode, which require manually adding filenames into generated controller batch`r`nx264 usually comes with lavf, unlike x265, therefore x265 usually exports .hevc raw-streams instead of .mp4. Press Enter to proceed"

#Function namecheck([string]$inName) {
#    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
#    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
#    return $true
#} #Checking if input filename compliants to Windows file naming scheme, only required by single encoding mode

Function whereisit($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a file
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #Starting path set to Desktop
    #Intercepting failed inputs with if statement
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName}
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗, 通过SelectedPath将GUI交互窗锁定到桌面文件夹, 效果一般
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="选择路径用的窗口. 拖拽边角可放大此窗口"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #打开选择文件的GUI交互窗, 用if拦截误操作
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a folder/path/dir
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ Description="Select a directory. Drag bottom corner to enlarge"; SelectedPath=[Environment]::GetFolderPath($startPath); RootFolder='MyComputer'; ShowNewFolderButton=$true }
    #Intercepting failed inputs with if statement
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #Root directory always have a "\" in return, whereas a folder/path/dir doesn't. Therefore an if statement is used to add "\" when needed, but comment out under single-encode mode
    if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}
    return $endPath
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

#「Bootstrap A」Generate 1~n amount of "enc_[numbers].bat". Not needed in singular encode mode
[array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
[int]$qty=0 #Start counting from 0 instead of 1
Do {[int]$qty = (Read-Host -Prompt "Specify the previous amount of [generated encoding batches]. Range from 1~15625")
        if ($qty -eq 0) {"Non-integer or no value was entered"} elseif ($qty -gt 15625) {Write-Warning "Greater than 15625 individual encodes"}
} While (($qty -eq 0) -or ($qty -gt 15625))

#「Bootstrap B」Locate path to export batch files
Read-Host "`r`nPress Enter to open a window that locates [path for exporting batch files], it may pop up at rear of current window."
$exptPath = whichlocation
Write-Output "√ Selected $exptPath`r`n"

#「Bootstrap C」Choose if user wants leading zeros in exporting file (both stream & temp-multiplex files), INT variable $qty has no Length property, therefore INT-str convertion were used. Not needed in singular encode mode
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

#「Bootstrap D」Locate path to export encoded files
Read-Host "Press Enter to proceed open a window to [locate path to export encoded files]"
$fileEXP = whichlocation
Write-Output "√ Selected $fileEXP`r`n"

#「Bootstrap E」Step 2 already learns paths to ffmpeg & so. Therefore here the import is for files to encode. Note the variables are renamed to further stress the difference
Write-Output "Reference: [Video file formats]https://en.wikipedia.org/wiki/Video_file_format"
Write-Output "Step 2 already learns paths to ffmpeg & so. Here it's about to import a path with files to encode`r`n"
Do {$IMPchk=$vidIMP=$vpyIMP=$avsIMP=$apmIMP=""
    Switch (Read-Host "The previously selected pipe upstream program was [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod]") {
        a {$IMPchk="a"; Write-Output "`r`nSelected ffmpeg-----video source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $vidIMP=whichlocation}
        b {$IMPchk="b"; Write-Output "`r`nSelected vspipe------.vpy source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $vpyIMP=whichlocation} #Multi-encode only, procedure is different from single-encode mode
        c {$IMPchk="c"; Write-Output "`r`nSelected avs2yuv-----.avs source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $avsIMP=whichlocation}
        d {$IMPchk="d"; Write-Output "`r`nSelected avs2pipemod-.avs source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $apmIMP=whichlocation}
        default {Write-Warning "Bad input, try again"}
    }
} While ($IMPchk -eq "")

#「Bootstrap F1」Aggregate and feedback user's selected path
$impEXTa=$vidIMP+$vpyIMP+$avsIMP+$apmIMP
Write-Output "`r`nPath/File selected under multi/single-encode mode is $impEXTa`r`n"

#「Bootstrap F2」Under single encode mode, file extension analysis is needed, makes Bootstrap F different. Ditched Get-ChildItem because it containmates variables
#$impEXTc=$vidIMP+$vpyIMP+$avsIMP+$apmIMP
#if (($impEXTc -eq "") -eq $true) {Write-Error "× Imported file is blank"; pause; exit}
#else {
#    $impEXTc=[io.path]::GetExtension($impEXTc)
#    $impFNM=[io.path]::GetFileNameWithoutExtension($impEXTc)
#}

#Report if imported files doesn't have a matching extension (e.g., vspipe=".vpy", avs2yuv=".avs")
#if (($IMPchk -eq "d") -or ($IMPchk -eq "c")) {
#    if (($impEXTc -eq ".avs") -eq $false) {Write-Warning "Imported file extension is $impEXTc instead of .avs`r`n"} #if statement is used to prevent selection of ffmpeg path + an empty $impEXTc
#} elseif ($IMPchk -eq "b") {
#    if (($impEXTc -eq ".vpy") -eq $false) {Write-Warning "Imported file extension is $impEXTc instead of .vpy`r`n"} #Comment this out during multi-encode mode as no source file is imported
#} #Note: Import variable: $impEXTc; Export variable: $fileEXP

#「Bootstrap G」Avs2pipemod requires avisynth.dll, which needs to be added to commandline
if ($IMPchk -eq "d") {
    Read-Host "Press Enter to proceed open a window to [import a sample source video for ffprobe to analyze]. Note that ffprobe cannot analyze .vpy/.avs files"
    $apmDLL=whereisit
    $DLLchk=(Get-ChildItem $apmDLL).Extension #Report if imported file extension isn't .dll
    if (($DLLchk -eq ".dll") -eq $false) {Write-Warning "File extension is $apmDLL instead of .dll"}
    Write-Output "√ Added avs2pipemod option: $apmDLL`r`n"
} else {$apmDLL="X:\Somewhere\avisynth.dll"}

#「Bootstrap H1」Importing a video file for ffprobe to check, under non-ffmpeg upstream routes. Only for single-encode mode as ffmpeg route imports a video, instead of a path
#if ($IMPchk -eq "a") {$impEXTc=$vidIMP}
#else {
#    Read-Host "Press Enter to proceed open a window to [import a source video sample for analysis] by ffprobe. Note that ffprobe cannot analyze .vpy nor .avs files"
#    $impEXTc=whereisit
#}
#「Bootstrap H2」For multi-encode mode
Read-Host "Press Enter to proceed open a window to [import a source video sample for analysis] by ffprobe. Note that ffprobe cannot analyze .vpy nor .avs files"
$impEXTc=whereisit

#「Bootstrap I」Locate ffprobe
Read-Host "Press Enter to proceed open a window to [locate ffprobe.exe]"
$fprbPath=whereisit

#「ffprobeA2」Begin analyze sample video. Due to people confuses at MKV files' NUMBER_OF_FRAMES; NUMBER_OF_FRAMES-eng & etc. tagging, some MKV files ends up not having data on NUMBER_OF_FRAMES tag (at CSV's tag 24,25), therefore by reading both and keep the non-0 value would provide fallback
$parsProbe = $fprbPath+" -i '$impEXTc' -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
Invoke-Expression $parsProbe > "C:\temp_v_info.csv"

#i.e.: $parsProbe = "D:\ffprobe.exe -i `"F:\Asset\Video\BDRipPT\[Beatrice-Raws] Anne Happy [BDRip 1920x1080 x264 FLAC]\[Beatrice-Raws] Anne Happy 01 [BDRip 1920x1080 x264 FLAC].mkv`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#i.e.: $parsProbe = "D:\ffprobe.exe -i `"N:\SolLevante_HDR10_r2020_ST2084_UHD_24fps_1000nit.mov`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#Invoke-Expression $parsProbe > "C:\temp_v_info.csv"
#Notepad "C:\temp_v_info.csv"

#「ffprobeB」Read with Import-CSV module and map them as an array, header is needed as ffprobe generates headless CSV by default A~F, A file is created because there is currently no method to parse value wihtout exporting CSV to file, and for debugging (swap Remove-Item to Notepad) purpose
$ffprobeCSV = Import-Csv "C:\temp_v_info.csv" -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA
Remove-Item "C:\temp_v_info.csv" #File is saved to C drive because most Windows PC has only has 1 logical disk

#「ffprobeB3」Filling x265's option --subme <24fps=3, 48fps=4, 60fps=5, ++=6>
if ($ffprobeCSV.H -lt 61) {
    $x265subme="--subme 5"
    if ($ffprobeCSV.H -lt 49) {
        $x265subme="--subme 4"
        if ($ffprobeCSV.H -lt 25) {
            $x265subme="--subme 3"}}
} else {$x265subme="--subme 6"}
Write-Output "√ Added x265 option: $x265subme"

$WxH="--input-res "+$ffprobeCSV.B+"x"+$ffprobeCSV.C+""
$color_matrix="--colormatrix "+$ffprobeCSV.F
$trans_chrctr="--transfer "+$ffprobeCSV.G
$fps="--fps "+$ffprobeCSV.H
$fmpgfps="-r "+$ffprobeCSV.H
Write-Output "√ Added x264-5 options: $color_matrix $trans_chrctr $fps $WxH`r`n√ Added ffmpeg options: $fmpgfps`r`n"

#「ffprobeC」fetch total frame count with ffprobe, then parse to variable $x265VarA, for single-encode mode only
#if ($ffprobeCSV.I -match "^\d+$") {
#    $nbrFrames = "--frames "+$ffprobeCSV.I
#    Write-Output "Detecting MPEGtag total frame count`r`n√ Added x264-5 option: $nbrFrames"
#} elseif ($ffprobeCSV.AA -match "^\d+$") {
#    $nbrFrames = "--frames "+$ffprobeCSV.AA
#    Write-Output "Detecting MKVtag total frame count`r`n√ Added x264-5 option: $nbrFrames"
#} else {Write-Output "× tag: Total frame count is missing, Leaving blank on x264-5 option --frames, the drawback is ETA information will be missing during encoding (estimate time of completion)"}

#「ffprobeD1」fetch colorspace & depth format forffmpeg, VapourSynth, AviSynth, AVS2PipeMod, x264 & x265
[string]$avsCSP=[string]$avsD=[string]$encCSP=[string]$ffmpegCSP=[string]$encD=$null
Do {Switch ($ffprobeCSV.D) {
        yuv420p     {Write-Output "Detecting colorspace & bitdepth[yuv420p 8bit ]"; $avsCSP="-csp i420"; $avsD="-depth 8";  $encCSP="--input-csp i420"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv420p"}
        yuv420p10le {Write-Output "Detecting colorspace & bitdepth[yuv420p 10bit]"; $avsCSP="-csp i420"; $avsD="-depth 10"; $encCSP="--input-csp i420"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv420p10le"}
        yuv420p12le {Write-Output "x265-only colorspace & bitdepth[yuv420p 12bit]"; $avsCSP="-csp i420"; $avsD="-depth 12"; $encCSP="--input-csp i420"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv420p12le"}
        yuv422p     {Write-Output "Detecting colorspace & bitdepth[yuv422p 8bit ]"; $avsCSP="-csp i422"; $avsD="-depth 8";  $encCSP="--input-csp i422"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv422p"}
        yuv422p10le {Write-Output "Detecting colorspace & bitdepth[yuv422p 10bit]"; $avsCSP="-csp i422"; $avsD="-depth 10"; $encCSP="--input-csp i422"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv422p10le"}
        yuv422p12le {Write-Output "x265-only colorspace & bitdepth[yuv422p 12bit]"; $avsCSP="-csp i422"; $avsD="-depth 12"; $encCSP="--input-csp i422"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv422p12le"}
        yuv444p     {Write-Output "Detecting colorspace & bitdepth[yuv444p 8bit ]"; $avsCSP="-csp i444"; $avsD="-depth 8";  $encCSP="--input-csp i444"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt yuv444p"}
        yuv444p10le {Write-Output "Detecting colorspace & bitdepth[yuv444p 10bit]"; $avsCSP="-csp i444"; $avsD="-depth 10"; $encCSP="--input-csp i444"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv444p10le"}
        yuv444p12le {Write-Output "x265-only colorspace & bitdepth[yuv444p 12bit]"; $avsCSP="-csp i444"; $avsD="-depth 12"; $encCSP="--input-csp i444"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv444p12le"}
        gray        {Write-Output "Detecting colorspace & bitdepth[yuv400p 8bit ]"; $avsCSP="-csp i400"; $avsD="-depth 8";  $encCSP="--input-csp i400"; $encD="--input-depth 8";  $ffmpegCSP="-pix_fmt gray"}
        gray10le    {Write-Output "Detecting colorspace & bitdepth[yuv400p 10bit]"; $avsCSP="-csp i400"; $avsD="-depth 10"; $encCSP="--input-csp i400"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt gray10le"}
        gray12le    {Write-Output "x265-only colorspace & bitdepth[yuv400p 12bit]"; $avsCSP="-csp i400"; $avsD="-depth 12"; $encCSP="--input-csp i400"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt gray12le"}
        nv12        {Write-Output "x265-only colorspace & bitdepth[ nv12 12bit ]";  $avsCSP="-csp AUTO"; $avsD="-depth 12"; $encCSP="--input-csp nv12"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt nv12"}
        nv16        {Write-Output "x265-only colorspace & bitdepth[ nv16 16bit ]";  $avsCSP="-csp AUTO"; $avsD="-depth 16"; $encCSP="--input-csp nv16"; $encD="--input-depth 16"; $ffmpegCSP="-pix_fmt nv16"}
        default     {Write-Warning "! Incompatible colorspace & bitdepth"($ffprobeCSV.D)}
    }
} While ($ffmpegCSP -eq $null)
if ($ffmpegCSP -ne $null) {Write-Output "√ Added ffmpeg option: $ffmpegCSP`r`n√ Added avs2yuv options: $avsCSP $avsD`r`n"}
if ($avsCSP -eq "-csp AUTO") {Write-Warning "avs2yuv may not work with nv12/nv16 colorspaces"}

#「Bootstrap J」Choose downstream program of file pipe, x264 or x265
Do {$ENCops=$x265Path=$x264Path=""
    Switch (Read-Host "Choose a downstream pipe program [A: x265/hevc | B: x264/avc]") {
        a {$ENCops="a"; Write-Output "`r`nSelecting x265--route A. Opening a selection window to [locate x265.exe]"; $x265Path=whereisit}
        b {$ENCops="b"; Write-Output "`r`nSelecting x264--route B. Opening a selection window to [locate x264.exe]"; $x264Path=whereisit}
        default {Write-Warning "Bad input, try again"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "√ Selected $encEXT"

#「Bootstrap K」Select multiple ways of specifying exporting filenames, episode variable $serial works at lower loop structure
$vidEXP=[io.path]::GetFileNameWithoutExtension($impEXTc)
Do {Switch (Read-Host "`r`nChoose how to specify filename of encoding exports [A: Input manually | B: Copy from an existing file | C: $vidEXP]`r`nNote that PowerShell misinterprets square brackets next to eachother, e.g., [some][text]. Space inbetween them is required") {
        a { $vidEXP=Read-Host "`r`nSpecify filename to export (w/out file extension). Place episode conter `$serial in desired location.`r`n`r`n`$serial should be padded from trailing alphabets. e.g., [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)"
            $chkme=namecheck($vidEXP)
            if (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "Missing variable `$serial under multi-encode mode; No value entered; Or intercepted illegal characters / | \ < > : ? * `""}
            #if (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "Detecting variable `$serial in single-encode mode; No value entered; Or intercepted illegal characters / | \ < > : ? * `""}
            #[string]$serial=($s).ToString($zroStr) #Example of parsing leading zeros to $serial. Used in for loop below (supplies variable $s)
            #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #Activating $serial as a variable with expand string method. Used in for loop below
        }
        b { Write-Output "Opening a selection window to [get filename from a file]"
            $vidEXP=whereisit
            $chkme=namecheck($vidEXP)
            $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
            $vidEXP+='_$serial' #Single quotes are used to prevent variable being expanded (becomes static value), comment this out in singular encoding batch mode
            Write-Output "`r`nIn multi-encode mode, option B, C will add a trailing counter in filename`r`n"
        }
        c { $chkme=namecheck($vidEXP)
            $vidEXP+='_$serial'}  #Single quotes are used to prevent variable being expanded (becomes static value), comment this out in singular encoding batch mode
        default {Write-Warning "Bad input, try again"}
    }
} While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) #Multi-encoding only, comment out under single-encode mode
#} While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) #Single-encoding only, comment out under multi-encode mode
Write-Output "√ Added exporting filename $vidEXP`r`n"

#「Bootstrap L, M」1: Specify file extention based on x264-5. 2: For x265, ddd pme/pools based on cpu core count & motherboard node count.
#Extra filtering x265 that usually doesn't come with lavf (cannot export MP4), x264 usually comes with lavf but does not support pme/pools
if ($ENCops -eq "b") {$nameIn+=".mp4"}
elseif ($ENCops -eq "a") {
    $nameIn+=".hevc"
    $pme=$pool=""
    $procNodes=0
    
    [int]$cores=(wmic cpu get NumberOfCores)[2]
    if ($cores -gt 21) {$pme="--pme"; Write-Output "√ Detecting processor's core count reaching 22, added x265 option: --pme"}

    $AllProcs=Get-CimInstance Win32_Processor | Select Availability
    ForEach ($_ in $AllProcs) {if ($_.Availability -eq 3) {$procNodes+=1}}
    if ($procNodes -eq 2) {$pools="--pools +,-"}
    elseif ($procNodes -eq 4) {$pools="--pools +,-,-,-"}
    elseif ($procNodes -eq 6) {$pools="--pools +,-,-,-,-,-"}
    elseif ($procNodes -eq 8) {$pools="--pools +,-,-,-,-,-,-,-"}
    elseif ($procNodes -gt 8) {Write-Warning "? Detecting an unusal amount of installed processor nodes ($procNodes), please add option --pools manually"} #Cannot use else, otherwise -eq 1 gets accounted for "unusual amount of comp nodes"
    if ($procNodes -gt 1) {Write-Output "√ Detected $procNodes installed processors, added x265 option: $pools"}
}

Set-PSDebug -Strict
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #export batch file w/ utf-8NoBOM text codec

#Note: Inport file variable: $impEXTc; Export file variable: $fileEXP
#「Initialize」$ffmpegPar-ameters variable contains no trailing spaces
#「Limitation」$ffmpegPar-ameters can only be added after all of file-imported option ("-i")s are written, & ffmpeg option "-hwaccel" must be written before of "-i". This further increases the string reallocation work & amount of variables needed to assemble ffmpeg commandline
#Remove option "loglevel" when debugging
#Add "-thread_queue_size<Avg bitrate gets computed during encode kbps+1000>" when ffmpeg shows warning "-thread_queue_size is too small", but the better practice is to replace ffmpeg
$ffmpegParA="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -an -f yuv4mpegpipe -strict unofficial" #Step 2 already addes "- | -" for pipe operation. Therefore there is no need to add it here
$ffmpegParB="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -c:v copy" #The ffmpeg commandline to generate temporary MP4. This workaround enables ffmpeg to multiplex .mp4 instead of .hevc to .mkv
$vspipeParA="--y4m"
$avsyuvParA="$avsCSP $avsD"
$avsmodParA="`"$apmDLL`" -y4mp" #Note: avs2pipemod uses "| -" instead of other tools' "- | -" pipe commandline (leave upstream/leftside "-" blank). y4mp, y4mt, y4mb represents progressive, top-field-1st interlace, bottom-field-1st interlace. This script does not bother interlaced sources to lower program complexity

#「Initialize」x265Par-ameters, contains a trailing space
$x265ParA="$encD $x265subme $color_matrix $trans_chrctr $fps $WxH $encCSP $pme $pools --tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --me umh --merange 48 --weightb --max-merge 4 --early-skip --ref 3 --no-open-gop --min-keyint 5 --keyint 250 --fades --bframes 16 --b-adapt 2 --radl 3 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --tskip --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rc-lookahead 68 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --qp-adaptation-range 4 --deblock -1:0 --limit-sao --sao-non-deblock --hash 2 --allow-non-conformance --single-sei --y4m -"
$x264ParA="$encD $color_matrix $trans_chrctr $fps $WxH $encCSP --me umh --subme 9 --merange 48 --no-fast-pskip --direct auto --weightb --keyint 360 --min-keyint 5 --bframes 12 --b-adapt 2 --ref 3 --rc-lookahead 90 --crf 20 --qpmin 9 --chromaqp-offset -2 --aq-mode 3 --aq-strength 0.7 --trellis 2 --deblock 0:0 --psy-rd 0.77:0.22 --fgo 10 --y4m -"
#「Initialize」x264-5 variables, adding --frames, no trailing spaces, single-file mode only
#$x265VarA=$x264VarA="$nbrframes --output `"$fileEXP$vidEXP`""

#Iteration begins, carry as any axis reaches letter 27. Switch occupies temp-variable $_ which cannot be used to initialize this loop. Counts as a 3-digit twenty-hexagonal
$ffmpegVarSChar=$vspipeVarSChar=$avsyuvVarSChar=$avsmodVarSChar=$x265VarNosChar=$x264VarNosChar=$encCallNosChar=$vidEXX=@()
$ffmpegVarWarp=$vspipeVarWarp=$avsyuvVarWarp=$avsmodVarWarp=$x265VarWarp=$x264VarWarp=$tempMuxOut=$tempEncOut=""
[int]$x=[int]$y=[int]$z=0
For ($s=0; $s -lt $qty; $s++) {
    #$x+=1 is commented out at beginning as values are being parsed to filenames, therefore placed at the trailing of loop
    if ($x -gt 25) {$y+=1; $x=0}
    if ($y -gt 25) {$z+=1; $y=$x=0}
    $sChar=$validChars[$z]+$validChars[$y]+$validChars[$x]

    [string]$serial=($s).ToString($zroStr) #leading zeros processor, this prevents $s from being the actual episode counter. $serial is converted int-to-string to allow placing leading 0s
    
    $vidEXX+=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #$vidEXP contains $serial. Expand is needed to convert $serial from string to variable. Breaking the previous single quotes' seal

    $tempMuxOut=$vidEXX[$s]+".mp4" #multi-encode mode's temporary multiplex solution. $serial is used instead of $sChar
    $tempEncOut=$vidEXX[$s]+".hevc"

    $ffmpegVarSChar+="@set `"ffmpegVar"+$sChar+"=-hwaccel auto -i `"video-to-encode"+"_"+"$sChar.mkv`"`"`n"
    $vspipeVarSChar+="@set `"vspipeVar"+$sChar+"=-i `"video-to-encode"+"_"+"$sChar.mkv`"`"`n"
    $avsyuvVarSChar+="@set `"avsyuvVar"+$sChar+"=-i `"video-to-encode"+"_"+"$sChar.mkv`"`"`n"
    $avsmodVarSChar+="@set `"avsmodVar"+$sChar+"=-i `"video-to-encode"+"_"+"$sChar.mkv`"`"`n"

    $x265VarNosChar+="@set `"x265Var"+$sChar+"=--output `"$fileEXP$tempMuxOut`"`"`n"
    $x264VarNosChar+="@set `"x264Var"+$sChar+"=--output `"$fileEXP$tempMuxOut`"`"`n"
    $encCallNosChar+="call enc_$s.bat`n"

    $x+=1 #The loop automatically applies $s+=1, but manual application is needed for debugging
}
#Harvest array datatype of ffmpeg & similar tools' generated commandlines. Each commandline supplies information needed for individual encode batch
[string]$ffmpegVarWrap=$ffmpegVarSChar;$ffmpegVarWrap=$ffmpegVarWrap -replace " @set", "@set" #Convert back to string will result in " @set xxx", therefore replacing back to "@set xxx"
[string]$vspipeVarWrap=$vspipeVarSChar;$vspipeVarWrap=$vspipeVarWrap -replace " @set", "@set"
[string]$avsyuvVarWrap=$avsyuvVarSChar;$avsyuvVarWrap=$avsyuvVarWrap -replace " @set", "@set"
[string]$avsmodVarWrap=$avsmodVarSChar;$avsmodVarWrap=$avsmodVarWrap -replace " @set", "@set"
[string]$x265VarWrap = $x265VarNosChar;$x265VarWrap = $x265VarWrap   -replace " @set", "@set"
[string]$x264VarWrap = $x264VarNosChar;$x264VarWrap = $x264VarWrap   -replace " @set", "@set"
[string]$encCallWrap = $encCallNosChar;$encCallWrap = $encCallWrap   -replace " call", "call"

#「Generate the controller batch」
$ctrl_gen="REM 「Compatible with UTF-8」opt-out from ANSI code page
REM 「Safe for with multiple runs」Achieved by set+endlocal, works both at stopping during encoding and controlling batch
REM 「Compatible localized CLI language」Implementation failed, the batch file must run with code page 65001
REM 「Startup」Disable prompt input display, 5s sleep

@echo off
timeout 5
chcp 65001
setlocal

REM 「Non-std exiting」Clean up used variables with taskkill /F /IM cmd.exe /T. Otherwise it may cause variable contamination

@echo 「Non-std exits」cleanup with `"taskkill /F /IM cmd.exe /T`" is necessary to prevent residual variable's presence from previously ran sripts.
@echo. && @echo --Starting multi-batch-enc workflow v2--

REM 「ffmpeg debug」Delete -loglevel 16
REM 「-thread_queue_size small err」Specity ffmpeg option -thread_queue_size<computing kbps+1000>, but better to replace ffmpeg

REM 「ffmpeg, vspipe, avsyuv, avs2pipemod fixed Parameters」

@set `"ffmpegParA="+$ffmpegParA+"`"
@set `"vspipeParA="+$vspipeParA+"`"
@set `"avsyuvParA="+$avsyuvParA+"`"
@set `"avsmodParA="+$avsmodParA+"`"

REM 「ffmpeg, vspipe, avsyuv, avs2pipemod Variable optoins」

"+$ffmpegVarWrap+"
"+$vspipeVarWrap+"
"+$avsyuvVarWrap+"
"+$avsmodVarWrap+"

REM 「x264-5 fixed Parameters」

@set `"x265ParA="+$x265ParA+"`"
@set `"x264ParA="+$x264ParA+"`"

REM 「x264-5 Variable optoins」Comment out during debugging

"+$x264VarWrap+"
"+$x265VarWrap+"

REM 「Debugging」x264-5 Variable options, comment out during normal use, variables have no trailing spaces

REM @set `"x265VarA=--crf 23 ... --output ...`"
REM @set `"x265VarB=--crf 26 ... --output ...`"
REM @set `"x264VarA=--crf 23 ... --output ...`"
REM @set `"x264VarA=--crf 26 ... --output ...`"

REM 「Encoding」Use commenting or deleting encode batches to skip undesired encode tasks

"+$encCallWrap+"

REM 「Finish」Perserve CMD prompt after finish, use /k instead of -k could skip printing of Windows build information

endlocal
cmd -k"

if ($IMPchk -eq "a") {$exptPath+="4A.M.「Controller」.bat"
} elseif ($IMPchk -eq "b") {$exptPath+="4B.M.「Controller」.bat"
} elseif ($IMPchk -eq "c") {$exptPath+="4C.M.「Controller」.bat"
} elseif ($IMPchk -eq "d") {$exptPath+="4D.M.「Controller」.bat"}

Write-Output "`r`nGenerating $exptPath"
[IO.File]::WriteAllLines($exptPath, $ctrl_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec
Write-Output "Task completed"
pause