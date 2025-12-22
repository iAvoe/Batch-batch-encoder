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
    $confirm = Read-Host " 是否删除该文件以继续？输入 'y' 确认，其它任意键取消（这不是移到回收站）"

    if ($confirm -ne 'y') {
        Show-Info "用户取消操作，脚本终止"
        exit 1
    }

    Remove-Item $Path -Force
    Show-Success "`r`n已删除旧文件：$Path"
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