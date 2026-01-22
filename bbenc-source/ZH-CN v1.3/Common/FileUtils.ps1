# 检测文件名是否符合 Windows 命名规则
function Test-FilenameValid {
    param([string]$Filename)
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    return $Filename.IndexOfAny($invalid) -eq -1
}

# 安全的文件引用函数（确保有引号并转义）
function Get-QuotedPath {
    param([string]$Path)
    return "`"$Path`""
}

# 若文件存在则确认是否删除
function Confirm-FileDelete {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Show-Warning "检测到已存在文件：$Path"
    $confirm = Read-Host " 是否删除该文件以继续？输入 'y' 确认，其它任意键取消（永久删除）"

    if ($confirm -ne 'y') {
        Show-Info "用户取消操作，脚本终止"
        exit 1
    }

    Remove-Item $Path -Force
    Show-Success "已删除旧文件：$Path"
}

function Select-File(
        [string]$Title = "选择文件",
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$ExeOnly,
        [switch]$AvsOnly,
        [switch]$VpyOnly,
        [switch]$DllOnly,
        [switch]$IniOnly,
        [switch]$BatOnly
    ) {
    
    # 若是文件路径则取其父目录；如果路径不存在回到 Desktop
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

    # 后缀名过滤
    if ($ExeOnly) { $dialog.Filter = 'exe files (*.exe)|*.exe' }
    elseif ($AvsOnly) { $dialog.Filter = 'avs files (*.avs)|*.avs' }
    elseif ($VpyOnly) { $dialog.Filter = 'vpy files (*.vpy)|*.vpy' }
    elseif ($DllOnly) { $dialog.Filter = 'dll files (*.dll)|*.dll' }
    elseif ($IniOnly) { $dialog.Filter = 'ini files (*.ini)|*.ini' }
    elseif ($BatOnly) { $dialog.Filter = 'bat Files (*.bat)|*.bat' }
    else { $dialog.Filter = 'All files (*.*)|*.*' }

    Write-Host " 选窗可能会在本窗口后面打开，这里不要按回车"

    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
        $choice = Read-Host "未选择文件，按回车重试或输入 'q' 强制退出"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

function Select-Folder([string]$Description = "选择文件夹", [string]$InitialPath = [Environment]::GetFolderPath('Desktop')) {
    # (Put on top of script) Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialPath
    $dialog.ShowNewFolderButton = $true

    Write-Host " 选窗可能会在本窗口后面打开，这里不要按回车"
    
    do {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (-not $path.EndsWith('\')) { $path += '\' }
            return $path
        }
        $choice = Read-Host "未选择文件夹，按回车重试或输入 'q' 强制退出"
        if ($choice -eq 'q') { exit 1 }
    }
    while ($true)
}

# 生成使用 Windows（CRLF 换行）、UTF-8 BOM 文本编码的批处理
function Write-TextFile { # 需在 Core.ps1 写入全局变量后运行
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [bool]$UseBOM = $true
    )
    
    # 必须使用 CRLF 换行符，否则 CMD 无法读取（乱码）
    $normalizedContent = $Content -replace "`r?`n", "`r`n"
    
    # 选择编码
    $encoding = if ($UseBOM) { $Global:utf8BOM } else { $Global:utf8NoBOM }
    
    # 写入文件
    [System.IO.File]::WriteAllText($Path, $normalizedContent, $encoding)
    Show-Debug "编码：$($encoding.EncodingName), 换行符：CRLF"
    Show-Success "文件已写入：$Path"
}

# 验证批处理文件格式
function Test-TextFileFormat {
    param([Parameter(Mandatory=$true)][string]$Path)
    
    if (-not (Test-Path -LiteralPath $Path)) {
        Show-Error "文件不存在：$Path"
        return $false
    }
    
    try {
        # 读取文件内容
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        
        $hasUnixLF = $content -match "(?<!`r)`n"
        if ($hasUnixLF) {
            Write-Host "检测到 Unix(LF) 换行符"
        }
        $hasMacCR = $content -match "`r(?!`n)"
        if ($hasMacCR) {
            Write-Host "检测到 Mac(CR) 换行符"
        }
        # 统计 CR 和 LF 数量
        $crCount = ($content -split "`r").Count - 1
        $lfCount = ($content -split "`n").Count - 1
        if ($crCount -ne $lfCount) {
            Show-Warning "换行符 CR($crCount) 和 LF($lfCount) 数量不相等，执行时可能会乱码"
        }
        
        # 返回验证结果
        $isValid = (-not $hasUnixLF) -and (-not $hasMacCR) -and ($crCount -eq $lfCount)
        
        if ($isValid) {
            Show-Success "文件格式正确 (CRLF：$crCount)" -ForegroundColor Green
        }
        else {
            Show-Warning "文件格式有问题" -ForegroundColor Red
        }
        return $isValid
    }
    catch {
        Show-Error "验证失败：$_" -ForegroundColor Red
        return $false
    }
}

# 用 ffprobe 获取媒体流元数据
function Get-StreamMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$FFprobePath,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$StreamType
    )
    
    # 验证流文件/ffprobe存在
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Show-Error "文件不存在：$FilePath"
        return $null
    }
    if (-not (Test-Path -LiteralPath $FFprobePath)) {
        Show-Error "ffprobe 不存在：$FFprobePath"
        return $null
    }
    
    try { # 构建 ffprobe 命令参数
        $streamSelector = switch ($StreamType.ToLower()) {
            "v" { "v" }  # 视频
            "a" { "a" }  # 音频
            "s" { "s" }  # 字幕
            "t" { "t" }  # 字体
            default { $StreamType }
        }
        
        $arguments = @(
            "-v", "quiet",
            "-print_format", "json",
            "-show_streams",
            "-select_streams", $streamSelector,
            "`"$FilePath`""
        )
        
        Show-Debug "执行 ffprobe：$FFprobePath $arguments"
        
        # 执行 ffprobe 并捕获输出
        $result = & $FFprobePath @arguments 2>&1
        
        # 检查是否有错误
        if ($LASTEXITCODE -ne 0) {
            Show-Warning "ffprobe 执行失败（退出代码: $LASTEXITCODE）：$result"
            return $null
        }
        
        # 解析 JSON 输出
        $jsonOutput = $result | Out-String
        $metadata = $jsonOutput | ConvertFrom-Json
        
        # 如果没有找到指定类型的流
        if (-not $metadata.streams -or $metadata.streams.Count -eq 0) {
            Show-Debug "未找到指定为 $StreamType 类型的流：$FilePath"
            return $null
        }
        
        # 返回第一个匹配的流信息（根据上下文，通常只需要第一个）
        $stream = $metadata.streams[0]
        
        # 构建返回对象
        $streamInfo = [PSCustomObject]@{
            Index      = if ($stream.index) { [int]$stream.index } else { 0 }
            CodecName  = if ($stream.codec_name) { $stream.codec_name } else { $null }
            CodecTag   = if ($stream.codec_tag_string) { $stream.codec_tag_string } else { $null }
            CodecType  = if ($stream.codec_type) { $stream.codec_type } else { $null }
            FrameRate  = if ($stream.r_frame_rate) { 
                # 将分数格式化为字符串（如 24000/1001）
                $frameRateStr = $stream.r_frame_rate.ToString()
                # 如果是整数（如 24/1），简化为整数
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
            RawData    = $stream  # 保留原始数据以备用
        }
        
        Show-Debug "获取到流信息：$($streamInfo.CodecType) - $($streamInfo.CodecName)"
        if ($streamInfo.FrameRate) {
            Show-Debug "帧率：$($streamInfo.FrameRate)"
        }
        
        return $streamInfo
        
    }
    catch {
        Show-Error "解析 ffprobe 输出时出错：$_"
        Show-Debug "错误详情：$($_.ScriptStackTrace)"
        return $null
    }
}

# 从 SVFI INI 文件中直接提取路径用
function Convert-IniPath {
    param([string]$iniPath)
    
    # 先处理 Unicode 转义
    $path = [regex]::Unescape($iniPath)
    
    # 移除可能存在的双引号
    $path = $path.Trim('"')
    
    # 双反换单反斜杠
    $path = $path -replace '\\\\', '\'
    return $path
}