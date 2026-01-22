# 檢測文件名是否符合 Windows 命名規則
function Test-FilenameValid {
    param([string]$Filename)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    return $Filename.IndexOfAny($invalid) -eq -1
}

# 安全的文件引用函數（確保有引號並轉義）
function Get-QuotedPath {
    param([string]$Path)
    return "`"$Path`""
}

# 若文件存在則確認是否刪除
function Confirm-FileDelete {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Show-Warning "檢測到已存在文件：$Path"
    $confirm = Read-Host " 是否刪除該文件以繼續？輸入 'y' 確認，其它任意鍵取消（永久刪除）"

    if ($confirm -ne 'y') {
        Show-Info "用戶取消操作，腳本終止"
        exit 1
    }

    Remove-Item $Path -Force
    Show-Success "已刪除舊文件：$Path"
}

function Select-File(
        [string]$Title = "選擇文件",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$ExeOnly,
        [switch]$AvsOnly,
        [switch]$VpyOnly,
        [switch]$DllOnly,
        [switch]$IniOnly,
        [switch]$BatOnly
    ) {
    
    # 若是文件路徑則取其父目錄；如果路徑不存在回到 Desktop
    if ($InitialDirectory) {
        if (Test-Path $InitialDirectory -PathType Leaf) {
            $InitialDirectory = Split-Path $InitialDirectory -Parent
        }
        if (-not (Test-Path $InitialDirectory -PathType Container)) {
            $InitialDirectory = [Environment]::GetFolderPath('Desktop')
        }
    }
    else {
        $InitialDirectory = [Environment]::GetFolderPath('Desktop')
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.InitialDirectory = $InitialDirectory
    $dialog.Multiselect = $false

    # 後綴名過濾
    if ($ExeOnly) { $dialog.Filter = 'exe files (*.exe)|*.exe' }
    elseif ($AvsOnly) { $dialog.Filter = 'avs files (*.avs)|*.avs' }
    elseif ($VpyOnly) { $dialog.Filter = 'vpy files (*.vpy)|*.vpy' }
    elseif ($DllOnly) { $dialog.Filter = 'dll files (*.dll)|*.dll' }
    elseif ($IniOnly) { $dialog.Filter = 'ini files (*.ini)|*.ini' }
    elseif ($BatOnly) { $dialog.Filter = 'bat Files (*.bat)|*.bat' }
    else { $dialog.Filter = 'All files (*.*)|*.*' }

    Write-Host " 選窗可能會在本窗口後面打開，這裡不要按回車"

    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        $choice = Read-Host "未選擇文件，按回車重試或輸入 'q' 強制退出"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

function Select-Folder([string]$Description = "選擇文件夾", [string]$InitialPath = [Environment]::GetFolderPath('Desktop')) {
    # (Put on top of script) Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialPath
    $dialog.ShowNewFolderButton = $true

    Write-Host " 選窗可能會在本窗口後面打開，這裡不要按回車"
    
    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (-not $path.EndsWith('\')) { $path += '\' }
            return $path
        }
        $choice = Read-Host "未選擇文件夾，按回車重試或輸入 'q' 強制退出"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

# 生成使用 Windows（CRLF 換行）、UTF-8 BOM 文本編碼的批處理
function Write-TextFile { # 需在 Core.ps1 寫入全局變量後運行
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [bool]$UseBOM = $true
    )
    
    # 必須使用 CRLF 換行符，否則 CMD 無法讀取（亂碼）
    $normalizedContent = $Content -replace "`r?`n", "`r`n"
    
    # 選擇編碼
    $encoding = if ($UseBOM) { $Global:utf8BOM } else { $Global:utf8NoBOM }
    
    # 寫入文件
    [System.IO.File]::WriteAllText($Path, $normalizedContent, $encoding)
    Show-Debug "編碼：$($encoding.EncodingName), 換行符：CRLF"
    Show-Success "文件已寫入：$Path"
}

# 驗證批處理文件格式
function Test-TextFileFormat {
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Show-Error "文件不存在：$Path"
        return $false
    }
    
    try {
        # 讀取文件內容
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        
        $hasUnixLF = $content -match "(?<!`r)`n"
        if ($hasUnixLF) {
            Write-Host "檢測到 Unix(LF) 換行符"
        }
        $hasMacCR = $content -match "`r(?!`n)"
        if ($hasMacCR) {
            Write-Host "檢測到 Mac(CR) 換行符"
        }
        # 統計 CR 和 LF 數量
        $crCount = ($content -split "`r").Count - 1
        $lfCount = ($content -split "`n").Count - 1
        if ($crCount -ne $lfCount) {
            Show-Warning "換行符 CR($crCount) 和 LF($lfCount) 數量不相等，執行時可能會亂碼"
        }
        
        # 返回驗證結果
        $isValid = (-not $hasUnixLF) -and (-not $hasMacCR) -and ($crCount -eq $lfCount)
        
        if ($isValid) {
            Show-Success "文件格式正確 (CRLF：$crCount)" -ForegroundColor Green
        }
        else {
            Show-Warning "文件格式有問題" -ForegroundColor Red
        }
        return $isValid
    }
    catch {
        Show-Error "驗證失敗：$_" -ForegroundColor Red
        return $false
    }
}

# 用 ffprobe 獲取媒體流元數據
function Get-StreamMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$FFprobePath,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$StreamType
    )
    
    # 驗證流文件/ffprobe存在
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Show-Error "文件不存在：$FilePath"
        return $null
    }
    if (-not (Test-Path -LiteralPath $FFprobePath)) {
        Show-Error "ffprobe 不存在：$FFprobePath"
        return $null
    }
    
    try { # 構建 ffprobe 命令參數
        $streamSelector = switch ($StreamType.ToLower()) {
            "v" { "v" }  # 視頻
            "a" { "a" }  # 音頻
            "s" { "s" }  # 字幕
            "t" { "t" }  # 字體
            default { $StreamType }
        }
        
        $arguments = @(
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-select_streams", $streamSelector,
            "`"$FilePath`""
        )
        
        Show-Debug "執行 ffprobe：$FFprobePath $arguments"
        
        # 執行 ffprobe 並捕獲輸出
        $result = & $FFprobePath @arguments 2>&1
        
        # 檢查是否有錯誤
        if ($LASTEXITCODE -ne 0) {
            Show-Warning "ffprobe 執行失敗（退出代碼: $LASTEXITCODE）：$result"
            return $null
        }
        
        # 解析 JSON 輸出
        $jsonOutput = $result | Out-String
        $metadata = $jsonOutput | ConvertFrom-Json
        
        # 如果沒有找到指定類型的流
        if (-not $metadata.streams -or $metadata.streams.Count -eq 0) {
            Show-Debug "未找到指定為 $StreamType 類型的流：$FilePath"
            return $null
        }
        
        # 返回第一個匹配的流信息（根據上下文，通常只需要第一個）
        $stream = $metadata.streams[0]
        
        # 構建返回對象
        $streamInfo = [PSCustomObject]@{
            Index      = if ($stream.index) { [int]$stream.index } else { 0 }
            CodecName  = if ($stream.codec_name) { $stream.codec_name } else { $null }
            CodecTag   = if ($stream.codec_tag_string) { $stream.codec_tag_string } else { $null }
            CodecType  = if ($stream.codec_type) { $stream.codec_type } else { $null }
            FrameRate  = if ($stream.r_frame_rate) { 
                # 將分數格式化為字符串（如 24000/1001）
                $frameRateStr = $stream.r_frame_rate.ToString()
                # 如果是整數（如 24/1），簡化為整數
                if ($frameRateStr -match '^(\d+)/1$') {
                    $matches[1]
                }
                else { $frameRateStr }
            }
            else { $null }
            Width      = if ($stream.width) { [int]$stream.width } else { $null }
            Height     = if ($stream.height) { [int]$stream.height } else { $null }
            Duration   = if ($stream.duration) { [double]$stream.duration } else { $null }
            BitRate    = if ($stream.bit_rate) { [int]$stream.bit_rate } else { $null }
            SampleRate = if ($stream.sample_rate) { [int]$stream.sample_rate } else { $null }
            Channels   = if ($stream.channels) { [int]$stream.channels } else { $null }
            Language   = if ($stream.tags -and $stream.tags.language) { $stream.tags.language } else { $null }
            RawData    = $stream  # 保留原始數據以備用
        }
        
        Show-Debug "獲取到流信息：$($streamInfo.CodecType) - $($streamInfo.CodecName)"
        if ($streamInfo.FrameRate) {
            Show-Debug "幀率：$($streamInfo.FrameRate)"
        }
        
        return $streamInfo
        
    }
    catch {
        Show-Error "解析 ffprobe 輸出時出錯：$_"
        Show-Debug "錯誤詳情：$($_.ScriptStackTrace)"
        return $null
    }
}

# 從 SVFI INI 文件中直接提取路徑用
function Convert-IniPath {
    param([string]$iniPath)
    
    # 先處理 Unicode 轉義
    $path = [regex]::Unescape($iniPath)
    
    # 移除可能存在的雙引號
    $path = $path.Trim('"')
    
    # 雙反換單反斜槓
    $path = $path -replace '\\\\', '\'
    return $path
}