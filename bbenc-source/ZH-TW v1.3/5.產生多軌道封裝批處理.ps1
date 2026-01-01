<#
.SYNOPSIS
    基於 ffmpeg、ffprobe 的多軌道複雜封裝命令生成器
.DESCRIPTION
    封裝對過視音頻、字幕字體批處理的工具，運行批處理即可完成封裝操作
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# 加載共用代碼
. "$PSScriptRoot\Common\Core.ps1"

# 檢測幀率值是否正常
function Test-FrameRateValid {
    param([string]$fr)
    if (-not $fr) { return $false }

    # 排除 0/0 或 0
    if ($fr -match '^(0(/0)?|0(\.0+)?)$') { return $false }

    # 允許分數如 24000/1001、允許整數 24、允許小數 23.976
    if ($fr -match '^\d+/\d+$') { return $true }
    if ($fr -match '^\d+(\.\d+)?$') { return $true }
    return $false
}

function Get-FrameRateFromContainer {
    param(
        [Parameter(Mandatory=$true)][string]$FFprobePath,
        [Parameter(Mandatory=$true)][string]$FilePath
    )
    $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
    if ($vData -and $vData.FrameRate) {
        return $vData.FrameRate
    }
    return $null
}


# 調用 ffprobe 獲取指定流的信息，直接返回對象，不寫臨時文件
function Get-StreamArgs {
    param (
        [string]$FFprobePath,
        [string]$FilePath,
        [int]$MapIndex,
        [bool]$IsFirstVideo
    )
    
    $ext = [IO.Path]::GetExtension($FilePath).ToLower()
    $argsResult = @()
    $hasVideo = $false
    
    # 檢查是否為視頻容器格式
    $isVideoContainer = $ext -in @('.mkv', '.mp4', '.mov', '.f4v', '.flv', '.avi', '.m3u', '.mxv')
    $isAudioContainer = $ext -in @('.m4a', '.mka', '.mks')
    $isSingleFile = -not ($isVideoContainer -or $isAudioContainer)
    
    Show-Debug "分析文件：$FilePath（擴展名：$ext）"
    
    # 處理視頻容器
    if ($isVideoContainer) {
        Show-Info "視頻容器格式，分析所有流..."
        
        # 視頻流
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        if ($vData -and $IsFirstVideo) {
            $codec = if ($vData.CodecTag -and $vData.CodecTag -ne "0") { 
                $vData.CodecTag 
            }
            else { 
                $vData.CodecName 
            }
            
            Show-Success "視頻流：$codec"
            if ($vData.FrameRate) { # 默認視頻容器格式一定含幀率信息
                $argsResult += "-r $($vData.FrameRate) -c:v copy"
            }
            else {
                $argsResult += "-c:v copy"
            }
            $hasVideo = $true
        }
        elseif ($vData) {
            Show-Warning "跳過額外視頻流（僅保留第一個視頻）"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "發現音頻流"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "發現字幕流"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isAudioContainer) { # 處理音頻容器
        Show-Info "發現音頻容器格式..."
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "發現音頻流"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "發現字幕流"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isSingleFile) { # 處理單文件（未封裝視頻、音頻、字幕等）
        Show-Info "單文件格式，分析流類型..."
        
        # 嘗試檢測文件格式
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        
        if ($vData -and $IsFirstVideo) {
            Show-Success "發現視頻流：$($vData.CodecName)"
            
            # 獲取當前文件的幀率
            $currentFrameRate = $vData.FrameRate
            $isCurrentFrameRateValid = Test-FrameRateValid -fr $currentFrameRate
            
            # 幀率處理邏輯
            if ($isCurrentFrameRateValid) {
                # 情況1：單文件本身有有效幀率
                Show-Info "使用文件自帶的幀率：$currentFrameRate"
                $frameRate = $currentFrameRate
            }
            else {
                # 情況2：單文件沒有有效幀率，提供選擇
                Show-Warning "未封裝的視頻流不具備有效幀率信息"
                
                # 提供用戶選擇
                Write-Host "`n選擇幀率來源：" -ForegroundColor Cyan
                Write-Host "1：手動輸入幀率" -ForegroundColor Yellow
                Write-Host "2：從其他封裝視頻文件讀取（推薦）" -ForegroundColor Yellow
                Write-Host "3：使用常用預設幀率" -ForegroundColor Yellow
                Write-Host "q：跳過此文件" -ForegroundColor DarkGray
                
                $choice = Read-Host "`n選擇（1-3，q）"
                
                switch ($choice.ToLower()) {
                    '1' { # 手動輸入幀率
                        $manualFrameRate = Read-Host "請輸入幀率（整數/小數/分數，如 24、23.976、24000/1001）"
                        if (Test-FrameRateValid -fr $manualFrameRate) {
                            $frameRate = $manualFrameRate
                        }
                        else {
                            Show-Error "無效的幀率格式，將跳過此文件"
                            return $null
                        }
                    }
                    '2' { # 從其他文件讀取幀率
                        Show-Info "選擇一個包含幀率信息的封裝視頻文件（.mp4/.mov/.flv/...）"
                        $containerFile = Select-File -Title "選擇封裝視頻文件以讀取幀率"
                        
                        if ($containerFile -and (Test-Path -LiteralPath $containerFile)) {
                            $frameRate = Get-FrameRateFromContainer -FFprobePath $FFprobePath -FilePath $containerFile
                            if (-not $frameRate) {
                                Show-Error "無法從所選文件讀取有效幀率，將跳過此文件"
                                return $null
                            }
                            Show-Info "從參考文件讀取幀率：$frameRate"
                        }
                        else {
                            Show-Error "未選擇有效文件，將跳過此文件"
                            return $null
                        }
                    }
                    '3' { # 選擇常見幀率
                        Write-Warning "幀率必須與源完全一致，否則視頻無法正確播放"
                        Write-Host "`n常用幀率預設：" -ForegroundColor Cyan
                        Write-Host "1. 23.976（24000/1001）" -ForegroundColor Yellow
                        Write-Host "2. 24" -ForegroundColor Yellow
                        Write-Host "3. 25" -ForegroundColor Yellow
                        Write-Host "4. 29.97（30000/1001）" -ForegroundColor Yellow
                        Write-Host "5. 30" -ForegroundColor Yellow
                        Write-Host "6. 48" -ForegroundColor Yellow
                        Write-Host "7. 50" -ForegroundColor Yellow
                        Write-Host "8. 59.94（60000/1001）" -ForegroundColor Yellow
                        Write-Host "9. 60" -ForegroundColor Yellow
                        Write-Host "a. 120" -ForegroundColor Yellow
                        Write-Host "b. 144" -ForegroundColor Yellow
                        Write-Host ""

                        $presetChoice = Read-Host "選擇預設幀率（1-9，a-b）"
                        $frameRate = switch ($presetChoice.ToLower()) {
                            '1' { '24000/1001' }
                            '2' { '24' }
                            '3' { '25' }
                            '4' { '30000/1001' }
                            '5' { '30' }
                            '6' { '48' }
                            '7' { '50' }
                            '8' { '60000/1001' }
                            '9' { '60' }
                            'a' { '120' }
                            'b' { '144' }
                            default { 
                                Show-Error "無效選擇，將跳過此文件"
                                return $null
                            }
                        }
                    }
                    'q' {
                        Show-Info "用戶取消，跳過此文件"
                        return $null
                    }
                    default {
                        Show-Error "無效選擇，將跳過此文件"
                        return $null
                    }
                }
            }
            
            # 添加 ffmpeg 幀率參數
            if ($frameRate) {
                $argsResult += "-r $frameRate -c:v copy"
                $hasVideo = $true
            }
            else {
                Show-Warning "未設置幀率，大概率會導致播放問題"
                $argsResult += "-c:v copy"
                $hasVideo = $true
            }
        }
        elseif (-not $vData) { # 嘗試音頻流
            $aData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a"
            if ($aData) {
                Show-Success "發現音頻流：$($aData.CodecName)"
                $argsResult += "-c:a copy"
            }
        }
        
        if ($ext -in @('.srt', '.ass', '.ssa')) {
            Show-Success "字幕文件：$ext"
            $argsResult += "-c:s copy"
        }
        elseif ($ext -in @('.ttf', '.ttc', '.otf')) {
            Show-Success "字體文件：$ext"
            $argsResult += "-c:t copy"
        }
    }
    else {
        Show-Warning "未識別的源，無法處理"
        return $null
    }
    
    if ($argsResult.Count -eq 0) {
        Show-Warning "文件未生成有效參數：$FilePath"
        return $null
    }
    
    return [PSCustomObject]@{
        ArgumentsString = $argsResult -join " "
        ContainsVideo   = $hasVideo
    }
}

function Main {
    Show-Border
    Show-Info "基於 ffmpeg 的多軌道封裝命令生成器"
    Show-Border
    
    # 1. 初始化路徑與工具
    Show-Info "導入工具和選擇路徑"
    Show-Info "（1/4）導入 ffprobe.exe..."
    $fprbPath = Select-File -Title "選擇 ffprobe.exe" -ExeOnly
    Show-Info "（2/4）導入 ffmpeg.exe..."
    $ffmpegPath = Select-File -Title "選擇 ffmpeg.exe" -ExeOnly -InitialDirectory ([IO.Path]::GetDirectoryName($fprbPath))
    Show-Info "（3/4）選擇導出封裝批處理路徑..."
    $exptPath = Select-Folder -Description "選擇導出封裝批處理的文件夾"
    Show-Info "（4/4）選擇封裝結果路徑..."a
    $muxPath  = Select-Folder -Description "選擇導出封裝結果的文件夾"

    # 2. 導入素材
    Show-Info "導入素材文件（循環）"
    Write-Host "提示：僅第一個視頻文件會被用作主視頻流" -ForegroundColor Yellow
    Write-Host "      後續文件只添加音頻、字幕等軌道" -ForegroundColor Yellow
    
    $inputsAgg = ""   # 所有的 -i "path"
    $mapsAgg   = ""   # 所有的 -map xArgs
    $mapIndex  = 0
    $hasVideo  = $false

    while ($true) {
        $strmPath = Select-File -Title "選擇源文件（第 $($mapIndex+1) 個）"
        
        $result = Get-StreamArgs -FFprobePath $fprbPath -FilePath $strmPath -MapIndex $mapIndex -IsFirstVideo (-not $hasVideo)
        
        if ($result) {
            $inputsAgg += " -i `"$strmPath`""
            $mapsAgg   += " -map $mapIndex $($result.ArgumentsString)"
            
            if ($result.ContainsVideo) {
                $hasVideo = $true
                Show-Success "已添加主視頻流"
            }
            
            $mapIndex++
        }
        
        Write-Host ""
        $continue = Read-Host "繼續添加文件？輸入 'y' 確認，按 Enter 完成"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            break
        }
    }

    # 3. 輸出批處理
    # 3-1. 確定文件名
    $defaultName = [IO.Path]::GetFileNameWithoutExtension($strmPath) + "_mux"
    $outName = Read-Host "請輸入輸出文件名 (留空默認：$defaultName)"
    if ([string]::IsNullOrWhiteSpace($outName)) { $outName = $defaultName }
    
    # 3-2. 簡單校驗文件名
    if (-not (Test-FilenameValid $outName)) {
        Show-Warning "文件名包含非法字符，已自動修正"
        $invalid = [IO.Path]::GetInvalidFileNameChars()
        foreach ($c in $invalid) { $outName = $outName.Replace($c, '_') }
    }

    # 3-3. 選擇封裝容器
    Write-Host "`r`n選擇封裝容器:"
    Write-Host " 1：MP4（適合通用）"
    Write-Host " 2：MOV（適合剪輯）"
    Write-Host " 3：MKV（兼容字幕、字體）"
    Write-Host " 4：MXF（專業用途）"
    Write-Warning " ffmpeg 正在棄用 MP4 時間碼（pts）生成功能，屆時 MP4 格式選項將不可用"
    
    $containerExt = ""
    do {
        switch (Read-Host "請輸入選項（1/2/3/4）") {
            1 { $containerExt = ".mp4" }
            2 { $containerExt = ".mov" }
            3 { $containerExt = ".mkv" }
            4 { $containerExt = ".mxf" }
            default { Write-Warning "無效選項" }
        }
    }
    while ($containerExt -eq "")

    # 3-4. 生成命令與後期檢查
    
    # 構建最終命令
    # 結構：ffmpeg.exe inputs maps output
    $finalOutput = Join-Path $muxPath ($outName + $containerExt)
    $cmdLine = "& $(Get-QuotedPath $ffmpegPath) $inputsAgg $mapsAgg $(Get-QuotedPath $finalOutput)"

    # 兼容性檢查與自動修復
    if (($containerExt -in ".mp4", ".mov", ".mxf") -and $cmdLine -match "-c:t copy") {
        Show-Warning "檢測到字體流（-c:t copy），但 MP4/MOV/MXF 不支持"
        Write-Host "`r`n請選擇一個選項繼續："
        Write-Host " d：刪除導入語句"
        Write-Host " m：將容器格式更改為 MKV"
        Write-Host " Enter：忽略"

        $fix = Read-Host "請選擇..."
        if ($fix -eq 'd') {
            $cmdLine = $cmdLine.Replace("-c:t copy", "")
        }
        elseif ($fix -eq 'm') { 
            $containerExt = ".mkv"
            $cmdLine = $cmdLine.Replace(".mp4", ".mkv").Replace(".mov", ".mkv").Replace(".mxf", ".mkv")
            Show-Success "已切換為 MKV"
        }
    }

    if (($containerExt -in ".mp4", ".mov") -and $cmdLine -match "-c:s copy") {
        Show-Warning "檢測到字幕流 (-c:s copy)，MP4/MOV 支持較差，大概率無法封裝"
        Write-Host "`r`n請選擇一個選項繼續："
        Write-Host " d：刪除導入語句"
        Write-Host " m：將容器格式更改為 MKV"
        Write-Host " Enter：忽略"

        $fix = Read-Host "請選擇..."
        if ($fix -eq 'd') {
            $cmdLine = $cmdLine.Replace("-c:s copy", "")
        }
        elseif ($fix -eq 't') {
            $cmdLine = $cmdLine.Replace("-c:s copy", "-c:s:0 mov_text")
        }
    }
    
    # 生成文件名
    $batFilename = "ffmpeg_mux.bat"
    $batPath = Join-Path $exptPath $batFilename

    # 寫入 Bat 文件內容（去除 PowerShell 的 & 調用符，轉為 CMD 格式）
    $cmdContent = $cmdLine.TrimStart('& ') 
    $batContent = @"

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM ffmpeg 封裝工具
REM 生成時間：{0}
REM ========================================

echo.
echo 開始封裝任務...
echo.

{1}

echo.
echo ========================================
echo  批處理執行完畢！
echo ========================================
echo.

endlocal
echo 按任意鍵進入命令提示符，輸入 exit 退出...
cmd /k
"@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $cmdContent

    # 確保 ffmpeg 路徑帶引號
    #（雖然 $ffmpegPath 變量裡可能沒帶，但上面組合時加了）
    
    Show-Border
    Write-TextFile -Path $batPath -Content $batContent -UseBOM $true
    
    Show-Success "任務完成！"
    Show-Info "命令已保存至：$batPath"
    Write-Host "提示：如果音畫不同步，請在 -map 和 -c 之間添加 -itoffset <秒> 參數" -ForegroundColor DarkGray
    
    Pause
}

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按回車鍵退出"
}