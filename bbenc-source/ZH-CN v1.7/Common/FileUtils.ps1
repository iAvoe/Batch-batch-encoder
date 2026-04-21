# 调用 Test-Path 前先确保变量名非空或 null
function Test-NullablePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return Test-Path -LiteralPath $Path }
    catch { return $false }
}

# UTF-8 JSON 读写实现
function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 10
    $utf8 = [System.Text.UTF8Encoding]::new($true) # 带 BOM
    [System.IO.File]::WriteAllText($Path, $json, $utf8)
}

# 验证 JSON 文件格式
function Test-JsonFileFormat {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Show-Error "文件不存在：$Path"
        return $false
    }
    try {
        $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        Show-Debug "JSON 文件验证通过：$Path"
        return $true
    }
    catch {
        Show-Error "JSON 文件格式错误：$Path"
        Write-Host $_ -ForegroundColor Red
        return $false
    }
}

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
    do {
        $confirm = Read-Host " 是否删除该文件以继续？输入 'y' 永久删除，输入 'q' 取消"
        if ('y' -eq $confirm) { break }
        elseif ('q' -eq $confirm) {
            Show-Info "取消操作，脚本终止"
            exit 1
        }
    } while ('y' -ne $confirm)

    Remove-Item $Path -Force
    Show-Success "已删除旧文件：$Path"
}

# 尝试在脚本所在目录和 PATH 变量中模糊匹配含有特征名的 .exe 文件
function Find-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$Keyword,
        [string[]]$SearchPaths = @(),
        [switch]$IncludePathEnv
    )

    # 收集所有要搜索的目录
    $allPaths = New-Object System.Collections.ArrayList

    # 用户指定的额外路径 + 环境变量 PATH 中的目录（如果启用）
    foreach ($p in $SearchPaths) {
        if (Test-Path -Path $p -PathType Container) {
            [void]$allPaths.Add($p)
        }
    }
    if ($IncludePathEnv) {
        $envPaths = $env:Path -split ';'
        foreach ($p in $envPaths) {
            if ([string]::IsNullOrWhiteSpace($p)) { continue }
            $p = $p.trim()
            if (Test-Path -LiteralPath $p -PathType Container) {
                [void]$allPaths.Add($p)
            }
        }
    }

    # 去重
    if (@($allPaths).Count -gt 1) {
        $allPaths = $allPaths | Select-Object -Unique
    }

    # 在每条路径中搜索 *.exe，并筛选文件名包含关键字的文件
    foreach ($dir in $allPaths) {
        try {
            $hits = Get-ChildItem -Path $dir -Filter *.exe -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$Keyword*" }

            if ($hits) { # 返回首个匹配项
                return $hits[0].FullName
            }
        }
        catch { continue } # 忽略无法访问的目录
    }
    Write-Host " Find-Tool：脚本所在位置、环境变量与用户指定路径中均未发现 $keyword" -ForegroundColor DarkGray
    return $null
}

function Invoke-AutoSearch {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [Parameter(Mandatory = $true)][string]$ScriptDir
    )
    <#
    .SYNOPSIS
        自动搜索工具路径（不包含交互）
    .DESCRIPTION
        在脚本目录、额外路径和 PATH 中搜索包含指定关键字的可执行文件。
        返回找到的路径，若未找到则返回 $null。
        额外路径（需手动在 Common/Core.ps1 中定义。
    .PARAMETER ToolName
        工具名称（用于关键字匹配和在 ToolExtraSearchPaths 中查找额外路径）
    .PARAMETER ScriptDir
        脚本所在目录（通常传入 $scriptDir）
    #>
    # 构建搜索路径列表：脚本目录 + 额外路径
    $searchPaths = @($ScriptDir)
    if ($Global:ToolExtraSearchPaths.ContainsKey($ToolName)) {
        $searchPaths += $Global:ToolExtraSearchPaths[$ToolName]
    }
    return Find-Tool -Keyword $ToolName -SearchPaths $searchPaths -IncludePathEnv
}

#　通用的文件选择逻辑
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
    Write-Host " 命令行窗口可能会失焦，点击命令行窗口以恢复输入光标" -ForegroundColor DarkGray

    # 若是文件路径则取其父目录；如果路径不存在回到 Desktop
    if ($InitialDirectory) {
        if (Test-Path $InitialDirectory -PathType Leaf) {
            $InitialDirectory = Split-Path $InitialDirectory -Parent
        }
        if (-not (Test-Path $InitialDirectory -PathType Container)) {
            $InitialDirectory = [Environment]::GetFolderPath('Desktop')
        }
    }
    else { $InitialDirectory = [Environment]::GetFolderPath('Desktop') }

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

    # 创建一个隐藏的 TopMost 窗口作为 owner
    $form = New-Object System.Windows.Forms.Form
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.WindowState = 'Minimized'

    while ($true) {
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }

        # 恢复控制台焦点（VSCode 无效）
        $hwnd = [WinAPI]::GetConsoleWindow()
        [WinAPI]::SetForegroundWindow($hwnd) | Out-Null

        if ('q' -eq (Read-Host "未选择文件，按回车重试或输入 'q' 强制退出")) { exit 1 }
    }
}

function Select-Folder(
        [string]$Description = "选择文件夹",
        [string]$InitialPath = [Environment]::GetFolderPath('Desktop')
    ) {
    Write-Host " 命令行窗口可能会失焦，点击命令行窗口以恢复输入光标" -ForegroundColor DarkGray
    # UI.ps1: Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.SelectedPath = $InitialPath
    $dialog.ShowNewFolderButton = $true

    # 创建一个隐藏的 TopMost 窗口作为 owner
    $form = New-Object System.Windows.Forms.Form
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.WindowState = 'Minimized'

    while ($true) {
        $result = $dialog.ShowDialog($form)
        
        # 恢复控制台焦点（VSCode 无效）
        $hwnd = [WinAPI]::GetConsoleWindow()
        [WinAPI]::SetForegroundWindow($hwnd) | Out-Null

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $path = $dialog.SelectedPath
            if (-not $path.EndsWith('\')) { $path += '\' }
            return $path
        }

        $choice = Read-Host "未选择文件夹，按回车重试或输入 'q' 强制退出"
        if ($choice -eq 'q') { exit 1 }
    }
}

# 生成使用 Windows（CRLF 换行）、UTF-8 BOM 文本编码的批处理
function Write-TextFile { # 需在 Core.ps1 写入全局变量后运行
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content,
        [bool]$UseBOM = $true
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Error "Write-TextFile - 文件写入失败：空路径"
        return
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        Write-Error "Write-TextFile - 文件写入失败：空内容"
        return
    }

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
        Show-Error "验证失败：$_"
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
            (Get-QuotedPath $FilePath)
            
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