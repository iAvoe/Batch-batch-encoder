<#
.SYNOPSIS
    ffprobe 影片源分析腳本
.DESCRIPTION
    分析源影片並導出到 %USERPROFILE%\temp_v_info(_is_mov).csv: 總幀數，寬，高，色彩空間，傳輸特定等。繁體在地化由繁化姬實現：https://zhconvert.org
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.4
#>

# .mov 格式支持 $ffprobeCSV.A-I + ...；其它格式支持 $ffprobeCSV.A-AA + ...
# 若同時檢測到 temp_v_info_is_mov.csv 與 temp_v_info.csv，則使用其中創建日期最新的文件
# $ffprobeCSV.A：stream (or not stream)
#            .B：width
#            .C：height  
#            .D：pixel format (pix_fmt)
#            .E：color_space
#            .F：color_transfer
#            .G：color_primaries
#            .H：avg_frame_rate | VOB：field_order
#            .I：MOV：nb_frames | VOB：avg_frame_rate | first frame count field (others)
#            .J：interlaced_frame | VOB：nb_frames
#            .K：top_field_first | VOB：N/A
#            .AA：NUMBER_OF_FRAMES-eng (only for non-MOV files)
# $sourceCSV.SourcePath：影片源路徑
# $sourceCSV.UpstreamCode：指定管道上遊程序
# $sourceCSV.Avs2PipeModDLLPath：Avs2PipeMod 需要的 avisynth.dll
# $sourceCSV.SvfiConfigPath：one_line_shot_args（SVFI）的渲染配置 X:\SteamLibrary\steamapps\common\SVFI\Configs\*.ini

# 載入共用代碼，包括 $utf8NoBOM、Get-QuotedPath、Select-File、Select-Folder...
. "$PSScriptRoot\Common\Core.ps1"

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

# 利用 ffprobe 檢測真實的影片檔案封裝格式，無視后綴名（封裝格式用大寫字母表示）
function Test-VideoContainerFormat {
    param (
        [Parameter(Mandatory=$true)][string]$ffprobePath,
        [Parameter(Mandatory=$true)][string]$videoSource
    )

    if (-not (Test-Path $ffprobePath)) {
        throw "Test-VideoContainerFormat：ffprobe.exe 不存在（$ffprobePath）"
    }
    if (-not (Test-Path $videoSource)) {
        throw "Test-VideoContainerFormat：輸入影片不存在（$videoSource）"
    }
    Show-Info ("Test-VideoContainerFormat：導入影片 $videoSource")
    $quotedVideoSource = Get-QuotedPath $videoSource

    try {
        # 使用 JSON 輸入分析
        $ffprobeJson = & $ffprobePath -hide_banner -v quiet -show_format -print_format json $quotedVideoSource 2>null

        if ($LASTEXITCODE -eq 0) { # ffprobe 正常退出，分析結果存在
            $formatInfo = $ffprobeJson | ConvertFrom-Json
            $formatName = $formatInfo.format.format_name

            # VOB 格式檢測
            if ($formatName -match "mpeg") {
                # 進一步檢測
                $ffprobeText = & $ffprobePath -hide_banner $quotedVideoSource 2>&1
                # 檔案名含 VTS_ 字樣（不確定是否全是大寫，因此不用 cmatch）
                # $hasVTSFileName = $filename -match "^VTS_"
                # 元數據含 dvd_nav 字樣（高機率是 VOB）
                $hasDVD = $false
                # 元數據含 mpeg2video 字樣（高機率是 VOB）
                $hasMPEG2 = $false

                foreach ($line in $ffprobeText) {
                    if ($line -match "mpeg2video") {
                        $hasMPEG2 = $true
                    }
                    if ($line -match "dvd_nav") {
                        $hasDVD = $true
                    }
                }

                # VOB 通常包含 DVD 導航包或特定的流結構
                if ($hasDVD -or $hasMPEG2) {
                    Show-Info "Test-VideoContainerFormat：檢測到 VOB 格式（DVD 影片）"
                    return "VOB"
                }
                elseif ($hasMPEG2) {
                    Show-Warning "Test-VideoContainerFormat：源使用 MPEG2 編碼，將視作 VOB 格式（DVD 影片）"
                    return "VOB"
                }
                elseif ($hasDVD) {
                    Show-Warning "Test-VideoContainerFormat：源非 MPEG2 編碼，但含有 DVD 導航標識，將視作 VOB 格式（DVD 影片）"
                    return "VOB"
                }
                else {
                     Show-Warning "Test-VideoContainerFormat：源非 MPEG2 編碼，且無 DVD 導航標識，將視作一般封裝格式"
                    return "std"
                }
            }
            elseif ($formatName -match "mov|mp4|m4a|3gp|3g2|mj2") {
                if ($formatName -match "qt" -or $ext -eq ".mov") {
                    Show-Info "Test-VideoContainerFormat：檢測到 MOV 格式"
                    return "MOV"
                }
                else {
                    Show-Info "Test-VideoContainerFormat：檢測到 MP4 格式"
                    return "MP4"
                }
            }
            elseif ($formatName -match "matroska") {
                Show-Info "Test-VideoContainerFormat：檢測到 MKV 格式"
                return "MKV"
            }
            elseif ($formatName -match "webm") {
                Show-Info "Test-VideoContainerFormat：檢測到 WebM 格式"
                return "WebM"
            }
            elseif ($formatName -match "avi") {
                Show-Info "Test-VideoContainerFormat：檢測到 AVI 格式"
                return "AVI"
            }
            elseif ($formatName -match "ivf") {
                Show-Info "Test-VideoContainerFormat：檢測到 ivf 格式"
                return "ivf"
            }
            elseif ($formatName -match "hevc") {
                Show-Info "Test-VideoContainerFormat：檢測到 hevc 格式"
                return "hevc"
            }
            elseif ($formatName -match "h264" -or $formatName -match "avc") {
                Show-Info "Test-VideoContainerFormat：檢測到 avc 格式"
                return "avc"
            }
            return $formatName
        }
        else { # ffprobe 失敗
            throw "Test-VideoContainerFormat：ffprobe 執行或 JSON 解析失敗"
        }
    }
    catch {
        throw ("Test-VideoContainerFormat：檢測失敗" + $_)
    }
}

# 主程式
function Main {
    Show-Border
    Write-Host ("ffprobe 源讀取工具，導出 " + $Global:TempFolder + "temp_v_info(_is_mov).csv 以備用") -ForegroundColor Cyan
    Show-Border
    Write-Host ""

    # Show-Info "常用編碼命令範例："
    # Write-Host "ffmpeg -i [輸入] -an -f yuv4mpegpipe -strict unofficial - | x265.exe --y4m - -o"
    # Write-Host "vspipe [腳本.vpy] --y4m - | x265.exe --y4m - -o"
    # Write-Host "avs2pipemod [腳本.avs] -y4mp | x265.exe --y4m - -o"
    # Write-Host ""

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
    do {
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
    while ($true)
    
    # 獲取上遊程序代號（寫入 CSV）；為 Avs2PipeMod 導入必須的 DLL
    $upstreamCode = $null
    $Avs2PipeModDLL = $null
    $OneLineShotArgsINI = $null
    $isScriptUpstream =
        $selectedType.Name -in @('vspipe', 'avs2yuv', 'avs2pipemod')

    switch ($selectedType.Name) {
        'ffmpeg'      { $upstreamCode = 'a' }
        'vspipe'      { $upstreamCode = 'b' }
        'avs2yuv'     { $upstreamCode = 'c' }
        'avs2pipemod' {
            $upstreamCode = 'd'
            Show-Info "請指定 avisynth.dll 的路徑..."
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
            Show-Success "已記錄 avisynth.dll 路徑：$Avs2PipeModDLL"
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

    # 定義變數
    $videoSource = $null # ffprobe 將分析這個影片檔案
    $scriptSource = $null # 腳本文件路徑，如果有則在導出的 CSV 中覆蓋影片源
    $encodeImportSourcePath = $null
    $svfiTaskId = $null

    # vspipe / avs2yuv / avs2pipemod：提供生成無濾鏡腳本選項
    if ($isScriptUpstream) {
        do {
            # 選擇影片源文件（ffprobe 分析）
            Show-Info "選擇（腳本引用的）影片源文件（ffprobe 將分析此文件）"
            while ($null -eq $videoSource) {
                $videoSource = Select-File -Title "選擇影片源文件（例如 .mp4/.mkv/.mov）"
                if ($null -eq $videoSource) { Show-Error "未選擇影片檔案" }
            }
        
            # 詢問用戶是否要生成無濾鏡腳本
            $mode = Read-Host "輸入 'y' 導入自訂腳本，輸入 'n' 或 Enter 為影片源生成無濾鏡腳本"
        
            if ($mode -eq 'y') { # 導入自訂腳本
                Show-Warning "由於腳本支持的導入源路徑的種類繁多，如先定義路徑變數或直接寫入、`r`n 不同解析器、多種字面意義符搭配不同字串引號、多影片源等條件組合起來過於複雜，`r`n 因此請自行檢查腳本中的影片源是否真實存在`r`n"
                do {
                    $scriptSource = Select-File -Title "定位腳本文件（.avs/.vpy...）"
                    if (-not $scriptSource) {
                        Show-Error "未選擇文件"
                        continue
                    }
                
                    # 驗證文件副檔名
                    $ext = [IO.Path]::GetExtension($scriptSource).ToLower()
                    if ($selectedType.Name -in @('avs2yuv', 'avs2pipemod') -and $ext -ne '.avs') {
                        Show-Error "對於 $($selectedType.Name)，需要 .avs 腳本文件"
                        $scriptSource = $null
                    }
                    elseif ($selectedType.Name -eq 'vspipe' -and $ext -ne '.vpy') {
                        Show-Error "對於 vspipe，需要 .vpy 腳本文件"
                        $scriptSource = $null
                    }
                }
                while (-not $scriptSource)
            
                Show-Success "已選擇腳本文件：$scriptSource"
                # 注意：影片源 $videoSource 仍然用於 ffprobe
            }
            # 生成無濾鏡腳本
            elseif ([string]::IsNullOrWhiteSpace($mode) -or $mode -eq 'n') {
                Show-Warning "AviSynth(+) 默認不自帶 LSMASHSource.dll（影片導入濾鏡）請保證該文件存在，"
                Write-Host " AVS 安裝路徑為：C:\Program Files (x86)\AviSynth+\plugins64+\" -ForegroundColor Yellow
                Write-Host " 下載並解壓 64bit 版：https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works/releases`r`n" -ForegroundColor Magenta
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
            }
            else {
                Show-Warning "無效輸入"
                continue
            }
            break
        }
        while ($true)

        $encodeImportSourcePath = $scriptSource
    }
    # SVFI：從 INI 文件中讀取影片路徑，以及 task_id
    elseif ($OneLineShotArgsINI -and (Test-Path -LiteralPath $OneLineShotArgsINI)) { 
        # SVFI ini 文件中的影片路徑（實際上內容為單行）：gui_inputs="{
        #     \"inputs\": [{
        #         \"task_id\": \"必須獲取並賦值到 CSV\",
        #         \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\影片.mp4\",
        #         \"is_surveillance_folder\": false
        #     }]
        # }"
        # 讀取文件並找到 gui_inputs 行，如：
        # gui_inputs="{\"inputs\": [{\"task_id\": \"798_2aa174\", \"input_path\": \"X:\\\\Video\\\\\\u5176\\u5b83-\\u52a8\\u6f2b\\u753b\\u516c\\u79cd\\\\[Airota][Yuru Yuri\\u3001][OVA][BDRip 1080p AVC AAC][CHS].mp4\", \"is_surveillance_folder\": false}]}"
        Show-Info " 將嘗試從 SVFI 渲染配置 INI 中讀取影片源路徑..."

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
            Show-Success "已選擇影片源文件：$videoSource"
            break
        }
        while ($true)

        $encodeImportSourcePath = $videoSource
    }

    # 定位 ffprobe 程序
    Show-Info "定位 ffprobe.exe..."
    do {
        $ffprobePath =
            Select-File -Title "定位 ffprobe.exe" -InitialDirectory ([Environment]::GetFolderPath('ProgramFiles')) -ExeOnly
        if (-not (Test-Path -LiteralPath $ffprobePath)) {
            Show-Warning "找不到 ffprobe 可執行文件，請重試"
        }
    }
    while (-not (Test-Path -LiteralPath $ffprobePath))

    # 檢測封裝文件類型
    $realFormatName = Test-VideoContainerFormat -ffprobePath $ffprobePath -videoSource $videoSource
    $isMOV = ($realFormatName -like "MOV")
    $isVOB = ($realFormatName -like "VOB")
    # if ($isMOV) { Show-Debug "導入影片 $videoSource 的封裝格式為 MOV" }
    # elseif ($isVOB -like "VOB") { Show-Debug "導入影片 $videoSource 的封裝格式為 VOB" }
    # else { Show-Debug "導入影片 $videoSource 的封裝格式非 MOV、VOB" }

    # 根據封裝文件類型選用 ffprobe 命令、定義檔案名
    $ffprobeArgs =
        if ($isMOV) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,interlaced_frame,top_field_first', '-of', 'csv'
        )}
        elseif ($isVOB) {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,field_order', '-of', 'csv'
        )}
        else {@(
            '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
            'stream=width,height,pix_fmt,color_space,color_transfer,color_primaries,avg_frame_rate,nb_frames,interlaced_frame,top_field_first:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
            '-of', 'csv'
        )}
    # $ffprobeArgsDebug =
    #    if ($isMOV) {@(
    #        '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
    #        'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries', '-of', 'ini'
    #    )}
    #    else {@(
    #        '-i', $videoSource, '-select_streams', 'v:0', '-v', 'error', '-hide_banner', '-show_streams', '-show_entries',
    #        'stream=width,height,pix_fmt,avg_frame_rate,nb_frames,color_space,color_transfer,color_primaries:stream_tags=NUMBER_OF_FRAMES,NUMBER_OF_FRAMES-eng',
    #        '-of', 'ini'
    #    )}
    
    # 由於 ffprobe 讀取不同源所產生的列數不一，導致讀取額外插入的資訊隨機錯位，因此需要獨立的 CSV（s_info）來儲存源資訊
    $sourceCSVExportPath = Join-Path $Global:TempFolder "temp_s_info.csv"
    $ffprobeCSVExportPath =
        if ($isMOV) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv"
        }
        elseif ($isVOB) {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.csv"
        }
        else {
            Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv"
        }
    # $ffprobeCSVExportPathDebug =
    #     if ($isMOV) {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov_debug.csv"
    #     }
    #     else {
    #         Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_debug.csv"
    #     }

    # 若 CSV 已存在，要求手動確認後清理，避免覆蓋
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_mov.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info_is_vob.csv")
    Confirm-FileDelete (Join-Path -Path $Global:TempFolder -ChildPath "temp_v_info.csv")
    Confirm-FileDelete $sourceCSVExportPath

    # 執行 ffprobe 並插入影片源路徑
    try {
        $ffprobeOutputCSV = (& $ffprobePath @ffprobeArgs).Trim()
        # $ffprobeOutputCSVDebug = (& $ffprobePath @ffprobeArgsDebug).Trim()

        # 構建源 CSV 行
        $sourceInfoCSV = @"
"$encodeImportSourcePath",$upstreamCode,"$Avs2PipeModDLL","$OneLineShotArgsINI","$svfiTaskId"
"@

        Write-TextFile -Path $ffprobeCSVExportPath -Content $ffprobeOutputCSV -UseBOM $true
        # [System.IO.File]::WriteAllLines($ffprobeCSVExportPathDebug, $ffprobeOutputCSVDebug)

        Write-TextFile -Path $sourceCSVExportPath -Content $sourceInfoCSV -UseBOM $true
        Show-Success "CSV 文件已生成：$ffprobeCSVExportPath`n$sourceCSVExportPath"

        # 驗證換行符
        Show-Debug "驗證 CSV 檔案格式..."
        if (-not (Test-TextFileFormat -Path $ffprobeCSVExportPath)) {
            return
        }
        if (-not (Test-TextFileFormat -Path $sourceCSVExportPath)) {
            return
        }
    }
    catch { throw "ffprobe 執行失敗：$_" }

    Write-Host ""
    Show-Success "腳本執行完成！"
    Read-Host "按 Enter 退出"
}

try { Main }
catch {
    Show-Error "腳本執行出錯：$_"
    Write-Host "錯誤詳情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按 Enter 退出"
}