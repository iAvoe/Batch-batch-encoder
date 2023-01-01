cls #开发人员的Github: https://github.com/iAvoe
Read-Host "本程序无法手动选择导入封装中的特定轨道. 否则用以下命令导出所有内容后, 再运行本程序逐一导入:`r`n`"ffmpeg -dump_attachment:<视频v/音频a/字幕s/字体t> `"导出文件名`" -i 导入.mkv`"`r`n按Enter继续..."

function namecheck([string]$inName) {
    $badChars = '[{0}]' -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
    ForEach ($_ in $badChars) {if ($_ -match $inName) {return $false}}
    return $true
} #检测文件名是否符合Windows命名规则, 大批量版不需要

Function whereisit($startPath='DESKTOP') {
    #「启动」启用System.Windows.Forms选择文件的GUI交互窗
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.OpenFileDialog -Property @{ InitialDirectory = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.FileName} #打开选择文件的GUI交互窗, 用if拦截误操作
    return $endPath
}

Function whichlocation($startPath='DESKTOP') {
    #启用System.Windows.Forms选择文件夹的GUI交互窗
    Add-Type -AssemblyName System.Windows.Forms
    $startPath = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{ SelectedPath = [Environment]::GetFolderPath($startPath) } #GUI交互窗锁定到桌面文件夹
    #打开选择文件的GUI交互窗, 用if拦截误操作
    if ($startPath.ShowDialog() -eq "OK") {[string]$endPath = $startPath.SelectedPath}
    #由于选择根目录时路径变量含"\", 而文件夹时路径变量缺"\", 所以要自动判断并补上
    if (($endPath.SubString($endPath.Length-1) -eq "\") -eq $false) {$endPath+="\"}
    return $endPath
}
#3合1大型函数, 分流了甲: 封装文件, 乙: 特殊封装, 丙: 单文件流. 甲-乙用ffprobe测, 丙用GetExtension测, 拦截无关的文件格式, 最终以多线并发的方法生成ffmpeg的-map ?:?, -c:? copy命令
Function addcopy {
    Param ([Parameter(Mandatory=$true)]$fprbPath, [Parameter(Mandatory=$true)]$StrmPath, [Parameter(Mandatory=$true)]$mapQTY,[Parameter(Mandatory=$true)]$vcopy)
    $DebugPreference="Continue" #function里不能用Write-Output/Host,或" "来输出交互信息, 而是修改Write-Debug的运行逻辑属性实现交互
    $result=@()
    $mrc=$vrc=$arc=$src=$trc=[IO.Path]::GetExtension($StrmPath) #过滤掉文件名, 只保留后缀, 防止文件名中含匹配值造成误匹配, 由于Get-ChildItem查不出.hevc所以放弃
    #「检测」视频+音频+字幕+字体封装检测规程
    if (($mrc -match "mkv") -or ($mrc -match "mp4") -or ($mrc -match "mov") -or
        ($mrc -match "f4v") -or ($mrc -match "flv") -or ($mrc -match "avi") -or
        ($mrc -match "m3u") -or ($mrc -match "mxv")) {
        Write-Debug "? 可能性甲: 视音频字幕字体用的封装格式`r`n"
        #「ffprobe」读取封装文件multiplexed file中的音频. 不管导入文件是否封装
        #有的片子删了codec_tag_string, 所以用codec_name做冗余
        $VProbe=$fprbPath+" -i '$StrmPath' -select_streams v -v error -hide_banner -show_entries stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags= -of csv"
        Invoke-Expression $VProbe > "C:\temp_mv_info.csv" #ffprobe生成的csv中: stream,<index>,<codec_tag_string>
        $AProbe=$fprbPath+" -i '$StrmPath' -select_streams a -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $AProbe > "C:\temp_ma_info.csv" #导入的csv中: A=stream,B=<index>,C=<codec_tag_string>
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams s -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $SProbe > "C:\temp_ms_info.csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams t -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $SProbe > "C:\temp_mt_info.csv"

        if (Test-Path "C:\temp_mv_info.csv") {$Vcsv=Import-Csv "C:\temp_mv_info.csv" -Header A,B,C,D; Remove-Item "C:\temp_mv_info.csv"} #ffmpeg要求输入帧数, 否则会阻止封装为mkv
        if (Test-Path "C:\temp_ma_info.csv") {$Acsv=Import-Csv "C:\temp_ma_info.csv" -Header A,B,C; Remove-Item "C:\temp_ma_info.csv"}
        if (Test-Path "C:\temp_ms_info.csv") {$Scsv=Import-Csv "C:\temp_ms_info.csv" -Header A,B,C; Remove-Item "C:\temp_ms_info.csv"}
        if (Test-Path "C:\temp_mt_info.csv") {$Tcsv=Import-Csv "C:\temp_mt_info.csv" -Header A,B,C; Remove-Item "C:\temp_mt_info.csv"} #防止删除不存在的文件导致报错

        if (($Vcsv.C -match "0") -or ($Vcsv.C -eq "")) {Write-Debug "甲! 视频元数据codec_tag_string遭删, 切到备用值codec_name"; $vrc=$Vcsv.B} else {$vrc=$Vcsv.C} #检测code_name_tag是否给出了定义范围内的格式
        $vfc=$Vcsv.D
        if (($Acsv.C -match "0") -or ($Acsv.C -eq "")) {Write-Debug "甲! 音频元数据codec_tag_string遭删, 切到备用值codec_name"; $arc=$Acsv.B} else {$arc=$Acsv.C}
        if (($Scsv.C -match "0") -or ($Scsv.C -eq "")) {Write-Debug "甲! 字幕元数据codec_tag_string遭删, 切到备用值codec_name"; $src=$Scsv.B} else {$src=$Scsv.C}
        if (($Tcsv.C -match "0") -or ($Tcsv.C -eq "")) {Write-Debug "甲! 字体元数据codec_tag_string遭删, 切到备用值codec_name"; $trc=$Tcsv.B} else {$trc=$Tcsv.C}
        #Write-Debug "vrc: $vrc "
        #Write-Debug $vrc.GetType()
        if (($vrc -eq "") -or ($vrc -eq $null)) {Write-Debug "`r`n甲× 视频流 $vrc 不存在"}
        else {
            if (($vrc -match "hevc") -or ($vrc -match "h265") -or ($vrc -match "avc") -or
                ($vrc -match "h264") -or ($vrc -match "cfhd") -or ($vrc -match "ap4x") -or
                ($vrc -match "apcn") -or ($vrc -match "hev1") -or ($vrc -match "vp09") -or
                ($vrc -match "vp9")) {
                Write-Debug "`r`n甲√可封装视频流: $vrc"
                if (($vrc -match "ap4x") -or ($vrc -match "apcn")) {Write-Warning "检测到ProRes 422 / 4444XQ视频流. 仅MOV/QTFF, MXF封装格式支持"}
                if (($vrc -match "vp09") -or ($vrc -match "vp9")) {Write-Warning "检测到VP9视频流. 有MKV, MP4, *OGG, WebM等封装格式支持"}
            } else {Write-Warning "`r`n甲? 不认识/大概能封装视频流: $vrc"}
            if ($vcopy -eq "y") {$result+="-r $vfc -c:v copy "} else {Write-Warning "首个 -c:v copy 以及 -r 命令已被写入, 屏蔽了重复写入"}
        }
        #Write-Debug "arc: $arc"
        #Write-Debug $arc.GetType()
        if (($arc -eq "") -or ($arc -eq $null)) {Write-Debug "`r`n甲× 音频流 $arc 不存在"}
        else {
            if (($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or 
                ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or 
                ($arc -match "wav") -or ($arc -match "pcm") -or ($arc -match "lpcm") -or
                ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
                Write-Debug "`r`n甲√可封装音频流: $arc"
                if ($arc -match "ape") {Write-Error "甲× 没有封装格式支持MonkeysAudio/APE音频"; pause; exit}
                if ($arc -match "flac") {Write-Warning "检测到FLAC音频, MOV/QTFF, MXF封装格式不支持"}
                if ($arc -match "alac") {Write-Warning "检测到ALAC音频, MXF封装格式不支持"}
            } else {Write-Warning "`r`n甲? 不认识/大概能封装音频流: $arc"}
            $result+="-c:a copy "
        }
        #Write-Debug "src: $src"
        #Write-Debug $src.GetType()
        if (($src -eq "") -or ($src -eq $null)) {Write-Debug "`r`n甲× 字幕轨 $src 不存在"}
        else {
            if (($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
                Write-Debug "`r`n甲√可封装字幕轨: $src"
                if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "检测到ASS/SSA字幕, 唯独MKV封装格式支持"}
            } else {Write-Warning "`r`n甲? 不认识/大概能封装字幕轨: $src"}
            $result+="-c:s copy "
        }
        #Write-Debug "trc: $trc"
        #Write-Debug $trc.GetType()
        if (($trc -eq "") -or ($trc -eq $null)) {Write-Debug "`r`n甲× 字体轨 $trc 不存在"}
        else {
            if (($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {Write-Warning "`r`n甲!  .mp4和.mov封装格式不支持字体轨 $trc"}
            $result+="-c:t copy "
        }

        if ($result.Count -lt 1) {Write-Error "甲× 失败: 输入了空的视音频+字幕字体封装文件"; pause; exit}
        return $result
    }elseif(
        ($mrc -match "m4a") -or ($mrc -match "mka") -or ($mrc -match "mks")) {
        Write-Debug "? 可能性乙: 非视频用的封装格式`r`n"
        $AProbe=$fprbPath+" -i '$StrmPath' -select_streams a -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams s -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        $SProbe=$fprbPath+" -i '$StrmPath' -select_streams t -v error -hide_banner -show_entries stream=codec_name,codec_tag_string:disposition=:tags= -of csv"
        Invoke-Expression $AProbe > "C:\temp_na_info.csv"
        Invoke-Expression $SProbe > "C:\temp_ns_info.csv"
        Invoke-Expression $SProbe > "C:\temp_nt_info.csv"
        if (Test-Path "C:\temp_na_info.csv") {$Acsv=Import-Csv "C:\temp_na_info.csv" -Header A,B,C; Remove-Item "C:\temp_na_info.csv"}
        if (Test-Path "C:\temp_ns_info.csv") {$Scsv=Import-Csv "C:\temp_ns_info.csv" -Header A,B,C; Remove-Item "C:\temp_ns_info.csv"}
        if (Test-Path "C:\temp_nt_info.csv") {$Tcsv=Import-Csv "C:\temp_nt_info.csv" -Header A,B,C; Remove-Item "C:\temp_nt_info.csv"}

        if (($Acsv.C -match "0") -or ($Acsv.C -eq "")) {Write-Debug "乙! 音频元数据codec_tag_string遭删, 切到备用值codec_name"; $arc=$Acsv.B} else {$arc=$Acsv.C}
        if (($Scsv.C -match "0") -or ($Scsv.C -eq "")) {Write-Debug "乙! 字幕元数据codec_tag_string遭删, 切到备用值codec_name"; $src=$Scsv.B} else {$src=$Scsv.C}
        if (($Tcsv.C -match "0") -or ($Tcsv.C -eq "")) {Write-Debug "乙! 字体元数据codec_tag_string遭删, 切到备用值codec_name"; $trc=$Tcsv.B} else {$trc=$Tcsv.C}
        #Write-Debug "arc: $arc"
        #Write-Debug $arc.GetType()
        if (($arc -eq "") -or ($arc -eq $null)) {Write-Debug "`r`n乙× 音频流 $arc 不存在"}
        else {
            if (($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or
                ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or
                ($arc -match "wav") -or ($arc -match "pcm") -or ($arc -match "lpcm") -or
                ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
                Write-Debug "`r`n乙√可封装音频流: $arc"
                if ($arc -match "ape") {Write-Error "β× 没有封装格式支持MonkeysAudio/APE音频"; pause; exit}
                if ($arc -match "flac") {Write-Warning "检测到FLAC音频. MOV/QTFF, MXF封装格式不支持"}
                if ($arc -match "alac") {Write-Warning "检测到ALAC音频, MXF封装格式不支持"}
            } else {Write-Warning "`r`n乙? 不认识/大概能封装音频流: $arc"}
            $result+="-c:a copy "
        }
        #Write-Debug "src: $src"
        #Write-Debug $src.GetType()
        if (($src -eq "") -or ($src -eq $null)) {Write-Debug "`r`n乙× 字幕轨: $src 不存在"}
        else {
            if (($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
                Write-Debug "`r`n乙√可封装字幕轨: $src"
                if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "检测到ASS/SSA字幕, 唯独MKV封装格式支持"}
            } else {Write-Warning "`r`n乙? 不认识/大概能封装字幕轨 $src"}
            $result+="-c:s copy "
        }
        #Write-Debug "trc: $trc"
        #Write-Debug $trc.GetType()
        if (($trc -eq "") -or ($trc -eq $null)) {Write-Debug "`r`n乙× 字体轨 $trc 不存在"}
        else {
            if (($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {Write-Warning "`r`n乙!  .mp4和.mov封装格式不支持字体轨 $trc"}
            $result+="-c:t copy "
        }
        
        if ($result.Count -lt 1)  {Write-Error "乙× 失败: 输入了空的音频-字幕封装文件"; pause}
        return $result[$mapQTY]
    }else { Write-Debug "? 可能性丙: 未封装的单文件`r`n"
        if (($vrc -match "hevc") -or ($vrc -match "h265") -or ($vrc -match "avc") -or
            ($vrc -match "h264") -or ($vrc -match "cfhd") -or ($vrc -match "ap4x") -or
            ($vrc -match "apcn") -or ($vrc -match "hev1") -or ($vrc -match "vp09") -or
                ($vrc -match "vp9")) {
            $VProbe=$fprbPath+" -i '$StrmPath' -select_streams v -v error -hide_banner -show_entries stream=codec_name,codec_tag_string,avg_frame_rate:disposition=:tags= -of csv"
            Invoke-Expression $VProbe > "C:\temp_ov_info.csv" #ffprobe生成的csv中: stream,<index>,<codec_tag_string>
            if (Test-Path "C:\temp_ov_info.csv") {$Vcsv=Import-Csv "C:\temp_ov_info.csv" -Header A,B,C,D; Remove-Item "C:\temp_ov_info.csv"}
            $vfc=$Vcsv.D #ffmpeg要求输入帧数, 否则会阻止封装为mkv
            if ($vcopy -eq "y") {$result+="-r $vfc -c:v copy "} else {Write-Warning "首个 -c:v copy 以及 -r 命令已被写入, 屏蔽了重复写入"}
            if ((($MUXops -match "mkv") -and ($vrc -match "hevc")) -or (($MUXops -match "mkv") -and ($vrc -match "h265"))) {Write-Error "丙× ffmpeg不准导入hevc/h265单文件流到mkv(无时间戳错误), 先用本程序封装成MP4再封装MKV"; pause; exit}
            if ((($MUXops -match "mkv") -and ($vrc -match "hevc")) -or (($MUXops -match "mkv") -and ($vrc -match "h265"))) {Write-Error "丙× ffmpeg不准导入avc/h264单文件流到mkv(无时间戳错误), 先用本程序封装成MP4再封装MKV"; pause; exit}
            Write-Debug "`r`n丙√ $MUXops 可以封装视频流: $vrc`r`n"
            if (($vrc -match "ap4x") -or ($vrc -match "apcn")) {Write-Warning "检测到ProRes 422 / 4444XQ视频流. 仅MOV/QTFF, MXF封装格式支持"}
            if (($vrc -match "vp09") -or ($vrc -match "vp9")) {Write-Warning "检测到VP9视频流. 有MKV, MP4, *OGG, WebM等封装格式支持"}
        } elseif(
            ($arc -match "aac") -or ($arc -match "ogg") -or ($arc -match "alac") -or
            ($arc -match "dts") -or ($arc -match "mp3") -or ($arc -match "wma") -or
            ($arc -match "wav") -or ($arc -match ".pcm") -or ($arc -match ".lpcm") -or
            ($arc -match "flac") -or ($arc -match "ape") -or ($arc -match "alac")) {
            $result+="-c:a copy "
            Write-Debug "`r`n丙√ $MUXops 可以封装音频流: $arc`r`n"
            if ($arc -match "ape") {Write-Error "β× 没有封装格式支持MonkeysAudio/APE音频"; pause; exit}
            if ($arc -match "flac") {Write-Warning "检测到FLAC音频. MOV/QTFF, MXF封装格式不支持"}
            if ($arc -match "alac") {Write-Warning "检测到ALAC音频, MXF封装格式不支持"}
        } elseif(
            ($src -match "srt") -or ($src -match "ass") -or ($src -match "ssa")) {
            $result+="-c:s copy "
            Write-Debug "`r`n丙√ $MUXops 可以封装字幕轨: $src`r`n"
            if (($src -match "ass") -or ($src -match "ssa")) {Write-Warning "检测到ASS/SSA字幕, 唯独MKV封装格式支持"}
        } elseif(
            ($trc -match "ttf") -or ($trc -match "ttc") -or ($trc -match "otf")) {
            $result+="-c:t copy "
            Write-Warning "`r`n丙! 仅.mkv格式支持封装字体轨 $trc`r`n"
        } else{Write-Error "`r`n丙× 无法写入ffmpeg命令, 因为输入的单文件流不在mkv/mp4/mov/f4v/flv/avi, m4a/mka/mks, hevc/avc/cfhd/ap4x/apcn/vp9, aac/ogg/alac/dts/mp3/wma/pcm/lpcm/flac, srt/ass/ssa, ttf/ttc/otf范围内`r`n"; pause}
        return $result
    }
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

Write-Output "用mediainfo打开封装文件, 选`"view`"即检测封装中的音-字幕轨格式. 仅音轨可以用: ffprobe -i [源] -select_streams a -v error -hide_banner -show_streams  -of ini > `"X:\桌面\1.txt`"`r`n"
Write-Output "导出封装中特定aac音轨(.mp4中常见的音轨格式):`r`nffmpeg -i [源] -vn -c:a:0 copy `"X:\文件夹\导出音频1.aac`" `r`nffmpeg -i [源] -vn -c:a:1 copy `"X:\文件夹\导出音频2.aac`" `r`nffmpeg -i [源] -vn -c:a:2 copy `"X:\文件夹\导出音频3.aac`"`r`n"
Write-Output "导出封装中所有字幕轨, 根据字幕格式写后缀名:`r`nffmpeg -i [源] -vn -an -c:s:0 copy `"X:\文件夹\导出字幕1.ass`" `r`nffmpeg -i [源] -vn -an -c:s:1 copy `"X:\文件夹\导出字幕2.ass`" `r`nffmpeg -i [源] -vn -an -c:s:2 copy `"X:\文件夹\导出字幕3.ass`"`r`n"
Write-Output "导出封装中多轨道并重新封装1:`r`nffmpeg -i [源] -c:v copy -c:a:0 copy -c:a:1 copy -c:a:0 copy -c:s:0 copy`"X:\文件夹\导出1.mkv`"`r`n"
Write-Output "导出封装中多轨道并重新封装2:`r`nffmpeg -i [源] -i [源2] -i [源3] -i [源4] -map 1:v -c:v copy -map 2:a -c:a copy -map 2:s -c:s copy -map 3:a -c:a copy -map 3:s -c:s copy -map 4:a -c:a copy -map 4:s -c:s copy `"X:\文件夹\导出2.mkv`" `r`n"
Write-Output "为降低程序复杂度而限制了支持的文件类型:`r`nmkv/mp4/mov/f4v/flv/avi, m4a/mka/mks, hevc/avc/cfhd/ap4x/apcn, aac/ogg/alac/dts/mp3/wma/pcm/lpcm, srt/ass/ssa. ttf/ttc/otf`r`n"
Set-PSDebug -Strict

#「启动A」找到所有需要的路径
Read-Host "将打开[导出封装批处理]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$exptPath=whichlocation
Read-Host "将打开[导出最终封装结果]的路径选择窗, 可能会在窗口底层弹出. 按Enter继续"
$muxPath=whichlocation
Read-Host "将打开[定位ffprobe.exe]的选择窗. 按Enter继续"
$fprbPath=whereisit

#「启动B」初始化用于临时储存一个导入命令, 以及集成多个导入命令的两个参数
$StrmIMPAgg=$StrmParAgg=""#Agg=aggregate
Write-Warning "只有第一项导入的视频文件会保留(-c:v copy)命令, 以确保仅输出一个视频流到封装中`r`n"
$keepAdd=$vcopy="y"       #循环导入判断, 以及写入首个-c:v copy命令后关闭写入窗口的判断值
$mapQTY=0                 #ffmpeg -map参数的循环累计值, 只在一开始导入时初始化

#「启动C」循环调用addcopy函数生成封装导入命令
Read-Host "将打开[定位待封装源]的循环选择窗. 按Enter继续"
While ($keepAdd -eq "y") {
    $StrmPath=whereisit
    $addcopy=addcopy -fprbPath $fprbPath -StrmPath $StrmPath -mapQTY $mapQTY -vcopy $vcopy
    if ($addcopy -match "-c:v copy") {$vcopy="n"} #第一个源必须是视频, 然后通过$vcopy开关关闭"-c:v copy"命令的生成

    $StrmIMPAgg+=" -i `"$StrmPath`"" #由于ffmpeg要求多文件导入必须添加map参数, 而-map参数要求必须分割每个-c:? copy所做的参数顺序重构工作
    $StrmParAgg+="-map "+$mapQTY+" $addcopy" #随循环累计变多, 注意ffmpeg不支持单引号
    
    $mapQTY+=1
    Do {$keepAdd=Read-Host "`r`n√ 已生成ffmpeg导入参数: $StrmParAgg `r`n`r`n选择[n结束 | y继续]导入文件"
        if ((($keepAdd -eq "y") -eq $false) -and (($keepAdd -eq "n") -eq $false)) {Write-Warning "未输入y或n"}
    } While ((($keepAdd -eq "y") -eq $false) -and (($keepAdd -eq "n") -eq $false))
}

$nameIn=[IO.Path]::GetFileNameWithoutExtension($StrmPath) #初始化导出封装结果用的文件名
$nameIn+="_tempMux"
Switch (Read-Host "`r`n 选择[A: 输入文件名 | B: $nameIn]") {
    a {Do {Do {$nameIn = (Read-Host -Prompt "`r`n输入[文件名]（无后缀, 如 [Zzz] Memories – 01 (BDRip 1764x972 HEVC)）")
                $nameCheck = namecheck($nameIn)
                if ($nameCheck -eq $false) {Write-Output "文件名违反Windows命名规则（含/ | \ < > : ? * `"）"}
                elseif ($nameIn -eq 'y') {Write-Output "为防止误操作, 拦截了输出文件名: y"}
            } While ($nameCheck -eq $false)
        } While ($nameIn -eq 'y')
        Write-Output "√ 文件名符合Windows命名规则`r`n"} #关闭选项A
    b {Write-Output "选择了默认文件名"}
    default {Write-Output "选择了默认文件名（输入了空值）"}
}

#选择封装方案. 由于未来要添加更多导入方案, 所以导入变量会重复出现在多个选项里
Do {$MUXops=""
    Switch (Read-Host "`r`n选择封装工具+格式:`r`n[A: ffmpeg+MP4 (视音频, 独轨字幕) | B: ffmpeg+MOV (视音频) | C: ffmpeg+MKV (视音字幕字体) | D: ffmpeg+MXF (视音字幕)]") {
        a {$MUXops=".mp4"; Write-Output "`r`n选择了MP4 - 线路A. 已打开[定位ffmpeg.exe]的选择窗`r`n"; $fmpgPath=whereisit}
        b {$MUXops=".mov"; Write-Output "`r`n选择了MOV - 线路B. 已打开[定位ffmpeg.exe]的选择窗`r`n"; $fmpgPath=whereisit}
        c {$MUXops=".mkv"; Write-Output "`r`n选择了MKV - 线路C. 已打开[定位ffmpeg.exe]的选择窗`r`n"; $fmpgPath=whereisit}
        d {$MUXops=".mxf"; Write-Output "`r`n选择了MXF - 线路D. 已打开[定位ffmpeg.exe]的选择窗`r`n"; $fmpgPath=whereisit}
        default {Write-Warning "输入错误, 重试"}
    }
} While ($MUXops -eq "")
Write-Output "√ 输入了 $fmpgPath`r`n"

#D:\ffmpeg.exe -i "D:\视频.mkv" -i "D:\字幕.srt" -i "D:\视频.mp4"  -map 0:v -r 25 -c:v copy  -map 0:a -c:a copy  -map 0:s -c:s copy  -map 0:t -c:t copy  -map 1:s -c:s copy  -map 2:v -r 24000/1000 -c:v copy  "D:\文件夹\输出.mkv"
#$fmpgPath---" "-$StrmIMPAgg------------------------------------" "$StrmParAgg-------------------------------------------------------------------------------------------------------------------------------" "-$muxPath+$nameIn+$MUXops
$mux_gen=$fmpgPath+$StrmIMPAgg+" "+$StrmParAgg+" "+"`""+$muxPath+$nameIn+$MUXops+"`"" #注: ffmpeg禁止命令中含单引号

#拦截+处理与封装不匹配的命令
if ((($MUXops -eq ".mp4") -or ($MUXops -eq ".mov") -or ($MUXops -eq ".mxf")) -and ($mux_gen -match "-c:t copy")) {
    Switch (Read-Host "选择了MP4/MOV/MXF封装, 但命令行中有拷贝字体-c:t copy的命令.`r`n选择[A: 删除命令 | B: 换MKV封装 | C: 跳过(不推荐)]") {
        a {$mux_gen -replace "-c:t copy", ""; Write-Output "已删除"}
        b {$MUXops=".mkv"; Write-Output "已更改"}
        c {Write-Output 跳过}
    }
}

if ((($MUXops -eq ".mp4") -or ($MUXops -eq ".mov")) -and ($mux_gen -match "-c:s copy")) {
    Switch (Read-Host "选择了MP4/MOV封装, 但命令行中有拷贝多轨字幕-c:s copy的命令.`r`n选择[A: 删除命令 | B: 换MKV封装 | C: 跳过(不推荐)] | D: 选择单轨字幕并转码为-c:s:0 mov_text(成功概率低, 如果有多个-c:s copy命令则需要手动去重)") {
        a {$mux_gen -replace "-c:s copy", ""; Write-Output "已删除"}
        b {$MUXops=".mkv"; Write-Output "已更改"}
        c {Write-Output 跳过}
        d {$mux_gen -replace "-c:s copy", "-c:s:0 mov_text"; Write-Output "已更改"}
    }
}

if (($mux_gen -match "-c:v copy") -eq $false) {Write-Warning "总结出的命令中不含-c:v copy. 封装结果将不含视频"}
if (($mux_gen -match "-c:a copy") -eq $false) {Write-Warning "总结出的命令中不含-c:a copy. 封装结果将不含音频"}

$utf8NoBOM=New-Object System.Text.UTF8Encoding $false #导出utf-8NoBOM文本编码hack
$exptPath+="6S.「封装命令」.bat.txt"
Write-Output "`r`n  正在生成 6S.「封装命令」.bat.txt`r`n"
[System.IO.File]::WriteAllLines($exptPath, $mux_gen, $utf8NoBOM) #强制导出utf-8NoBOM编码

Write-Output "封装命令会故意生成.txt以引导用户先打开并移除不需要的-c:v copy, -c:a copy, -c:s copy, -c:t copy等参数, 或改成-c:a:0 copy这样的定位参数来筛选特定流`r`n如果音频/字幕没有与视频对齐, 则在对应的-map -c两个命令之间添加-itoffset<+/-秒.毫秒>"
pause