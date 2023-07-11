cls #「Bootstrap -」Multi-encode methods require users to manually add importing filenames
Read-Host "[Multiple encoding mode] only specifies the path to import files to encode, which require manually adding filenames into generated controller batch`r`nx264 usually comes with lavf, unlike x265, therefore x265 usually exports .hevc raw-streams instead of .mp4. Press Enter to proceed"
$mode="m" #multi-encode mode
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

Function setencoutputname ([string]$mode, [string]$switchOPS) {
    $DebugPreference="Continue" #Write-Output/Host does not work in a function, using Write-Debug instead

    Switch ($switchOPS) { #Switch with Read-Host doesn't work in Functions, therefore this question is asked & answered before entering this Function at K1-2
        a { Write-Debug "Opening a window that [copy filename on selection], it may pop up at rear of current window."

            $vidEXP=whereisit
            $chkme=namecheck($vidEXP)
            $vidEXP=[io.path]::GetFileNameWithoutExtension($vidEXP)
            if ($mode -eq "m") {$vidEXP+='_$serial'} #! Using single quotes in codeline here to prevent variable `$serial from being executed
                Write-Debug "`r`nIn multi-encode mode, choosing A will add a trailing counter in filename`r`n"
        } b {
            if ($mode -eq "m") {#Multi-encoding mode
                Do {$vidEXP=Read-Host "`r`nSpecify filename w/out extension (multi-encode mode)  `r`n1. Specify episode counter `$serial in desired location`r`n2. `$serial should be padded from trailing alphabets.`r`n3. Space is needed inbetween 2 square brackets`r`n  e.g., [YYDM-11FANS] [Yuru Yuri 2]`$serial[BDRIP 720P]; [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)"
                    $chkme=namecheck($vidEXP)
                    if  (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false)) {Write-Warning "Missing variable `$serial under multi-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                } While (($vidEXP.Contains("`$serial") -eq $false) -or ($chkme -eq $false))
            }
            if ($mode -eq "s") {#Single encoding mode
                Do {$vidEXP=Read-Host "`r`nSpecify filename w/out extension (multi-encode mode)  `r`n1. Specify episode counter `$serial in desired location`r`n2. `$serial should be padded from trailing alphabets.`r`n3. Space is needed inbetween 2 square brackets`r`n  e.g., [YYDM-11FANS] [Yuru Yuri 2]`$serial[BDRIP 720P]; [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)"
                    $chkme=namecheck($vidEXP)
                    if  (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false)) {Write-Warning "Missing variable `$serial under multi-encode mode; No value entered, Or intercepted illegal characters / | \ < > : ? * `""}
                } While (($vidEXP.Contains("`$serial") -eq $true) -or ($chkme -eq $false))
            }
                #[string]$serial=($s).ToString($zroStr) #Example of parsing leading zeros to $serial. Used in for loop below (supplies variable $s)
                #$vidEXP=$ExecutionContext.InvokeCommand.ExpandString($vidEXP) #Activating $serial as a variable with expand string method. Used in for loop below
        } default {#Compared to settmpoutputname, this Function won't encounter empty input, therefore Switch-default corresponds to the input file's own name
            if ($mode -eq "m") {$vidEXP+='_$serial'} #! Using single quotes in codeline here to prevent variable `$serial from being executed
        }
    }
    Write-Debug "`r`n√ Added exporting filename $vidEXP`r`n"
    return $vidEXP
}

Function hevcparwrapper {
    Param ([Parameter(Mandatory=$true)]$PICKops)
    Switch ($PICKops) {
        a {return "--tu-intra-depth 3 --tu-inter-depth 3 --limit-tu 1 --rdpenalty 1 --me umh --merange 48 --weightb--ref 3 --max-merge 3 --early-skip --no-open-gop --min-keyint 5 --fades --bframes 8 --b-adapt 2 --radl 3 --b-intra --constrained-intra --crf 21 --crqpoffs -3 --crqpoffs -1 --rdoq-level 2 --aq-mode 4 --aq-strength 0.8 --rd 3 --limit-modes --limit-refs 1 --rskip 3 --tskip-fast --rect --amp --psy-rd 1 --splitrd-skip --qp-adaptation-range 4 --limit-sao --sao-non-deblock --deblock 0:-1 --hash 2 --allow-non-conformance"} #generalPurpose
        b {return "--tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --me star --merange 48 --weightb --ref 3 --max-merge 4 --no-open-gop --min-keyint 3 --keyint 310 --fades --bframes 8 --b-adapt 2 --radl 3 --constrained-intra --b-intra --crf 21.8 --qpmin 8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --qg-size 8 --rd 3 --limit-refs 0 --rskip 0 --rect --amp --psy-rd 1.6 --deblock 0:0 --limit-sao --sao-non-deblock --selective-sao 3 --hash 2 --allow-non-conformance"} #filmCustom
        c {return "--tu-intra-depth 4 --tu-inter-depth 4 --limit-tu 1 --me star --merange 48 --weightb --ref 3 --max-merge 4 --no-open-gop --min-keyint 3 --fades --bframes 8 --b-adapt 2 --radl 3 --constrained-intra --b-intra --crf 21.8 --qpmin 8 --crqpoffs -3 --ipratio 1.2 --pbratio 1.5 --rdoq-level 2 --aq-mode 4 --aq-strength 1 --qg-size 8 --rd 3 --limit-refs 0 --rskip 0 --rect --amp --psy-rd 1 --qp-adaptation-range 3 --deblock 0:-1 --limit-sao --sao-non-deblock --selective-sao 3 --hash 2 --allow-non-conformance"} #stockFootag
        d {return "--tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 16 --me umh --merange 48 --weightb --max-merge 4 --early-skip --ref 3 --no-open-gop --min-keyint 5 --fades --bframes 16 --b-adapt 2 --radl 3 --bframe-bias 20 --constrained-intra --b-intra --crf 22 --crqpoffs -4 --cbqpoffs -2 --ipratio 1.6 --pbratio 1.3 --cu-lossless --tskip --psy-rdoq 2.3 --rdoq-level 2 --hevc-aq --aq-strength 0.9 --qg-size 8 --rd 3 --limit-modes --limit-refs 1 --rskip 1 --rect --amp --psy-rd 1.5 --splitrd-skip --rdpenalty 2 --qp-adaptation-range 4 --deblock -1:0 --limit-sao --sao-non-deblock --hash 2 --allow-non-conformance"} #animeFansubCustom
        e {return "--tu-intra-depth 4 --tu-inter-depth 4 --max-tu-size 4 --limit-tu 1 --me star --merange 52 --analyze-src-pics --weightb --max-merge 4 --ref 3 --no-open-gop --min-keyint 1 --fades --bframes 16 --b-adapt 2 --radl 2 --b-intra --crf 16.5 --crqpoffs -5 --cbqpoffs -2 --ipratio 1.67 --pbratio 1.33 --cu-lossless --psy-rdoq 2.5 --rdoq-level 2 --hevc-aq --aq-strength 1.4 --qg-size 8 --rd 5 --limit-refs 0 --rskip 2 --rskip-edge-threshold 3 --rect --amp --no-cutree --psy-rd 1.5 --rdpenalty 2 --qp-adaptation-range 5 --deblock -2:-2 --limit-sao --sao-non-deblock --selective-sao 1 --hash 2 --allow-non-conformance"} #animeBDRipColdwar
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
    try {return "--keyint "+[math]::Round((Invoke-Expression $CSVfps)*9)} catch {return "--keyint 249"} #Intentionally defining rare value for detection of execusion failure and normal usage
}

Function poolscalc{
    $allprocs=Get-CimInstance Win32_Processor | Select Availability
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a Function as it would trigger a value return, modify Write-Debug instead
    [int]$procNodes=0
    ForEach ($_ in $allprocs) {if ($_.Availability -eq 3) {$procNodes+=1}} #Only adding processors in normal state, otherwise it counts uninstalled slot as well
    if ($procNodes -gt 1) {
        if     ($procNodes -eq 2) {return "--pools +,-"}
        elseif ($procNodes -eq 4) {return "--pools +,-,-,-"}
        elseif ($procNodes -eq 6) {return "--pools +,-,-,-,-,-"}
        elseif ($procNodes -eq 8) {return "--pools +,-,-,-,-,-,-,-"}
        elseif ($procNodes -gt 8) {Write-Debug "? Detecting an unusal amount of installed processor nodes ($procNodes), add option --pools manually"; return ""} #Cannot use else, otherwise -eq 1 gets accounted for "unusual amount of comp nodes
    } else {Write-Debug "√ Detected 1 processor is running, avoided adding x265 option --pools"; return ""}
}

Function framescalc{
    Param ([Parameter(Mandatory=$true)]$fcountCSV, [Parameter(Mandatory=$true)]$fcountAUX)
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a Function as it would trigger a value return, modify Write-Debug instead
    if     ($fcountCSV -match "^\d+$") {Write-Debug "√ Detecting MPEGtag total frame-count"; return "--frames "+$fcountCSV}
    elseif ($fcountAUX -match "^\d+$") {Write-Debug "√ Detecting MKV-tag total frame-count"; return "--frames "+$fcountAUX}
    else {return ""}
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
if ($mode -eq "m") {
    [array]$validChars='A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    [int]$qty=0 #Start counting from 0 instead of 1
    Do {[int]$qty = (Read-Host -Prompt "Specify the previous amount of [generated encoding batches]. Range from 1~15625")
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
Read-Host "`r`nPress Enter to open a window that locates [path for exporting batch files], it may pop up at rear of current window."
$exptPath = whichlocation
Write-Output "√ Selected $exptPath`r`n"

#「Bootstrap D」Locate path to export encoded files
Read-Host "Hit Enter to proceed open a window to [locate path to export encoded files]"
$fileEXPpath = whichlocation
Write-Output "√ Selected $fileEXPpath`r`n"

#「Bootstrap E」Step 2 already learns paths to ffmpeg & so. Therefore here the import is for files to encode. Note the variables are renamed to further stress the difference
Write-Output "Reference: [Video file formats]https://en.wikipedia.org/wiki/Video_file_format`r`nStep 2 already learns paths to ffmpeg & so. Here it's about to import a path with files to encode`r`n"
$impEXTm=$IMPchk="" #impEXTm: Multu-encode mode's sourcefile import mode (path to files only)，IMPchk: upper-stream source type
Do {Switch (Read-Host "The previously selected pipe upstream program was [A: ffmpeg | B: vspipe | C: avs2yuv | D: avs2pipemod | E: SVFI (alpha)]") {
        a {Write-Output "`r`nSelected ffmpeg-----video source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $impEXTs=whichlocation; $IMPchk="a"}
        b {Write-Output "`r`nSelected vspipe------.vpy source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $impEXTs=whichlocation; $IMPchk="b"}
        c {Write-Output "`r`nSelected avs2yuv-----.avs source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $impEXTs=whichlocation; $IMPchk="c"}
        d {Write-Output "`r`nSelected avs2pipemod-.avs source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $impEXTs=whichlocation; $IMPchk="d"}
        e {Write-Output "`r`nSelected svfi(β)---video source. Opening a window to [locate path/directory w/ files to encode]`r`nThe procedure is to import path & add filnames in generated batch later"; $impEXTs=whichlocation; $IMPchk="e"}
        default {Write-Warning "`r`n× Bad input, try again"}
    } # Multi-encode can only input a path which contains all the files to encode
    $impEXTm
} While ($impEXTm -eq "")

#「Bootstrap F1」Aggregate and feedback user's selected path
if ($mode -eq "m") {Write-Output "`r`n√ Importing path is selected as $impEXTm`r`n"}
if ($mode -eq "s") {Write-Output "`r`n√ Importing file is selected as $impEXTs`r`n"
    if (($impEXTs -eq "") -eq $true) {Write-Error "× Imported file is blank"; pause; exit}
    else {#「Bootstrap F2」File extension fetching under single encode mode. Ditched Get-ChildItem because it containmates variables
        $impEXTs=[io.path]::GetExtension($impEXTs)
        $impFNM=[io.path]::GetFileNameWithoutExtension($impEXTs)
    }
    #「Bootstrap F3」Check file extension for avs2yuv, avs2pipemod routes
    if (($IMPchk -eq "d") -or ($IMPchk -eq "c")) {
        if ($impEXTs -ne ".avs") {Write-Warning "Imported file extension is $impEXTs instead of .avs`r`n"} #if statement is used to prevent selection of ffmpeg path + an empty $impEXTs
    } elseif ($IMPchk -eq "b") {#「Bootstrap F4」Check file extension for vspipe routes
        if ($impEXTs -ne ".vpy") {Write-Warning "Imported file extension is $impEXTs instead of .vpy`r`n"} #Comment this out during multi-encode mode as no source file is imported
    } #Note: Path source: $impEXTm, File source: $impEXTs, File export: $fileEXPpath
}

#「Bootstrap G1」Importing required avisynth.dll by Avs2pipemod
if ($IMPchk -eq "d") {
    Read-Host "Hit Enter to proceed open a window to [Select avisynth.dll] for Avs2pipemod, it may pop up at rear of current window"
    $apmDLL=whereisit
    $DLLchk=(Get-ChildItem $apmDLL).Extension #Report error if file extension is not .dll
    if (($DLLchk -eq ".dll") -eq $false) {Write-Warning "File extension is $apmDLL instead of .dll"}
    Write-Output "√ Added avs2pipemod option: $apmDLL`r`n"
} else {
    $apmDLL="X:\Somewhere\avisynth.dll"
    Write-Output "Skipped selection procedure for Avs2pipemod, AVS dynamic-link library will be set to $apmDLL"
}
#「Bootstrap G2」Importing required config.ini by SVFI. !No frame interpolation in default!
if ($IMPchk -eq "e") {
    Write-Warning "This script will disable frame interpolation by automatically replcing a line: target_fps=<ffprobe detected fps>`r`This is to make the frames cohesive with encoding fps generated for x264/5. Replace both target_fps & x264/5Par's --fps manually if interpolation is desired."
    Read-Host "`r`nHit Enter to proceed open a window to [rendering-configuration.ini] for SVFI, it may pop up at rear of current window.`r`ni.e. under Steam distro: X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"
    $olsINI=whereisit
    $INIchk=(Get-ChildItem $olsINI).Extension #Report error if file extension is not .ini
    if (($INIchk -eq ".ini") -eq $false) {Write-Warning "File extension is $olsINI instead of .ini"}
    Write-Output "√ Added SVFI option: $olsINI`r`n"
} else {
    $olsINI="X:\Somewhere\SVFI-render-customize.ini"
    Write-Output "Skipped selection procedure for SVFI, config ini file will be set to $olsINI"
}
#「Bootstrap H」Importing a video file for ffprobe to check under 4 circs: VS(1) route, AVS(2) routes, multi-encoding mode(1)
if (($mode -eq "m") -or (($IMPchk -ne "a") -and ($IMPchk -ne "e"))) {
    Do {$continue="n"
        Read-Host "`r`nnHit Enter to proceed open a window to [import a source video sample] for ffprobe to analyze. This is due to the fact that .vpy, .avs input source are not videos"
        $impEXTs=whereisit
        if ((Read-Host "[Assure] type of file input $impEXTs is video [Y: Confirm | N: Cancel and re-input]") -eq "y") {$continue="y"; Write-Output "Continue"} else {Write-Output "Rework"}
    } While ($continue -eq "n")
} else {$impEXTs=$vidIMP}

if ($impEXTs.Contains(".mov")) {
    $is_mov=$true;  Write-Output "视频 $impEXTs 的封装格式为MOV`r`n"
} else {
    $is_mov=$false; Write-Output "视频 $impEXTs 的封装格式非MOV`r`n"
}

#「Bootstrap I」Locate ffprobe
Read-Host "Hit Enter to proceed open a window to [locate ffprobe.exe]"
$fprbPath=whereisit

#「ffprobeA2」Begin analyze sample video. #「ffprobeA2」Due to people tends to use MKV files' NUMBER_OF_FRAMES; NUMBER_OF_FRAMES-eng & etc. tagging, some MKV files ends up not having data on NUMBER_OF_FRAMES tag (at CSV's tag 24,25), therefore a fallback operation by readong all of these values is needed
#             And due to the differently implemented MOV container, the stream_tags are completly unusable and causes errors
#「ffprobeB2」Read with Import-CSV module and map them as an array, header is needed as ffprobe generates headless CSV by default A~F, A file is created because there is currently no method to parse value wihtout exporting CSV to file, and for debugging (swap Remove-Item to Notepad) purpose
#             Due to ffprobe writes the title "stream" at beginning of CSV, the header A is automatically ignored and the rest value are +1 in order
#             e.g.: $parsProbe = "D:\ffprobe.exe -i `"F:\Asset\Video\BDRip私种\[Beatrice-Raws] Anne Happy [BDRip 1920x1080 x264 FLAC]\[Beatrice-Raws] Anne Happy 01 [BDRip 1920x1080 x264 FLAC].mkv`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#             e.g.: $parsProbe = "D:\ffprobe.exe -i `"N:\SolLevante_HDR10_r2020_ST2084_UHD_24fps_1000nit.mov`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
#                   Invoke-Expression $parsProbe > "C:\temp_v_info.csv"
#                   Notepad "C:\temp_v_info.csv"
Switch ($is_mov) {
    $true {
        [String]$parsProbe = $fprbPath+" -i `"$impEXTs`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries -of csv"
        Invoke-Expression $parsProbe > "C:\temp_v_info_is_mov.csv" #File is saved to C drive because most Windows PC has only has 1 disk
        $ffprobeCSV = Import-Csv "C:\temp_v_info_is_mov.csv" -Header A,B,C,D,E,F,G,H,I
    }
    $false{
        [String]$parsProbe = $fprbPath+" -i `"$impEXTs`" -select_streams v:0 -v error -hide_banner -show_streams -show_entries stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng -of csv"
        Invoke-Expression $parsProbe > "C:\temp_v_info.csv"        #File is saved to C drive because most Windows PC has only has 1 disk
        $ffprobeCSV = Import-Csv "C:\temp_v_info.csv" -Header A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,AA
    }
}
if     (Test-Path "C:\temp_v_info.csv")        {Remove-Item "C:\temp_v_info.csv"}
elseif (Test-Path "C:\temp_v_info_is_mov.csv") {Remove-Item "C:\temp_v_info_is_mov.csv"}

#「ffprobeB3」Filling x265's option --subme
$x265subme=x265submecalc -CSVfps $ffprobeCSV.H
Write-Output "√ Added x265 option: $x265subme"

#「ffprobeB4」Filling x264/5's option --keyint
$keyint=keyintcalc -CSVfps $ffprobeCSV.H
Write-Output "√ Added x264/5 option: $keyint"

$WxH="--input-res "+$ffprobeCSV.B+"x"+$ffprobeCSV.C+""
$color_mtx="--colormatrix "+$ffprobeCSV.F
$trans_chrctr="--transfer "+$ffprobeCSV.G
if ($ffprobeCSV.F -eq "unknown") {$avc_mtx="--colormatrix undef"} else {$avc_mtx=$color_mtx} #x264: ×--colormatrix unknown √--colormatrix undef
if ($ffprobeCSV.G -eq "unknown") {$avc_tsf="--colormatrix undef"} else {$avc_tsf=$trans_chrctr} #x264: ×--transfer unknown    √--transfer undef
$fps="--fps "+$ffprobeCSV.H
$fmpgfps="-r "+$ffprobeCSV.H
Write-Output "√ Added x264 options: $fps $WxH`r`n√ Added x265 options: $color_mtx $trans_chrctr $fps $WxH`r`n√ Added ffmpeg options: $fmpgfps`r`n"

#「ffprobeC1」Automatically replacing SVFI render configuratiion's target_fps line, then export as new file. rote SVFI only
if ($IMPchk -eq "e") {
    $iniEXP="C:\bbenc_svfi_targetfps_mod_"+(Get-Date).ToString('yyyy-MM-dd.hh-mm-ss')+".ini"
    $olsfps="target_fps="+$ffprobeCSV.H
    $iniCxt=Get-Content $olsINI
    $iniTgt=$iniCxt | Select-String target_fps | Select-Object -ExpandProperty Line
    $iniCxt | ForEach-Object {$_ -replace $iniTgt,$olsfps}>$iniEXP
    Write-Output "√ Replaced render config file $olsINI 's target_fps line as $olsfps,`r`n√ New render config file is created as $iniEXP"
} else {$iniEXP=$olsINI}

#「ffprobeC2」fetch total frame count with ffprobe, then parse to variable $x265VarA, single-encode mode only
if ($mode -eq "s") {$nbrFrames=framescalc -fcountCSV $ffprobeCSV.I -fcountAUX $ffprobeCSV.AA}
if ($nbrFrames -ne "") {Write-Output "√ Added x264/5 option: $nbrFrames"}
else {Write-Warning "× Total frame count tag is missing, Leaving blank on x264/5 option --frames, the drawback is ETA information will be missing during encoding (estimation of finish time)"}

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
        yuva444p10le{Write-Output "Detecting colorspace & bitdepth[yuv444p 10bit]"; $avsCSP="-csp i444"; $avsD="-depth 10"; $encCSP="--input-csp i444"; $encD="--input-depth 10"; $ffmpegCSP="-pix_fmt yuv444p10le"}
        yuva444p12le{Write-Output "x265-only colorspace & bitdepth[yuv444p 12bit]"; $avsCSP="-csp i444"; $avsD="-depth 12"; $encCSP="--input-csp i444"; $encD="--input-depth 12"; $ffmpegCSP="-pix_fmt yuv444p12le"}
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
        default {Write-Error "`r`n× Bad input, try again"}
    }
} While ($ENCops -eq "")
$encEXT=$x265Path+$x264Path
Write-Output "√ Selected $encEXT"

#「Bootstrap K1」Select multiple ways of specifying exporting filenames, episode variable $serial works at lower loop structure
$vidEXP=[io.path]::GetFileNameWithoutExtension($impEXTs)
Do {$switchOPS=""
    $switchOPS=Read-Host "`r`nChoose how to specify filename of encoding exports [A: Copy from an existing file | B: Input manually | C: $vidEXP]"
    if  (($switchOPS -ne "a") -and ($switchOPS -ne "b") -and ($switchOPS -ne "c")) {Write-Error "`r`n× Bad input, try again"}
} While (($switchOPS -ne "a") -and ($switchOPS -ne "b") -and ($switchOPS -ne "c"))

if (($switchOPS -eq "a") -or ($switchOPS -eq "b")) {$vidEXP = setencoutputname($mode, $switchOPS)}
else {Write-Output "√ Added exporting filename $vidEXP`r`n"}

#「Bootstrap K2」Select container file export format for x264 downstream（Default .hevc for x265 downstream）
if ($ENCops -eq "b") {$vidFMT=""
    Do {Switch (Read-Host "「x264 downstream」Select container format for file export`r`n[A: MKV | B: MP4 | C: FLV]`r`n") {
            a {$vidFMT=".mkv"} b {$vidFMT=".mp4"} c {$vidFMT=".flv"} Default {Write-Error "`r`n× Bad input, try again"}
        }
    } While ($vidFMT -eq "")
} elseif ($ENCops -eq "a") {$vidFMT=".hevc"}

#「Bootstrap L, M」1: Specify file extention based on x264-5. 2: For x265, add pme/pools based on cpu core count & motherboard node count
if ($ENCops -eq "b") {
    Do {$PICKops=$x264ParWrap=""
        Switch (Read-Host "Select an x264 preset [A: General purpose custom | B: Stock footage for editing]") {
            a {$x264ParWrap=avcparwrapper -PICKops "a"; Write-Output "`r`n√ Selected General-purpose preset"}
            b {$x264ParWrap=avcparwrapper -PICKops "b"; Write-Output "`r`n√ Selected Stock-footage preset"}
            default {Write-Warning "Bad input, try again"}
        }
    } While ($x264ParWrap -eq "")
    Write-Output "√ Defined x264 options: $x264ParWrap"
}
elseif ($ENCops -eq "a") {
    $pme=$pool=""
    $procNodes=0
    [int]$cores=(wmic cpu get NumberOfCores)[2]
    if ($cores -gt 21) {$pme="--pme"; Write-Output "√ Detecting processor's core count reaching 22, added x265 option: --pme"}

    $pools=poolscalc
    if ($pools -ne "") {Write-Output "√ Added x265 option: $pools"}

    Do {$PICKops=$x265ParWrap=""
        Switch (Read-Host "`r`nSelect an x265 preset [A: General purpose custom | B: High-compression film | C: Stock footage for editing | D: High-compression anime fansub | E: HEDT anime BDRip coldwar]") {
            a {$x265ParWrap=hevcparwrapper -PICKops "a"; Write-Output "`r`n√ Selected General-purpose preset"}
            b {$x265ParWrap=hevcparwrapper -PICKops "b"; Write-Output "`r`n√ Selected HC-film preset"}
            c {$x265ParWrap=hevcparwrapper -PICKops "c"; Write-Output "`r`n√ Selected ST-footage preset"}
            d {$x265ParWrap=hevcparwrapper -PICKops "d"; Write-Output "`r`n√ Selected HC-AnimeFS preset"}
            e {$x265ParWrap=hevcparwrapper -PICKops "e"; Write-Output "`r`n√ Selected HEDT-ABC preset"}
            default {Write-Warning "Bad input, try again"}
        }
    } While ($x265ParWrap -eq "")
    Write-Output "√ Defined x265 options: $x265ParWrap"
}

#「Bootstrap N」Activate when using x264 that supports Film grain optimization
#Do {$x264fgo=$FGOops=""
#    Switch (Read-Host "Select whether x264 [A: Support | B: Doesn't support] high frequency singal quantity based rate distorstion optimization (--fgo), this feature is outside of AVC standard") {
#        a {$FGOops="A";Write-Output "`r`nAltering to better RDO strategy"; $x264fgo="--fgo 15"}
#        b {$FGOops="B";Write-Output "`r`nKeeping currect RDO strategy";    $x264fgo=""}
#        default {Write-Warning "`r`n× Bad input, try again"}
#    }
#} While ($FGOops -eq "")

Set-PSDebug -Strict
$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #export batch file w/ utf-8NoBOM text codec

#Note: Inport file variable: $impEXTs; Export file variable: $fileEXPpath
#「Initialize」$ffmpegPar-ameters variable contains no trailing spaces
#「Limitation」$ffmpegPar-ameters can only be added after all of file-imported option ("-i")s are written, & ffmpeg option "-hwaccel" must be written before of "-i". This further increases the string reallocation work & amount of variables needed to assemble ffmpeg commandline
$ffmpegParA="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -an -f yuv4mpegpipe -strict unofficial" #Step 2 already addes "- | -" for pipe operation. Therefore there is no need to add it here
$ffmpegParB="$ffmpegCSP $fmpgfps -loglevel 16 -y -hide_banner -c:v copy" #The ffmpeg commandline to generate temporary MP4. This workaround enables ffmpeg to multiplex .mp4 instead of .hevc to .mkv
$vspipeParA="--y4m"
$avsyuvParA="$avsCSP $avsD"
$avsmodParA="`"$apmDLL`" -y4mp" #Note: avs2pipemod uses "| -" instead of other tools' "- | -" pipe commandline (leave upstream/leftside "-" blank). y4mp, y4mt, y4mb represents progressive, top-field-1st interlace, bottom-field-1st interlace. This script does not bother interlaced sources to lower program complexity
$olsargParA="-c `"$iniEXP`" --pipe-out" #Note: svfi doesn't support y4m pipe

#「Initialize」x265Par-ameters
if ($IMPchk -eq "e") {
    $x265y4m=$x264y4m=""; Write-Output "√ SVFI doesn't support yuv-for-mpeg pipe, configuring downstream x264, x265 to raw pipe format"
} else {
    $x265y4m="--y4m"
    $x264y4m="--demuxer y4m" #x264，x265 has different option writing on yuv-for-mpeg demultiplexer
}
$x265ParA="$encD $x265subme $color_mtx $trans_chrctr $fps $WxH $encCSP $pme $pools $keyint $x265ParWrap $y4m -"
$x264ParA="$encD $avc_mtx $avc_tsf $fps $WxH $encCSP $keyint $x264ParWrap $y4m -"
$x265ParA=$x265ParA -replace "  ", " " #Remove double space caused by empty variables, eventhough double space doesn't really affect execusion
$x264ParA=$x264ParA -replace "  ", " "

#「Initialize」ffmpeg, vspipe, avs2yuv, avs2pipemod Variable optoins, multi-encoding mode requires different filename and other attributes to separate tasks, therefore all Var-iables will first be loop-assigned
if ($mode -eq "s") {
    $ffmpegVarA=$vspipeVarA=$avsyuvVarA=$avsmodVarA=$olsargVarA="-i `"$impEXTs`"" #Upstream Vars
    $x265VarA=$x264VarA="$nbrframes --output `"$fileEXPpath$vidEXP`"" #Downstream Vars
}

#Iteration begins, carry as any axis reaches letter 27. Switch occupies temp-variable $_ which cannot be used to initialize this loop. Counts as a 3-digit twenty-hexagonal
$ffmpegVarSChar=$vspipeVarSChar=$avsyuvVarSChar=$avsmodVarSChar=$olsargVarSChar=$x265VarNosChar=$x264VarNosChar=$encCallNosChar=$vidEXX=@()
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
    $olsargVarSChar+="@set `"avsmodVar"+$sChar+"=-i `"video-to-encode"+"_"+"$sChar.mkv`" -t bbenc_run_$sChar`"`n"

    $x265VarNosChar+="@set `"x265Var"+$sChar+"=--output `"$fileEXPpath$tempMuxOut`"`"`n"
    $x264VarNosChar+="@set `"x264Var"+$sChar+"=--output `"$fileEXPpath$tempMuxOut`"`"`n"
    $encCallNosChar+="call enc_$s.bat`n"

    $x+=1 #The loop automatically applies $s+=1, but manual application is needed for debugging
}
#Harvest array datatype of ffmpeg & similar tools' generated commandlines. Each commandline supplies information needed for individual encode batch
[string]$ffmpegVarWrap=$ffmpegVarSChar;$ffmpegVarWrap=$ffmpegVarWrap -replace " @set", "@set" #Convert back to string will result in " @set xxx", therefore replacing back to "@set xxx"
[string]$vspipeVarWrap=$vspipeVarSChar;$vspipeVarWrap=$vspipeVarWrap -replace " @set", "@set"
[string]$avsyuvVarWrap=$avsyuvVarSChar;$avsyuvVarWrap=$avsyuvVarWrap -replace " @set", "@set"
[string]$avsmodVarWrap=$avsmodVarSChar;$avsmodVarWrap=$avsmodVarWrap -replace " @set", "@set"
[string]$olsargVarWrap=$olsargVarSChar;$olsargVarWrap=$olsargVarWrap -replace " @set", "@set"
[string]$x265VarWrap = $x265VarNosChar;$x265VarWrap = $x265VarWrap   -replace " @set", "@set"
[string]$x264VarWrap = $x264VarNosChar;$x264VarWrap = $x264VarWrap   -replace " @set", "@set"
[string]$encCallWrap = $encCallNosChar;$encCallWrap = $encCallWrap   -replace " call", "call"

#「Generate the controller batch」
$ctrl_gen="
chcp 65001
REM 「Compatible with UTF-8」opt-out from ANSI code page
REM 「Safe for with multiple runs」Achieved by set+endlocal, works both at stopping during encoding and controlling batch
REM 「Startup」Disable prompt input display, 5s sleep

@echo off
timeout 5
setlocal

REM 「Non-std exiting」Clean up used variables with taskkill /F /IM cmd.exe /T. Otherwise it may cause variable contamination

@echo 「Non-std exits」cleanup with `"taskkill /F /IM cmd.exe /T`" is necessary to prevent residual variable's presence from previously ran sripts.
@echo. && @echo --Starting multi-batch-enc workflow v2--

REM 「ffmpeg debug」Delete -loglevel 16
REM 「-thread_queue_size small error」Specity ffmpeg option -thread_queue_size<memory bandwidth (Kbps) per core>, but better to replace ffmpeg
REM 「ffmpeg, vspipe, avsyuv, avs2pipemod fixed Parameters」

@set `"ffmpegParA="+$ffmpegParA+"`"
@set `"vspipeParA="+$vspipeParA+"`"
@set `"avsyuvParA="+$avsyuvParA+"`"
@set `"avsmodParA="+$avsmodParA+"`"
@set `"olsargParA="+$olsargParA+"`"

REM 「ffmpeg, vspipe, avsyuv, avs2pipemod Variable optoins」

"+$ffmpegVarWrap+"
"+$vspipeVarWrap+"
"+$avsyuvVarWrap+"
"+$avsmodVarWrap+"
"+$olsargVarWrap+"

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