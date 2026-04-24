<#
.SYNOPSIS
    ffprobe 影片源分析腳本
.DESCRIPTION
    分析源影片並導出到 %USERPROFILE%\temp_v_info(_is_mov).json: 總幀數，寬，高，色彩空間，傳輸特定等。繁體在地化由繁化姬實現：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.7
#>

# 若同時檢測到 temp_v_info_is_mov.json 與 temp_v_info.json，則使用其中創建日期最新的文件

# 載入共用代碼，包括 $utf8NoBOM、Get-QuotedPath、Select-File、Select-Folder...
. "$PSScriptRoot\Common\Core.ps1"

# 需要結合影片數據統計的參數
$fpsParams = [PSCustomObject]@{
    rNumerator = [int]0 # 基礎幀率
    rDenumerator = [int]0
    rDouble = [double]0
    aNumerator = [int]0 # 平均幀率
    aDenumerator = [int]0
    aDouble = [double]0
}

# 腳本運行位置
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# 統計並更新影片源的基礎幀率、平均幀率、總幀數、總時長數據
function Set-FpsParams {
    param(
        [Parameter(Mandatory=$true)][string]$rFpsString,
        [Parameter(Mandatory=$true)][string]$aFpsString
    )
    $rFpsString = $rFpsString.Trim()
    $aFpsString = $aFpsString.Trim()
    $fpsRegex = '^\s*(\d+)\s*/\s*(\d+)\s*$'

    # 整數幀率補充分母
    if ($rFpsString -notmatch "/") { $rFpsString += "/1" }
    if ($aFpsString -notmatch "/") { $aFpsString += "/1" }
    
    # 處理基礎幀率
    if ($rFpsString -match $fpsRegex) {
        $rNum = [int]$Matches[1]
        $rDnm = [int]$Matches[2]
        if ($rDnm -eq 0) { throw "基礎幀率分母不能為零" }
        $script:fpsParams.rNumerator = $rNum
        $script:fpsParams.rDenumerator = $rDnm
        $script:fpsParams.rDouble = [double]$rNum / $rDnm
    }
    
    # 處理平均幀率
    if ($aFpsString -match $fpsRegex) {
        $aNum = [int]$Matches[1]
        $aDnm = [int]$Matches[2]
        if ($aDnm -eq 0) { throw "平均幀率分母不能為零" }
        $script:fpsParams.aNumerator = $aNum
        $script:fpsParams.aDenumerator = $aDnm
        $script:fpsParams.aDouble = [double]$aNum / $aDnm
    }
    elseif ([double]::TryParse($aFpsString, [ref]$null)) {
        $aDouble = [double]$aFpsString
        $script:fpsParams.aNumerator = [int]($aDouble * 1000)
        $script:fpsParams.aDenumerator = 1000
        $script:fpsParams.aDouble = $aDouble
    }
}

#region Getters
function Get-Source {
    param(
        [string]$WindowTitle,
        [switch]$ScriptOnly,
        [Parameter(Mandatory=$true)][string]$ErrMsg="未选择文件，请重试"
    )
    do {
        $file = Select-File -Title $windowTitle -ScriptOnly:$ScriptOnly
        if (-not $file) { Show-Error $errMsg }
    }
    while (-not $file)
    return $file
}

# 模組化的 ffprobe 資訊讀取函數
function Get-VideoStreamInfo {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource, # 輸入路徑不要加引號
        [string]$showEntries = "stream"
    )

    if (-not (Test-NullablePath $ffprobePath)) {
        throw "Get-VideoStreamInfo：ffprobe.exe 不存在（$ffprobePath）"
    }
    if (-not (Test-NullablePath $videoSource)) {
        throw "Get-VideoStreamInfo：輸入影片不存在（$videoSource）"
    }

    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-select_streams', 'v:0',
        '-show_entries', $showEntries,
        '-show_format',
        '-of', 'json', $videoSource
    )

    # 臨時切換為 UTF-8 解碼 ffprobe 的標準輸出
    $prevOut = [Console]::OutputEncoding
    $prevPS = $OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $ffprobeJson = &$ffprobePath @ffprobeArgs 2>$null
    }
    finally {
        [Console]::OutputEncoding = $prevOut
        $OutputEncoding = $prevPS
    }

    if ($LASTEXITCODE -ne 0 -or -not $ffprobeJson) {
        throw "Get-VideoStreamInfo：ffprobe 執行失敗或未返回有效數據"
    }

    try { $info = $ffprobeJson | ConvertFrom-Json }
    catch {
        Write-Host $ffprobeJson
        throw "Get-VideoStreamInfo：無法解析 ffprobe 返回的 JSON"
    }

    if (-not $info.streams -or $info.streams.Count -lt 1) {
        throw "Get-VideoStreamInfo：未找到影片串流資訊"
    }

    return $info.streams[0]
}

# 同時生成占位 AVS/VS 腳本到 %USERPROFILE%，從而在用戶暫無可用腳本的情況下頂替
function Get-BlankAVSVSScript {
    param([Parameter(Mandatory=$true)][string]$videoSource)

    # 嘗試用共用函數拿到帶引號的路徑
    $quotedImport = Get-QuotedPath $videoSource

    # 空腳本與導出路徑
    $AVSScriptPath = Join-Path $Global:TempFolder "blank_avs_script.avs"
    $VSScriptPath = Join-Path $Global:TempFolder "blank_vs_script.vpy"
    # 生成 AVS 內容（LWLibavVideoSource 需要雙引號包裹路徑）
    # 文件夾：C:\Program Files (x86)\AviSynth+\plugins64+\ 中必須有 libvslsmashsource.dll
    $blankAVSScript = "LWLibavVideoSource($quotedImport) # 自動生成的占位腳本，按需修改"
    # 生成 VapourSynth 內容（使用原始字串 literal r"..." 以避免轉義問題）
    # 若 Get-QuotedPath 返回例如 "C:\path\file.mp4"，則 r$quotedImport 將成為 r"C:\path\file.mp4"
    $blankVSScript = @"
import vapoursynth as vs
core = vs.core
src = core.lsmas.LWLibavSource(source=r$quotedImport)
# 自動生成無濾鏡腳本：按需在此處加入濾鏡、裁切、幀率調整等
src.set_output()
"@

    try {
        Confirm-FileDelete $AVSScriptPath
        Confirm-FileDelete $VSScriptPath

        Show-Info "正在生成無濾鏡腳本：`n $AVSScriptPath`n $VSScriptPath"
        Write-TextFile -Path $AVSScriptPath -Content $blankAVSScript -UseBOM $false
        Write-TextFile -Path $VSScriptPath -Content $blankVSScript -UseBOM $false
        Show-Success "已生成無濾鏡腳本到用戶目錄。"

        # 驗證換行符
        Show-Debug "驗證腳本檔案格式..."
        if (-not (Test-TextFileFormat -Path $AVSScriptPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $VSScriptPath)) {
            return
        }

        # 調用方根據上游類型選擇使用哪個腳本
        return @{
            AVS = $AVSScriptPath
            VPY = $VSScriptPath
        }
    }
    catch {
        Show-Error ("生成無濾鏡腳本失敗：" + $_)
        return $null
    }
}
#endregion

#region Validation
# 檢測整數是否類似質數，來源：buttondown.com/behind-the-powershell-pipeline/archive/a-prime-scripting-solution
function Test-IsLikePrime {
    param (
        [Parameter(Mandatory=$true)][int]$number,
        [int]$threshold = 5 # 整除數的數量閾值，超過後判斷為不類似質數
    )
    if ($number -lt 3) { throw "測試值必須大於 3" }
    $t = 0
    for ($i=2; $i -le [math]::Sqrt($number); $i++) {
        if ($number % $i -eq 0) { $t++ }
        if ($t -gt $threshold) { return $false }
    }
    return $true
}

# 檢測並警告可變幀率以及非方形象素變寬比存在，並提供修復建議
function Test-VideoWarnings {
    param (
        [Parameter(Mandatory=$true)]$ffprobeStreamInfo,
        [double]$RelativeTolerance = 0.000000001,
        [Parameter(Mandatory=$true)][string]$quotedVideoSource
    )

    function Write-NoticeBlock {
        param(
            [Parameter(Mandatory=$true)][string]$Title,
            [Parameter(Mandatory=$true)][object[]]$Lines
        )
        Show-Warning $Title
        foreach ($line in $Lines) {
            if ($line -is [hashtable]) {
                Write-Host $line.Text -ForegroundColor $line.Color
            }
            else {
                Write-Host $line -ForegroundColor DarkYellow
            }
        }
    }

    try {
        $warningBlocks = @()

        # 1) 先更新幀率參數
        try {
            Set-FpsParams `
                -rFpsString ([string]$ffprobeStreamInfo.r_frame_rate).Trim() `
                -aFpsString ([string]$ffprobeStreamInfo.avg_frame_rate).Trim()
        }
        catch {
            Show-Warning "影片幀率數據為空或損壞，幀率無從得知"
        }

        $rFps = $script:fpsParams.rDouble
        $aFps = $script:fpsParams.aDouble
        $nbFrames = 0
        $duration = 0

        try {
            $nbFrames = [int]$ffprobeStreamInfo.nb_frames.Trim()
            $duration = [double]$ffprobeStreamInfo.duration.Trim()
        }
        catch {
            Show-Info "影片總幀數、時長元數據缺失，編碼器將不顯示 ETA"
        }

        $eFps = $null
        if ($nbFrames -gt 0 -and $duration -gt 0) {
            $eFps = $nbFrames / $duration
        }

        # 2) VFR 判定
        $vReasons = @()
        $score = 0

        if ($rFps -gt 0 -and $aFps -gt 0) {
            $relDiff = [math]::Abs($rFps - $aFps) / [math]::Max(1e-9, [math]::Max($rFps, $aFps))
            if ($relDiff -gt $RelativeTolerance) {
                $score += 1
                $vReasons += "基礎幀率（$rFps）與平均幀率（$aFps）不同"
            }
        }

        if ($null -ne $eFps -and $aFps -gt 0) {
            $relDiff2 = [math]::Abs($eFps - $aFps) / [math]::Max(1e-9, [math]::Max($eFps, $aFps))
            if ($relDiff2 -gt $RelativeTolerance) {
                $score += 2
                $vReasons += "估計幀率（$eFps）與平均幀率（$aFps）不同"
            }
        }

        if ($ffprobeStreamInfo.r_frame_rate -eq "90000/1") {
            $score += 3
            $vReasons += "特徵 r_frame_rate（90000）為 VFR 容器標記"
        }

        $aDnm = $script:fpsParams.aDenumerator
        if ($aDnm -gt 50000) {
            if (Test-IsLikePrime -number $aDnm) {
                $score += 2
                $vReasons += "平均幀率分母值較大（$aDnm）且接近質數"
            }
            else {
                $score += 1
                $vReasons += "平均幀率分母值較大（$aDnm）"
            }
        }

        $mode = "「確定」是恆定幀率（CFR）"
        if ($score -ge 5)     { $mode = "「確定」是可變幀率（VFR）" }
        elseif ($score -ge 4) { $mode = "「高機率」是可變幀率（VFR）" }
        elseif ($score -ge 2) { $mode = "「應該」是可變幀率（VFR）" }
        elseif ($score -gt 0) { $mode = "「有跡象」是可變幀率（VFR）" }

        if ($score -gt 0) {
            $rNum = $script:fpsParams.rNumerator
            $rDnm = $script:fpsParams.rDenumerator

            $lines = @()
            $lines += ($vReasons | ForEach-Object { "   - $_" })
            $lines += " 建議重新渲染為恆定幀率（CFR）再繼續，或在對應線路添加 ffmpeg/VS/AVS 濾鏡組矯正"
            $lines += " 例：渲染並編碼為 FFV1 無損影片："
            $lines += @{ Text = "   - ffmpeg -i $quotedVideoSource -r $rNum/$rDnm -c:v ffv1 -level 3 -context 1 -g 180 -c:a copy output.mkv"; Color = "Magenta" }
            $lines += " 例：測量影片幀以確定 VFR："
            $lines += @{ Text = "   - ffmpeg -i $quotedVideoSource -vf vfrdet -an -f null -"; Color = "Magenta" }
            $lines += @{ Text = "   - 結束後根據 [Parsed_vfrdet_0 @ 0000012a34b5cd00] VFR:0.xxx (yyy/zzz) 字樣即可確定"; Color = "Yellow" }
            $lines += @{ Text = "   - yyy：顯示時長對不上幀率幀的總數"; Color = "Magenta" }

            $warningBlocks += [PSCustomObject]@{
                Title = "源$mode，本程式暫無對策（強行編碼可能會導致影片時長錯誤，隨播放與音訊失聯）"
                Lines = $lines
            }
        }

        # 3) SAR 判定
        $sampleAspectRatio = "1:1"
        try {
            $sampleAspectRatio = ([string]$ffprobeStreamInfo.sample_aspect_ratio).Trim()
        }
        catch {
            Show-Warning "Test-VideoWarnings：源的變寬比（SAR）數據損壞，將預設為 1:1"
        }

        if ($sampleAspectRatio -notin @("1:1", "0:1")) {
            $warningBlocks += [PSCustomObject]@{
                Title = "源的變寬比（SAR）為 $sampleAspectRatio（非 1:1 方形象素）"
                Lines = @(
                    " 本程式暫無對策（強行編碼會恢復到方形象素，致畫面縮寬）",
                    " 手動矯正方法：",
                    " 1. ffmpeg -i $quotedVideoSource -c copy -aspect $sampleAspectRatio output.mkv",
                    " 2. MP4Box -par 1=$sampleAspectRatio $quotedVideoSource -out output.mp4",
                    " 3. moviepy:",
                    "    from moviepy.editor import VideoFileClip",
                    "    clip = VideoFileClip($quotedVideoSource)",
                    "    clip.aspect_ratio = $sampleAspectRatio",
                    "    clip.write_videofile('output.mp4')"
                )
            }
        }

        # 4) 統一輸出
        if ($warningBlocks.Count -gt 0) {
            foreach ($block in $warningBlocks) {
                Write-NoticeBlock -Title $block.Title -Lines $block.Lines
                Write-Host ""
            }
            Read-Host " 按任意鍵繼續..." | Out-Null
        }
        else {
            Show-Success "源「確定」是恆定幀率（CFR），且未發現非方形象素問題"
        }
    }
    catch { throw ("Test-VideoWarnings：" + $_) }
}

# 利用 ffprobe 驗證影片檔案封裝格式，無視后綴名（封裝格式用大寫字母表示）
function Test-VContainerFormat {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource # 輸入路徑不要加引號
    )
    Show-Info "Test-VContainerFormat：正在檢測影片檔案封裝格式真偽..."

    # 臨時切換文本編碼
    $oldEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    if (-not (Test-Path -LiteralPath $ffprobePath)) {
        throw "Test-VContainerFormat：ffprobe.exe 不存在（$ffprobePath）"
    }
    if (-not (Test-Path -LiteralPath $videoSource)) {
        throw "Test-VContainerFormat：輸入影片不存在（$videoSource）"
    }
    # 獲取後綴名，用於後續邏輯
    $ext = [System.IO.Path]::GetExtension($videoSource)
    $ffprobeArgs = @(
        '-v', 'quiet', '-hide_banner',
        '-show_format', '-of', 'json',
        $videoSource
    )
    $ffprobeArgs2 = @(
        '-v', 'quiet', '-hide_banner',
        $videoSource
    )

    try { # 使用 JSON 輸入分析
        $ffprobeJson = &$ffprobePath @ffprobeArgs 2>$null

        if ($LASTEXITCODE -eq 0) { # ffprobe 正常退出，分析結果存在
            $formatInfo = $ffprobeJson | ConvertFrom-Json
            $formatName = $formatInfo.format.format_name

            # VOB 格式檢測
            if ($formatName -match "mpeg") {
                # 進一步檢測，捕獲 stderr
                $ffprobeText = &$ffprobePath @$ffprobeArgs2 2>&1
                # 檔案名含 VTS_ 字樣（不確定是否全是大寫，因此不用 cmatch）
                # $hasVTSFileName = $filename -match "^VTS_"
                # 元數據含 dvd_nav、mpeg2video 字樣
                $hasDVD = $ffprobeText -match "dvd_nav"
                $hasMPEG2 = $ffprobeText -match "mpeg2video"

                # VOB 通常包含 DVD 導航包或特定的流結構
                if ($hasDVD -or $hasMPEG2) {
                    Show-Success "Test-VContainerFormat：檢測到 VOB 格式（DVD 影片）"
                    return "VOB"
                }

                Show-Warning "Test-VContainerFormat：源非 MPEG2 編碼，且無 DVD 導航標識，將視作一般封裝格式"
                return "std"
            }
             
            # 常規格式映射
            switch -Regex ($formatName) {
                "mov|mp4|m4a|3gp|3g2|mj2" {
                    if ($formatName -match "qt" -or $ext -eq ".mov") {
                        Show-Success "檢測到 MOV 格式"
                        return "MOV"
                    }
                    Show-Success "檢測到 MP4 格式"
                    return "MP4"
                }
                "matroska" { Show-Success "檢測到 MKV 格式"; return "MKV" }
                "webm"     { Show-Success "檢測到 WebM 格式"; return "WebM" }
                "avi"      { Show-Success "檢測到 AVI 格式"; return "AVI" }
                "ivf"      { Show-Success "檢測到 IVF 格式"; return "ivf" }
                "hevc"     { Show-Success "檢測到 HEVC 裸流"; return "hevc" }
                "h264|avc" { Show-Success "檢測到 AVC 裸流"; return "avc" }
                "ffv1"     { Show-Success "檢測到 FFV1"; return "ffv1" }
            }
            return $formatName
        }
        else { # ffprobe 失敗
            throw "Test-VContainerFormat：ffprobe 執行或 JSON 解析失敗"
        }
    }
    catch {
        throw ("Test-VContainerFormat - 檢測失敗：" + $_)
    }
    finally { # 還原編碼設置
        [Console]::OutputEncoding = $oldEncoding
    }
}
#endregion

#region Main
function Main {
    # IO 變數
    $videoSource = $null # ffprobe 將分析這個影片檔案
    $scriptSource = $null # 腳本文件路徑，如果有則在導出的 json 中覆蓋影片源
    $encodeImportSourcePath = $null
    $svfiTaskId = $null
    $upstreamCode = $null
    $Avs2PipeModDLL = $null # Avs2PipeMod 需額外導入 DLL
    $OneLineShotArgsINI = $null
    $toolsJson = Join-Path $Global:TempFolder "tools.json"

    Show-Border
    Show-info ("ffprobe 源讀取工具，導出 " + $Global:TempFolder + "temp_v_info(_is_mov).json 以備用")
    Show-Border
    Write-Host ''

    # 根據管道上遊程序選擇源類型
    $sourceTypes = @{
        'A' = @{ Name = 'ffmpeg'; Ext = ''; Message = "任意源" }
        'B' = @{ Name = 'vspipe'; Ext = '.vpy'; Message = ".vpy 源" }
        'C' = @{ Name = 'avs2yuv'; Ext = '.avs'; Message = ".avs 源" }
        'D' = @{ Name = 'avs2pipemod'; Ext = '.avs'; Message = ".avs 源" }
        'E' = @{ Name = 'SVFI'; Ext = ''; Message = ".ini 源" } 
    }

    # 獲取源文件類型
    $selectedType = $null
    while ($true) {
        Show-Info "選擇先前腳本所用的管道上遊程序（確認源符合程序要求）："
        $sourceTypes.GetEnumerator() | Sort-Object Key | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value.Name)"
        }
        $choice = (Read-Host " 請輸入選項（A/B/C/D/E）").ToUpper()

        if ($sourceTypes.ContainsKey($choice)) {
            $selectedType = $sourceTypes[$choice]
            Show-Info $selectedType.Message
            break
        }
    }
    
    # 獲取上遊程序代號（寫入 json）
    $isScriptUpstream =
        $selectedType.Name -in @('vspipe', 'avs2yuv', 'avs2pipemod')

    switch ($selectedType.Name) {
        'ffmpeg'      { $upstreamCode = 'a' }
        'vspipe'      { $upstreamCode = 'b' }
        'avs2yuv'     { $upstreamCode = 'c' }
        'avs2pipemod' {
            $upstreamCode = 'd'
            Show-Info "指定 AviSynth.dll 的路徑..."
            Write-Host " 在 AviSynth+ 倉庫（https://github.com/AviSynth/AviSynthPlus/releases）中，"
            Write-Host " 下載 AviSynthPlus_x.x.x_yyyymmdd-filesonly.7z，即可獲取 DLL"
            do {
                $Avs2PipeModDLL = Select-File -Title "選擇 avisynth.dll" -InitialDirectory ([Environment]::GetFolderPath('System')) -DllOnly
                if (-not $Avs2PipeModDLL) {
                    $placeholderScript = Read-Host "未選擇 DLL。按 Enter 重試，輸入 'q' 強制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $Avs2PipeModDLL)
            Show-Success "已記錄 AviSynth.dll 路徑：$Avs2PipeModDLL"
        }
        'SVFI'        {
            $upstreamCode = 'e'
            Show-Info "正在檢測 SVFI 渲染配置 INI 可能的路徑..."
            $foundPath = Get-PSDrive -PSProvider FileSystem | ForEach-Object { 
                $p = "$($_.Root)SteamLibrary\steamapps\common\SVFI\Configs"
                if (Test-Path $p) { $p }
            } | Select-Object -First 1

            Show-Info "請指定 SVFI 渲染配置 INI 文件的路徑"
            Write-Host " 如 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini"

            do {
                if ($foundPath) { # 嘗試自動定位到的 SVFI 路徑（Select-File 能自動回退到 Desktop）
                    Show-Success "已定位候選路徑：$foundPath"
                    $OneLineShotArgsINI = Select-File -Title "選擇 SVFI 渲染設定檔（.ini）" -IniOnly -InitialDirectory $foundPath
                }
                else { # DIY
                    $OneLineShotArgsINI = Select-File -Title "選擇 SVFI 渲染設定檔（.ini）" -IniOnly
                }

                if (-not $OneLineShotArgsINI -or -not (Test-Path -LiteralPath $OneLineShotArgsINI)) {
                    $placeholderScript = Read-Host " INI 路徑不存在；按 Enter 重試，輸入 'q' 強制退出"
                    if ($placeholderScript -eq 'q') { exit }
                }
            }
            while (-not $OneLineShotArgsINI -or -not (Test-Path -LiteralPath $OneLineShotArgsINI))
        }
        default       { $upstreamCode = 'a' }
    }
    Write-Host ("─" * 50)

    # vspipe / avs2yuv / avs2pipemod：提供生成無濾鏡腳本選項
    if ($isScriptUpstream) {
        Show-Info "選擇腳本引用的影片源文件"
        $videoSource =
            Get-Source -WindowTitle "選擇腳本引用的影片源文件（ffprobe 分析）" -ErrMsg "未選擇文件，請重試"

        while ($true) { # 影片源需補充
            Show-Info '選擇導入腳本，或生成 AviSynth、VapourSynth 腳本'
            $mode = Read-Host " 輸入 'y' 為影片源生成無濾鏡腳本，輸入 'n' 或 Enter 導入自訂腳本"
        
            if ([string]::IsNullOrWhiteSpace($mode) -or 'n' -eq $mode) {
                Show-Warning "由於腳本支援的導入路徑寫法繁多，條件過於複雜，無法驗證；請自行檢查視訊來源字串的拼寫"
                $scriptSource = Get-Source -WindowTitle "定位腳本源文件（.avs/.vpy）" -ScriptOnly -ErrMsg "未選擇文件，請重試"
                Show-Success "已選擇腳本文件：$scriptSource"
                break
            }
            elseif ('y' -eq $mode) {
                if (Test-NullablePath 'C:\Program Files (x86)\AviSynth+\plugins64+\LSMASHSource.dll') {
                    Show-Success "檢測到 C:\Program Files (x86)\AviSynth+\plugins64+\ 下已有 LSMASHSource.dll，無需配置"
                }
                else { # 用戶可能未安裝 AviSynth——產生誤報
                    Show-Warning "未在 C:\Program Files (x86)\AviSynth+\plugins64+\ 下發現 LSMASHSource.dll（解碼器）"
                    Write-Host " 缺少該文件會導致 AVS 腳本，包括本工具自動生成的腳本無法執行"
                    Write-Host " 下載並解壓 64bit 版：https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works/releases`r`n" -ForegroundColor Magenta
                }
                Write-Host ("─" * 50)
                
                $placeholderScript = Get-BlankAVSVSScript -videoSource $videoSource
                if (-not $placeholderScript) { 
                    Show-Error "生成無濾鏡腳本失敗，請重試"
                    continue
                }
            
                # 根據上游類型選擇正確的腳本路徑
                if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod')) {
                    $scriptSource = $placeholderScript.AVS
                }
                else { # vspipe
                    $scriptSource = $placeholderScript.VPY
                }
                
                Show-Success "已生成無濾鏡腳本：$scriptSource"
                break
            }
            else {
                Show-Warning "無效輸入"
                continue
            }
        }

        $encodeImportSourcePath = $scriptSource
    }
    # SVFI：從 INI 文件中讀取影片路徑，以及 task_id
    elseif ($OneLineShotArgsINI -and (Test-Path -LiteralPath $OneLineShotArgsINI)) { 
        # SVFI ini 文件中的影片路徑（實際上內容為單行）：gui_inputs="{
        #     \"inputs\": [{
        #         \"task_id\": \"必須獲取並賦值到 json\",
        #         \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\影片.mp4\",
        #         \"is_surveillance_folder\": false
        #     }]
        # }"
        # 讀取文件並找到 gui_inputs 行，如：
        # gui_inputs="{\"inputs\": [{\"task_id\": \"798_2aa174\", \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\[Airota][Yuru Yuri\\u3001][OVA][BDRip 1080p].mp4\", \"is_surveillance_folder\": false}]}"
        Show-Info "將嘗試從 SVFI 渲染配置 INI 中讀取影片源路徑..."

        try { # 讀取 INI 並尋找 gui_inputs 行
            $iniContent = Get-Content -LiteralPath $OneLineShotArgsINI -Raw -ErrorAction Stop
            $pattern = 'gui_inputs\s*=\s*"((?:[^"\\]|\\.)*)"'
            $guiInputsMatch = [regex]::Match($iniContent, $pattern)
            if (-not $guiInputsMatch.Success) {
                Show-Error "在 SVFI INI 文件中未找到 gui_inputs 欄位，請重新用 SVFI 生成 INI 文件"
                Read-Host "按 Enter 退出"
                return
            }

            # 提取含路徑的 JSON 字串（移除外層 gui_inputs="..."）
            $jsonString = $guiInputsMatch.Groups[1].Value
            $jsonString = $jsonString -replace '\\"', '"'
            $jsonString = $jsonString -replace '\\\\', '\\'
            Show-Debug "JSON 解析結果：$jsonString"

            # 轉譯 JSON 並提取影片源路徑到 PowerShell 變數
            try {
                $jsonObject = $jsonString | ConvertFrom-Json -ErrorAction Stop
                if ($null -eq $jsonObject.inputs -or ($jsonObject.inputs.Count -eq 0)) {
                    Show-Error "SVFI INI 文件中缺少影片源導入（input）語句，請重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }

                # 獲取首個輸入文件的路徑
                Show-Success "成功檢測到導入語句"
                Show-Warning "將導入其中的首個影片源，忽略其它影片源"
                $jsonSource = $jsonObject.inputs[0].input_path
                if ([string]::IsNullOrWhiteSpace($jsonSource)) {
                    Show-Error "SVFI INI 文件中的導入語句指向空路徑，請重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
                $svfiTaskId = $jsonObject.inputs[0].task_id
                if ([string]::IsNullOrWhiteSpace($svfiTaskId)) {
                    Show-Error "SVFI INI 文件中的 task_id 語句損壞，請重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
                Show-Success "從 SVFI INI 中解析到 Task ID: $svfiTaskId"

                $videoSource = Convert-IniPath -iniPath $jsonSource # FileUtils.ps1 函數
                Show-Success "從 SVFI INI 中解析到影片源：$videoSource"

                # 驗證影片檔案是否存在
                if (-not (Test-Path -LiteralPath $videoSource)) {
                    Show-Error "影片檔案已不存在：$videoSource，請重新用 SVFI 生成 INI 文件"
                    Read-Host "按 Enter 退出"
                    return
                }
            }
            catch {
                Show-Error "解析 JSON 失敗：$_"
                Show-Debug "原始 JSON 字串：$jsonString"
                Read-Host "按 Enter 退出"
                return
            }
        }
        catch {
            Show-Error "讀取 SVFI INI 文件失敗：$_"
            Read-Host "按 Enter 退出"
            return
        }

        $encodeImportSourcePath = $videoSource
    }
    else { # ffmpeg：影片源
        do {
            Show-Info "選擇要分析的影片源文件"
            $videoSource = Select-File -Title "定位影片檔案，如影片（.mp4/.mov/...）、RAW（.yuv/.y4m/...）"
            if (-not $videoSource) { 
                Show-Error "未選擇文件" 
                continue
            }
        }
        while (-not $videoSource)
        Show-Success "已選擇影片源文件：$videoSource"
        $encodeImportSourcePath = $videoSource
    }
    $quotedVideoSource = Get-QuotedPath $videoSource

    # ffprobe 命令
    $ffprobeArgs = @(
        '-i', $quotedVideoSource,
        '-select_streams', 'v:0',
        '-v', 'error', '-hide_banner',
        '-show_streams',
        '-show_frames', '-read_intervals', "%+#1"
        '-of', 'json'
    )
    Write-Host ("─" * 50)

    Show-Info "定位 ffprobe.exe..."
    $ffprobePath = $null
    $isSavedPathValid = $false
    if (Test-NullablePath $toolsJson) {
        try {
            $savedConfig = Read-JsonFile $toolsJson
            Show-Info "檢測到設定檔（$($savedConfig.SaveDate)），正在載入..."
            if ($savedConfig.Analysis) {
                $ffprobePath = $savedConfig.Analysis.ffprobe
                Show-Debug ("路徑：" + $ffprobePath)
                if (Test-NullablePath $ffprobePath) { $isSavedPathValid = $true }
                else { Show-Info "設定檔指向的路徑不存在，建議重新執行步驟 2 腳本" }
            }
        }
        catch { Show-Info "設定檔損壞，需要手動導入；建議重新執行步驟 2 腳本" }
    }
    
    # 使用 Invoke-AutoSearch 定位 ffprobe 程序
    if (-not $isSavedPathValid) {
        $ffprobePath = Invoke-AutoSearch -ToolName 'ffprobe' -ScriptDir $scriptDir
        if ($ffprobePath) {
            Show-Success "將直接使用自動檢測到的 ffprobe.exe：$ffprobePath"
        }
        else {
            do {
                $ffprobePath =
                    Select-File -Title "定位 ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
                if (-not (Test-Path -LiteralPath $ffprobePath)) {
                    Show-Warning "找不到 ffprobe 可執行文件，請重試"
                }
            }
            while (-not (Test-Path -LiteralPath $ffprobePath))
        }
    }
    
    Write-Host ("─" * 50)

    # 僅用於觀察，不用於最終導出，不支持 $quotedVideoSource
    $streamInfo = Get-VideoStreamInfo -ffprobePath $ffprobePath -videoSource $videoSource -showEntries "stream=r_frame_rate,avg_frame_rate,nb_frames,duration,sample_aspect_ratio"
    # Show-Debug "幀率，平均幀率，總幀數，時長，變寬比："
    # Write-Host $streamInfo

    # 檢測可變幀率源、非方形象素源並告警
    Test-VideoWarnings -ffprobeStreamInfo $streamInfo -quotedVideoSource $quotedVideoSource

    Write-Host ("─" * 50)

    # 檢測封裝文件真偽，不支持 $quotedVideoSource
    $realFormatName = Test-VContainerFormat -ffprobePath $ffprobePath -videoSource $videoSource

    Write-Host ("─" * 50)

    $isMOV = ($realFormatName -like "MOV")
    $isVOB = ($realFormatName -like "VOB")
    # if ($isMOV) { Show-Debug "導入影片 $videoSource 的封裝格式為 MOV" }
    # elseif ($isVOB -like "VOB") { Show-Debug "導入影片 $videoSource 的封裝格式為 VOB" }
    # else { Show-Debug "導入影片 $videoSource 的封裝格式非 MOV、VOB" }

    # 由於 ffprobe 讀取不同源所產生的列數不一會導致數據隨機錯位，因此不用無鍵的格式
    $sourceJsonExportPath = Join-Path $Global:TempFolder "temp_s_info.json"
    $ffprobeJsonExportPath =
        if ($isMOV) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.json"
        }
        elseif ($isVOB) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.json"
        }
        else {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.json"
        }
    # $ffprobeJsonExportPathDebug =
    #     if ($isMOV) {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov_debug.json"
    #     }
    #     else {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_debug.json"
    #     }

    # 若 json 已存在，要求手動確認後清理，避免覆蓋
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.json")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.json")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.json")
    Confirm-FileDelete $sourceJsonExportPath

    # 執行 ffprobe 並插入影片源路徑
    try {
        Write-Host $ffprobeArgs -ForegroundColor Green
        $ffprobeOutputJson = (& $ffprobePath @ffprobeArgs) -join "`n"
        
        # 構建源資訊對象
        $sourceInfoObject = @{
            SourcePath       = $encodeImportSourcePath
            UpstreamCode     = $upstreamCode
            Avs2PipeModDllPath = $Avs2PipeModDLL
            SvfiInputConf    = $OneLineShotArgsINI
            SvfiTaskId       = $svfiTaskId
        }
        
        # 寫入 ffprobe JSON、源資訊 JSON
        Write-TextFile -Path $ffprobeJsonExportPath -Content $ffprobeOutputJson -UseBOM $true
        Write-JsonFile -Path $sourceJsonExportPath -Object $sourceInfoObject
        Show-Success "JSON 文件已生成：`r`n $ffprobeJsonExportPath`r`n $sourceJsonExportPath"
        Write-Host ("─" * 50)
        
        # 驗證 JSON 檔案格式（使用新的函數）
        Show-Debug "驗證 JSON 檔案格式..."
        if (-not (Test-JsonFileFormat -Path $ffprobeJsonExportPath)) {
            return
        }
        if (-not (Test-JsonFileFormat -Path $sourceJsonExportPath)) {
            return
        }
    }
    catch { 
        throw ("ffprobe 執行或 JSON 導出失敗：" + $_) 
    }

    Write-Host ''
    Show-Success "腳本執行完成！"
    Read-Host "按 Enter 退出"
}
#endregion

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}