cls #Dev's Github: https://github.com/iAvoe
Read-Host "This program imports all tracks detected instead of manually selecting specific tracks to import under multi-track files; to import manually, use the follwing commandline to dump all streams inside, then run this program to import individually:`r`n`"ffmpeg -dump_attachment:<v/a/s/t> `"outfile`" -i infile.mkv`"`r`nPress Enter to continue..."

function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #Checking if input filename compliants to Windows file naming scheme

Function whereisit($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a file
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #Starting path set to Desktop
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName} #Killing failed inputs with if statement
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #Opens a System.Windows.Forms GUI to pick a folder/path/dir
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ SelectedPath = [Environment]::GetFolderPath($startPath) } #Starting path set to Desktop
    #Intercepting failed inputs with if statement
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #Root directory always have a "\" in return, whereas a folder/path/dir doesn't. Therefore an if statement is used to add "\" when needed
    if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}
    return $endPath
}
#3-in-1 large function, diverted input file to α: multiplexed file, β: non-std multiplexed file, γ: demultiplexed stream. Detect α, β with ffprobe, γ with GetExtension. Stop on error for irrevelant file types;finally generate all the required ffmpeg -map ?:? & -c:? copy options in a multicasting fashion
Function addcopy {
    Param ([Parameter(Mandatory=$true)]$fprbPath, [Parameter(Mandatory=$true)]$StrmPath, [Parameter(Mandatory=$true)]$mapQTY,[Parameter(Mandatory=$true)]$vcopy)
    $DebugPreference="Continue" #Cannot use Write-Output/Host or " " inside a function as it would trigger a value return, modify Write-Debug instead
    $result=@()
    $mrc=$vrc=$arc=$src=$trc=[IO.Path]::GetExtension($StrmPath) #Only get file extension, which prevents filename accidentally matches to detection statements. Get-ChildItem is incompetent for getting .hevc steams' extension, which is useless
    #「Detection」find out if mux includes video+audio+subtitle+font
    if (($mrc -match "mkv") -or ($mrc -match "mp4") -or ($mrc -match "mov") -or
        ($mrc -match "f4v") -or ($mrc -match "flv") -or ($mrc -match "avi") -or
        ($mrc -match "m3u") -or ($mrc -match "m3u8") -or ($mrc -match "mxv")) {
        Write-Debug "? Possibility α:  Multiplex/encapsulation for video+audio+subtitle+font`r`n"
        #「ffprobe」detect a track types in a  multiplexed file
        #Some file has deleted codec_tag_string, therefore using codec_name or fallback
        $VProbe=$fprbPath+" -i '$StrmPath' -select_streams v -v error -hide_banner -show_entries stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags= -of csv"
        Invoke-Expression $VProbe > "C:\temp_mv_info.csv" #ffprobe generates a CSV with: stream,<index>,<codec_tag_string>
        $AProbe=$fprbPath+" -i '$StrmPath' -select_streams a -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $AProbe > "C:\temp_ma_info.csv" #Imported CSV is: A=stream,B=<index>,C=<codec_tag_string>
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams s -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $SProbe > "C:\temp_ms_info.csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams t -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $SProbe > "C:\temp_mt_info.csv"

        if (Test-Path "C:\temp_mv_info.csv") {$Vcsv=Import-Csv "C:\temp_mv_info.csv" -Header A,B,C,D; Remove-Item "C:\temp_mv_info.csv"} #ffmpeg demands total frame count, or refuses to write mkv encapsulation
        if (Test-Path "C:\temp_ma_info.csv") {$Acsv=Import-Csv "C:\temp_ma_info.csv" -Header A,B,C; Remove-Item "C:\temp_ma_info.csv"}
        if (Test-Path "C:\temp_ms_info.csv") {$Scsv=Import-Csv "C:\temp_ms_info.csv" -Header A,B,C; Remove-Item "C:\temp_ms_info.csv"}
        if (Test-Path "C:\temp_mt_info.csv") {$Tcsv=Import-Csv "C:\temp_mt_info.csv" -Header A,B,C; Remove-Item "C:\temp_mt_info.csv"} #Test-Path is to prevent Remove-Item stop on file-missing-error

        if (($Vcsv.C -match "0") -or ($Vcsv.C -eq "")) {Write-Debug "α! Missing video codec_tag_string, fallback to codec_name"; $vrc=$Vcsv.B} else {$vrc=$Vcsv.C} #Detect if code_name_tag data is valid
        $vfc=$Vcsv.D
        if (($Acsv.C -match "0") -or ($Acsv.C -eq "")) {Write-Debug "α! Missing audio codec_tag_string, fallback to codec_name"; $arc=$Acsv.B} else {$arc=$Acsv.C}
        if (($Scsv.C -match "0") -or ($Scsv.C -eq "")) {Write-Debug "α! Missing subtitle codec_tag_string, fallback to codec_name"; $src=$Scsv.B} else {$src=$Scsv.C}
        if (($Tcsv.C -match "0") -or ($Tcsv.C -eq "")) {Write-Debug "α! Missing font codec_tag_string, fallback to codec_name"; $trc=$Tcsv.B} else {$trc=$Tcsv.C}
        #Write-Debug "vrc: $vrc "
        #Write-Debug $vrc.GetType()
        if (($vrc -eq "") -or ($vrc -eq $null)) {Write-Debug "`r`nα× No video stream found on $vrc"}
        else {
            if (($vrc -match "hevc") -or ($vrc -match "h265") -or ($vrc -match "avc") -or
                ($vrc -match "h264") -or ($vrc -match "cfhd") -or ($vrc -match "ap4x") -or
                ($vrc -match "apcn") -or ($vrc -match "hev1") -or ($vrc -match "vp09") -or
                ($vrc -match "vp9")) {
                Write-Debug "`r`nα√ Video supports multiplexing: $vrc"
                if (($vrc -match "ap4x") -or ($vrc -match "apcn")) {Write-Warning "Detecting ProRes 422 / 4444XQ video streams. Supported by MOV/QTFF, MXF multiplexing container"}
                if (($vrc -match "vp09") -or ($vrc -match "vp9")) {Write-Warning "Detecting VP9 video stream. Supported by MKV, MP4, *OGG, WebM multiplexing container"}
            } else {Write-Warning "`r`nα? Video may supports multiplexing: $vrc"}
            if ($vcopy -eq "y") {$result+="-r $vfc -c:v copy "} else {Write-Warning "ffmpeg option -c:v copy & -r was written in previous import, preventing adding video stream for this run"}
        }
        #Write-Debug "arc: $arc"
        #Write-Debug $arc.GetType()
        if (($arc -eq "") -or ($arc -eq $null)) {Write-Debug "`r`nα× No audio stream found on $arc"}
        else {
            if (($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or 
                ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or 
                ($arc -match "wav") -or ($arc -match "pcm") -or ($arc -match "lpcm") -or
                ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
                Write-Debug "`r`nα√ Audio supports multiplexing: $arc"
                if ($arc -match "ape") {Write-Error "α× No multiplex container available for MonkeysAudio/APE format"; pause; exit}
                if ($arc -match "flac") {Write-Warning "Detecting FLAC audio stream. Not supported by MOV/QTFF, MXF multiplexing container"}
                if ($arc -match "alac") {Write-Warning "Detecting ALAC audio stream, Not supported by MXF multiplexing container"}
            } else {Write-Warning "`r`nα? Audio may supports multiplexing: $arc"}
            $result+="-c:a copy "
        }
        #Write-Debug "src: $src"
        #Write-Debug $src.GetType()
        if (($src -eq "") -or ($src -eq $null)) {Write-Debug "`r`nα× No subtitle track found on $src"}
        else {
            if (($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
                Write-Debug "`r`nα√ Subtitle supports multiplexing: $src"
                if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "Detecting ASS/SSA subtitle track, only supported by MKV"}
            } else {Write-Warning "`r`nα? Subtitle may supports multiplexing: $src"}
            $result+="-c:s copy "
        }
        #Write-Debug "trc: $trc"
        #Write-Debug $trc.GetType()
        if (($trc -eq "") -or ($trc -eq $null)) {Write-Debug "`r`nα× No font track found on $trc"}
        else {
            if (($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {Write-Warning "`r`nα! Only MKV supports multiplexing font $trc"}
            $result+="-c:t copy "
        }

        if ($result.Count -lt 1) {Write-Error "α× No stream found in multiplex container $StrmPath"; pause; exit}
        return $result
    }elseif(
        ($mrc -match "m4a") -or ($mrc -match "mka") -or ($mrc -match "mks")) {
        Write-Debug "? Possibility β: Multiplex file format made for non-video streams`r`n"
        $AProbe=$fprbPath+" -i '$StrmPath' -select_streams a -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams s -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams t -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $AProbe > "C:\temp_na_info.csv"
        Invoke-Expression $SProbe > "C:\temp_ns_info.csv"
        Invoke-Expression $SProbe > "C:\temp_nt_info.csv"
        if (Test-Path "C:\temp_na_info.csv") {$Acsv=Import-Csv "C:\temp_na_info.csv" -Header A,B,C; Remove-Item "C:\temp_na_info.csv"}
        if (Test-Path "C:\temp_ns_info.csv") {$Scsv=Import-Csv "C:\temp_ns_info.csv" -Header A,B,C; Remove-Item "C:\temp_ns_info.csv"}
        if (Test-Path "C:\temp_nt_info.csv") {$Tcsv=Import-Csv "C:\temp_nt_info.csv" -Header A,B,C; Remove-Item "C:\temp_nt_info.csv"}

        if (($Acsv.C -match "0") -or ($Acsv.C -eq "")) {Write-Debug "β! Missing audio codec_tag_string, fallback to codec_name"; $arc=$Acsv.B} else {$arc=$Acsv.C}
        if (($Scsv.C -match "0") -or ($Scsv.C -eq "")) {Write-Debug "β! Missing subtitle codec_tag_string, fallback to codec_name"; $src=$Scsv.B} else {$src=$Scsv.C}
        if (($Tcsv.C -match "0") -or ($Tcsv.C -eq "")) {Write-Debug "β! Missing font codec_tag_string, fallback to codec_name"; $trc=$Tcsv.B} else {$trc=$Tcsv.C}
        #Write-Debug "arc: $arc"
        #Write-Debug $arc.GetType()
        if (($arc -eq "") -or ($arc -eq $null)) {Write-Debug "`r`nβ× No audio stream found on $arc"}
        else {
            if (($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or
                ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or
                ($arc -match "wav") -or ($arc -match "pcm") -or ($arc -match "lpcm") -or
                ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
                Write-Debug "`r`nβ√ Audio supports multiplexing: $arc"
                if ($arc -match "ape") {Write-Error "β× No multiplex container available for MonkeysAudio/APE format"; pause; exit}
                if ($arc -match "flac") {Write-Warning "Detecting FLAC audio stream. Not supported by MOV/QTFF, MXF multiplexing container"}
                if ($arc -match "alac") {Write-Warning "Detecting ALAC audio stream, Not supported by MXF multiplexing container"}
            } else {Write-Warning "`r`nβ? Audio may supports multiplexing: $arc"}
            $result+="-c:a copy "
        }
        #Write-Debug "src: $src"
        #Write-Debug $src.GetType()
        if (($src -eq "") -or ($src -eq $null)) {Write-Debug "`r`nβ× No subtitle track found on $src"}
        else {
            if (($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
                Write-Debug "`r`nα√ Subtitle supports multiplexing: $src"
                if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "Detecting ASS/SSA subtitle track, only supported by MKV"}
            } else {Write-Warning "`r`nα? Subtitle may supports multiplexing: $src"}
            $result+="-c:s copy "
        }
        #Write-Debug "trc: $trc"
        #Write-Debug $trc.GetType()
        if (($trc -eq "") -or ($trc -eq $null)) {Write-Debug "`r`nβ× No font track found on $trc"}
        else {
            if (($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {Write-Warning "`r`nα! Only MKV supports multiplexing font $trc"}
            $result+="-c:t copy "
        }
        
        if ($result.Count -lt 1)  {Write-Error "β× No stream found in multiplex container $StrmPath"; pause; exit}
        return $result[$mapQTY]
    }else { Write-Debug "? Possibility γ: Raw streams`r`n"
        if (($vrc -match "hevc") -or ($vrc -match "h265") -or ($vrc -match "avc") -or
            ($vrc -match "h264") -or ($vrc -match "cfhd") -or ($vrc -match "ap4x") -or
            ($vrc -match "apcn") -or ($vrc -match "hev1") -or ($vrc -match "vp09") -or
            ($vrc -match "vp9")) {
            $VProbe=$fprbPath+" -i '$StrmPath' -select_streams v -v error -hide_banner -show_entries stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags= -of csv"
            Invoke-Expression $VProbe > "C:\temp_ov_info.csv" #ffprobe generates a CSV with: stream,<index>,<codec_tag_string>
            if (Test-Path "C:\temp_ov_info.csv") {$Vcsv=Import-Csv "C:\temp_ov_info.csv" -Header A,B,C,D; Remove-Item "C:\temp_ov_info.csv"}
            $vfc=$Vcsv.D #ffmpeg demands total frame count, or refuses to write mkv encapsulation
            if ($vcopy -eq "y") {$result+="-r $vfc -c:v copy "} else {Write-Warning "ffmpeg option -c:v copy & -r was written in previous import, preventing adding video stream for this run"}
            if ((($MUXops -match "mkv") -and ($vrc -match "hevc")) -or (($MUXops -match "mkv") -and ($vrc -match "h265"))) {Write-Error "γ× ffmpeg refuses to multiplex raw hevc/h265 to mkv (missing pts), use this script to multiplex to mp4 first"; pause; exit}
            if ((($MUXops -match "mkv") -and ($vrc -match "hevc")) -or (($MUXops -match "mkv") -and ($vrc -match "h265"))) {Write-Error "γ× ffmpeg refuses to multiplex raw avc/h264 to mkv (missing pts), use this script to multiplex to mp4 first"; pause; exit}
            Write-Debug "`r`nγ√ $MUXops supports multiplexing video stream: $vrc`r`n"
            if (($vrc -match "ap4x") -or ($vrc -match "apcn")) {Write-Warning "Detecting ProRes 422 / 4444XQ video streams. Supported by MOV/QTFF, MXF multiplexing container"}
            if (($vrc -match "vp09") -or ($vrc -match "vp9")) {Write-Warning "Detecting VP9 video streams. Supported by MKV, MP4, *OGG, WebM multiplexing container"}
        } elseif(
            ($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or
            ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or
            ($arc -match "wav") -or ($arc -match ".pcm") -or ($arc -match ".lpcm") -or
            ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
            $result+="-c:a copy "
            Write-Debug "`r`nγ√ $MUXops supports multiplexing audio stream: $arc`r`n"
            if ($arc -match "ape") {Write-Error "β× No multiplex container available for MonkeysAudio/APE format"; pause; exit}
            if ($arc -match "flac") {Write-Warning "Detecting FLAC audio stream. Not supported by MOV/QTFF, MXF multiplexing container"}
            if ($arc -match "alac") {Write-Warning "Detecting ALAC audio stream, Not supported by MXF multiplexing container"}
        } elseif(
            ($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
            $result+="-c:s copy "
            if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "Detecting ASS/SSA subtitle track, only supported by MKV"}
            Write-Debug "`r`nγ√ $MUXops supports multiplexing subtitle track: $src`r`n"
        } elseif(
            ($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {
            $result+="-c:t copy "
            Write-Warning "`r`nγ! Only MKV supports multiplexing font $trc`r`n"
        } else{Write-Error "`r`nγ× Could not add ffmpeg option as single stream file input is out of supported range mkv/mp4/mov/f4v/flv/avi, m4a/mka/mks, hevc/avc/cfhd/ap4x/apcn, aac/ogg/alac/dts/mp3/wma/pcm/lpcm/ape, srt/ass/ssa`r`n"; pause}
        return $result
    }
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

Write-Output "To manually check all streams/tracks within a multiplex format, open w/ mediainfo & select`"view`", or check all of audio tracks w/: ffprobe -i [src] -select_streams a -v error -hide_banner -show_streams  -of ini > `"X:\1.txt`"`r`n"
Write-Output "To export all AAC audio tracks (commonly inside a .mp4 file): ffmpeg -i [src] -vn -c:a:0 copy `"X:\folder\audOut.aac`" `r`nffmpeg -i [src] -vn -c:a:0 copy `"X:\folder\audOut2.aac`" `r`nffmpeg -i [src] -vn -c:a:0 copy `"X:\folder\audOut3.aac`"`r`n"
Write-Output "To export all subtitles (check mediainfo for proper file extension): ffmpeg -i [src] -vn -an -c:s:0 copy `"X:\folder\subOut1.ass`" `r`nffmpeg -i [src] -vn -an -c:s:0 copy `"X:\folder\subOut2.ass`" `r`nffmpeg -i [src] -vn -an -c:s:0 copy `"X:\folder\subOut3.ass`"`r`n"
Write-Output "To re-multiplex streams/tracks from a multiplexed source:`r`nffmpeg -i [src] -c:v copy -c:a:0 copy -c:a:1 copy -c:a:0 copy -c:s:0 copy`"X:\folder\export1.mkv`"`r`n"
Write-Output "To re-multiplex streams/tracks in many multiplexed sources:`r`nffmpeg -i [src] -i [src2] -i [src3] -i [src4] -map 1:v -c:v copy -map 2:a -c:a copy -map 2:s -c:s copy -map 3:a -c:a copy -map 3:s -c:s copy -map 4:a -c:a copy -map 4:s -c:s copy `"X:\文件夹\导出2.mkv`" `r`n"
Write-Output "Note: this script works within a limited range of stream formats to reduce coding complexities`r`nmkv/mp4/mov/f4v/flv/avi, m4a/mka/mks, hevc/avc/cfhd/ap4x/apcn, aac/ogg/alac/dts/mp3/wma/pcm/lpcm, srt/ass/ssa. ttf/ttc/otf`r`n"
Set-PSDebug -Strict

#「Bootstrap」Locate all pathes needed
Read-Host "Press Enter to open a selecting window to locate [Path to export multiplexing batch], it may pop up at rear of current window"
$exptPath=whichlocation
Read-Host "Press Enter to open a selecting window to locate [Path to export multiplexing result], it may pop up at rear of current window"
$muxPath=whichlocation
Read-Host "Press Enter to open a selecting window to locate [ffprobe.exe]"
$fprbPath=whereisit

#「Bootstrap」Initialize a variable to temporarily store ffmpeg import options, & another one to aggregate multiple instances from the former
$StrmIMPAgg=$StrmParAgg=""
Write-Warning "Only the 1st video stream imported in this script will get it's `"-c:v copy`" option generated, make sure to import the video wanted to multipelx first`r`n"
$keepAdd=$vcopy="y" #initialize loop continuity variable, and decision to whether generate "-c:v copy" due to having the same value
$mapQTY=0 #Initialize variable for "ffmpeg's -map" option, which requires to locate to apply operations to which imported file

#「Bootstrap」Loop through addcopy function to enable multi-import works
Read-Host "Press Enter to open a looped selecting window to locate [source files to multiplex]"
While ($keepAdd -eq "y") {
    $StrmPath=whereisit
    $addcopy=addcopy -fprbPath $fprbPath -StrmPath $StrmPath -mapQTY $mapQTY -vcopy $vcopy
    if ($addcopy -match "-c:v copy") {$vcopy="n"} #The 1st video stream gets it's -c:v copy option, and then trigger kill-switch variable $vcopy

    $StrmIMPAgg+=" -i `"$StrmPath`"" #Due to ffmpeg demands -map option for multiple imports, and each -map option has to follow with operations like "-c:? copy" accordingly, reorganization work is needed
    $StrmParAgg+="-map "+$mapQTY+" $addcopy" #-map option's variable gets aggregated, note that ffmpeg prohibits the use of single quotes
    
    $mapQTY+=1
    Do {$keepAdd=Read-Host "`r`n√ Generated ffmpeg importing variable: $StrmParAgg `r`n`r`nChoose to [n: END | y: Continue] file importing tasks"
        if ((($keepAdd -eq "y") -eq $false) -and (($keepAdd -eq "n") -eq $false)) {Write-Warning "No option were selected"}
    } While ((($keepAdd -eq "y") -eq $false) -and (($keepAdd -eq "n") -eq $false))
}

$nameIn=[IO.Path]::GetFileNameWithoutExtension($StrmPath) #Initialize the filename for exporting multiplexed files
$nameIn+="_tempMux"
Switch (Read-Host "`r`nChoose how to specify filename of encoding exports [A: Manually input | B: $nameIn]") {
    a {Do {Do {$nameIn = (Read-Host -Prompt "`r`nSpecify filename to export (w/out file extension). E.g., [Zzz] Memories – `$serial (BDRip 1764x972 HEVC)")
                $nameCheck = namecheck($nameIn)
                if ($nameCheck -eq $false) {Write-Warning "Detecting illegal characters / | \ < > : ? * `""}
                elseif ($nameIn -eq 'y') {Write-Warning "Preventing accidental input: y"}
            } While ($nameCheck -eq $false)
        } While ($nameIn -eq 'y')
        Write-Output "√ Filename is compliant to Windows OS`r`n"} #Close chose A
    b {Write-Output "Default filename was choosen"}
    default {Write-Output "Default filename was choosen（default option）"}
}

#Choose a multiplex format. This may get expanded in future with not just ffmpeg (and compatibility check gets improved), which causes $fmpgPath to be duplicated
Do {$MUXops=""
    Switch (Read-Host "`r`nChoose a multiplexing tool+format:`r`n[A: ffmpeg+MP4 (video, audios) | B: ffmpeg+MOV (video, audio) | C: ffmpeg+MKV (video, audios, subtitles, fonts) | D: ffmpeg+MXF (video, audios, subtitles)]") {
        a {$MUXops=".mp4"; Write-Output "`r`nChoosed MP4 - route A. Opening a selection window to [locate ffmpeg]`r`n"; $fmpgPath=whereisit}
        b {$MUXops=".mov"; Write-Output "`r`nChoosed MOV - route B. Opening a selection window to [locate ffmpeg]`r`n"; $fmpgPath=whereisit}
        c {$MUXops=".mkv"; Write-Output "`r`nChoosed MKV - route C. Opening a selection window to [locate ffmpeg]`r`n"; $fmpgPath=whereisit}
        d {$MUXops=".mxf"; Write-Output "`r`nChoosed MXF - route D. Opening a selection window to [locate ffmpeg]`r`n"; $fmpgPath=whereisit}
        default {Write-Warning "Bad input, try again"}
    }
} While ($MUXops -eq "")
Write-Output "√ Selected $fmpgPath`r`n"

#D:\ffmpeg.exe -i "D:\video&audio.mkv" -i "D:\sub1.srt" -i "D:\video2.mp4"  -map 0:v -r 25 -c:v copy  -map 0:a -c:a copy  -map 0:s -c:s copy  -map 0:t -c:t copy  -map 1:s -c:s copy  -map 2:v -r 24000/1000 -c:v copy  "D:\folder\multiplex.mkv"
#$fmpgPath---" "-$StrmIMPAgg---------------------------------------------" "$StrmParAgg-------------------------------------------------------------------------------------------------------------------------------" "-$muxPath+$nameIn+$MUXops
$mux_gen=$fmpgPath+$StrmIMPAgg+" "+$StrmParAgg+" "+"`""+$muxPath+$nameIn+$MUXops+"`"" #Note: ffmpeg prohibits single quotes

#Intercept+dealk with stream/track formats that are not compliant with select multiplexing container
if ((($MUXops -eq ".mp4") -or ($MUXops -eq ".mov") -or ($MUXops -eq ".mxf")) -and ($mux_gen -match "-c:t copy")) {
    Switch (Read-Host "Export format was choosen as MP4/MOV/MXF, but detecting font track multiplexing command(s) `"-c:t copy`".`r`nChoose to [A: remove `"-c:t copy`" | B: replace format to MKV | C: Ignore (not recommended)]") {
        a {$mux_gen -replace "-c:t copy", ""; Write-Output "Deleted"}
        b {$MUXops=".mkv"; Write-Output "Format altered"}
        c {Write-Output "Ignored (default)"}
    }
}

if ((($MUXops -eq ".mp4") -or ($MUXops -eq ".mov")) -and ($mux_gen -match "-c:s copy")) {
    Switch (Read-Host "Export format was choosen as MP4/MOV, but detecting subtitle track multiplexing command(s) `"-c:s copy`".`r`nChoose to [A: remove `"-c:s copy`" | B: replace format to MKV | C: Ignore (not recommended) |`r`nD: Copy just 1 track (alter to -c:s:0 mov_text, low success rate, if there are multiple -c:s copy, then manual redundancy is needed)]") {
        a {$mux_gen -replace "-c:s copy", ""; Write-Output "Deleted"}
        b {$MUXops=".mkv"; Write-Output "Format altered"}
        c {Write-Output "Ignored (default)"}
        d {$mux_gen -replace "-c:s copy", "-c:s:0 mov_text"; Write-Output "Altered"}
    }
}

if (($mux_gen -match "-c:v copy") -eq $false) {Write-Warning "There are no `"-c:v copy`" option found in commandline, the resulting file is likely to have no video stream"}
if (($mux_gen -match "-c:a copy") -eq $false) {Write-Warning "There are no `"-c:a copy`" option found in commandline, the resulting file is likely to have no audio stream"}

$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #Force exporting utf-8NoBOM text codec
$exptPath+="6S.「Multiplexing」.bat.txt"
Write-Output "`r`n  Generating 6S.「Multiplexing」.bat.txt`r`n"
[System.IO.File]::WriteAllLines($exptPath, $mux_gen, $utf8NoBOM) #Force exporting utf-8NoBOM text codec

Write-Output "The file extension is purposfully set to .txt to drive users to open and check again, to edit -map, -c:v copy, -c:a copy, -c:s copy, -c:t copy options, or altering some options similar to -c:a:0 copy to filter undersired streams/tracks`r`nIf audio/subtitle aren't aligned, go to the corresponding -map -c:? copy and add -itoffset<+/-seconds.miliseconds>"
pause