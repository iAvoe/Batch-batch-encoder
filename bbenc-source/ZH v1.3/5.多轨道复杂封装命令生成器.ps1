<#
.SYNOPSIS
    基于 ffmpeg、ffprobe 的多轨道复杂封装命令生成器
.DESCRIPTION
    封装对过视音频、字幕字体批处理的工具，运行批处理即可完成封装操作
.AUTHOR
    iAvoe - https://github.com/iAvoe
.VERSION
    1.3
#>

# 加载共用代码
. "$PSScriptRoot\Common\Core.ps1"

# 检测帧率值是否正常
function Test-FrameRateValid {
    param([string]$fr)
    if (-not $fr) { return $false }

    # 排除 0/0 或 0
    if ($fr -match '^(0(/0)?|0(\.0+)?)$') { return $false }

    # 允许分数如 24000/1001、允许整数 24、允许小数 23.976
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


# 调用 ffprobe 获取指定流的信息，直接返回对象，不写临时文件
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
    
    # 检查是否为视频容器格式
    $isVideoContainer = $ext -in @('.mkv', '.mp4', '.mov', '.f4v', '.flv', '.avi', '.m3u', '.mxv')
    $isAudioContainer = $ext -in @('.m4a', '.mka', '.mks')
    $isSingleFile = -not ($isVideoContainer -or $isAudioContainer)
    
    Show-Debug "分析文件：$FilePath（扩展名：$ext）"
    
    # 处理视频容器
    if ($isVideoContainer) {
        Show-Info "视频容器格式，分析所有流..."
        
        # 视频流
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        if ($vData -and $IsFirstVideo) {
            $codec = if ($vData.CodecTag -and $vData.CodecTag -ne "0") { 
                $vData.CodecTag 
            }
            else { 
                $vData.CodecName 
            }
            
            Show-Success "视频流：$codec"
            if ($vData.FrameRate) { # 默认视频容器格式一定含帧率信息
                $argsResult += "-r $($vData.FrameRate) -c:v copy"
            }
            else {
                $argsResult += "-c:v copy"
            }
            $hasVideo = $true
        }
        elseif ($vData) {
            Show-Warning "跳过额外视频流（仅保留第一个视频）"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "发现音频流"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "发现字幕流"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isAudioContainer) { # 处理音频容器
        Show-Info "发现音频容器格式..."
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a") {
            Show-Success "发现音频流"
            $argsResult += "-c:a copy"
        }
        
        if (Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "s") {
            Show-Success "发现字幕流"
            $argsResult += "-c:s copy"
        }
    }
    elseif ($isSingleFile) { # 处理单文件（未封装视频、音频、字幕等）
        Show-Info "单文件格式，分析流类型..."
        
        # 尝试检测文件格式
        $vData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "v"
        
        if ($vData -and $IsFirstVideo) {
            Show-Success "发现视频流：$($vData.CodecName)"
            
            # 获取当前文件的帧率
            $currentFrameRate = $vData.FrameRate
            $isCurrentFrameRateValid = Test-FrameRateValid -fr $currentFrameRate
            
            # 帧率处理逻辑
            if ($isCurrentFrameRateValid) {
                # 情况1：单文件本身有有效帧率
                Show-Info "使用文件自带的帧率：$currentFrameRate"
                $frameRate = $currentFrameRate
            }
            else {
                # 情况2：单文件没有有效帧率，提供选择
                Show-Warning "未封装的视频流不具备有效帧率信息"
                
                # 提供用户选择
                Write-Host "`n选择帧率来源：" -ForegroundColor Cyan
                Write-Host "1：手动输入帧率" -ForegroundColor Yellow
                Write-Host "2：从其他封装视频文件读取（推荐）" -ForegroundColor Yellow
                Write-Host "3：使用常用预设帧率" -ForegroundColor Yellow
                Write-Host "q：跳过此文件" -ForegroundColor DarkGray
                
                $choice = Read-Host "`n选择（1-3，q）"
                
                switch ($choice.ToLower()) {
                    '1' { # 手动输入帧率
                        $manualFrameRate = Read-Host "请输入帧率（整数/小数/分数，如 24、23.976、24000/1001）"
                        if (Test-FrameRateValid -fr $manualFrameRate) {
                            $frameRate = $manualFrameRate
                        }
                        else {
                            Show-Error "无效的帧率格式，将跳过此文件"
                            return $null
                        }
                    }
                    '2' { # 从其他文件读取帧率
                        Show-Info "选择一个包含帧率信息的封装视频文件（.mp4/.mov/.flv/...）"
                        $containerFile = Select-File -Title "选择封装视频文件以读取帧率"
                        
                        if ($containerFile -and (Test-Path -LiteralPath $containerFile)) {
                            $frameRate = Get-FrameRateFromContainer -FFprobePath $FFprobePath -FilePath $containerFile
                            if (-not $frameRate) {
                                Show-Error "无法从所选文件读取有效帧率，将跳过此文件"
                                return $null
                            }
                            Show-Info "从参考文件读取帧率：$frameRate"
                        }
                        else {
                            Show-Error "未选择有效文件，将跳过此文件"
                            return $null
                        }
                    }
                    '3' { # 选择常见帧率
                        Write-Warning "帧率必须与源完全一致，否则视频无法正确播放"
                        Write-Host "`n常用帧率预设：" -ForegroundColor Cyan
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

                        $presetChoice = Read-Host "选择预设帧率（1-9，a-b）"
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
                                Show-Error "无效选择，将跳过此文件"
                                return $null
                            }
                        }
                    }
                    'q' {
                        Show-Info "用户取消，跳过此文件"
                        return $null
                    }
                    default {
                        Show-Error "无效选择，将跳过此文件"
                        return $null
                    }
                }
            }
            
            # 添加 ffmpeg 帧率参数
            if ($frameRate) {
                $argsResult += "-r $frameRate -c:v copy"
                $hasVideo = $true
            }
            else {
                Show-Warning "未设置帧率，大概率会导致播放问题"
                $argsResult += "-c:v copy"
                $hasVideo = $true
            }
        }
        elseif (-not $vData) { # 尝试音频流
            $aData = Get-StreamMetadata -FFprobePath $FFprobePath -FilePath $FilePath -StreamType "a"
            if ($aData) {
                Show-Success "发现音频流：$($aData.CodecName)"
                $argsResult += "-c:a copy"
            }
        }
        
        if ($ext -in @('.srt', '.ass', '.ssa')) {
            Show-Success "字幕文件：$ext"
            $argsResult += "-c:s copy"
        }
        elseif ($ext -in @('.ttf', '.ttc', '.otf')) {
            Show-Success "字体文件：$ext"
            $argsResult += "-c:t copy"
        }
    }
    else {
        Show-Warning "未识别的源，无法处理"
        return $null
    }
    
    if ($argsResult.Count -eq 0) {
        Show-Warning "文件未生成有效参数：$FilePath"
        return $null
    }
    
    return [PSCustomObject]@{
        ArgumentsString = $argsResult -join " "
        ContainsVideo   = $hasVideo
    }
}

function Main {
    Show-Border
    Show-Info "基于 ffmpeg 的多轨道封装命令生成器"
    Show-Border
    
    # 1. 初始化路径与工具
    Show-Info "导入工具和选择路径"
    Show-Info "（1/4）导入 ffprobe.exe..."
    $fprbPath = Select-File -Title "选择 ffprobe.exe" -ExeOnly
    Show-Info "（2/4）导入 ffmpeg.exe..."
    $ffmpegPath = Select-File -Title "选择 ffmpeg.exe" -ExeOnly -InitialDirectory ([IO.Path]::GetDirectoryName($fprbPath))
    Show-Info "（3/4）选择导出封装批处理路径..."
    $exptPath = Select-Folder -Description "选择导出封装批处理的文件夹"
    Show-Info "（4/4）选择封装结果路径..."a
    $muxPath  = Select-Folder -Description "选择导出封装结果的文件夹"

    # 2. 导入素材
    Show-Info "导入素材文件（循环）"
    Write-Host "提示：仅第一个视频文件会被用作主视频流" -ForegroundColor Yellow
    Write-Host "      后续文件只添加音频、字幕等轨道" -ForegroundColor Yellow
    
    $inputsAgg = ""   # 所有的 -i "path"
    $mapsAgg   = ""   # 所有的 -map xArgs
    $mapIndex  = 0
    $hasVideo  = $false

    while ($true) {
        $strmPath = Select-File -Title "选择源文件（第 $($mapIndex+1) 个）"
        
        $result = Get-StreamArgs -FFprobePath $fprbPath -FilePath $strmPath -MapIndex $mapIndex -IsFirstVideo (-not $hasVideo)
        
        if ($result) {
            $inputsAgg += " -i `"$strmPath`""
            $mapsAgg   += " -map $mapIndex $($result.ArgumentsString)"
            
            if ($result.ContainsVideo) {
                $hasVideo = $true
                Show-Success "已添加主视频流"
            }
            
            $mapIndex++
        }
        
        Write-Host ""
        $continue = Read-Host "继续添加文件？输入 'y' 确认，按 Enter 完成"
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            break
        }
    }

    # 3. 输出批处理
    # 3-1. 确定文件名
    $defaultName = [IO.Path]::GetFileNameWithoutExtension($strmPath) + "_mux"
    $outName = Read-Host "请输入输出文件名 (留空默认：$defaultName)"
    if ([string]::IsNullOrWhiteSpace($outName)) { $outName = $defaultName }
    
    # 3-2. 简单校验文件名
    if (-not (Test-FilenameValid $outName)) {
        Show-Warning "文件名包含非法字符，已自动修正"
        $invalid = [IO.Path]::GetInvalidFileNameChars()
        foreach ($c in $invalid) { $outName = $outName.Replace($c, '_') }
    }

    # 3-3. 选择封装容器
    Write-Host "`r`n选择封装容器:"
    Write-Host " 1：MP4（适合通用）"
    Write-Host " 2：MOV（适合剪辑）"
    Write-Host " 3：MKV（兼容字幕、字体）"
    Write-Host " 4：MXF（专业用途）"
    Write-Warning " ffmpeg 正在弃用 MP4 时间码（pts）生成功能，届时 MP4 格式选项将不可用"
    
    $containerExt = ""
    do {
        switch (Read-Host "请输入选项（1/2/3/4）") {
            1 { $containerExt = ".mp4" }
            2 { $containerExt = ".mov" }
            3 { $containerExt = ".mkv" }
            4 { $containerExt = ".mxf" }
            default { Write-Warning "无效选项" }
        }
    }
    while ($containerExt -eq "")

    # 3-4. 生成命令与后期检查
    
    # 构建最终命令
    # 结构：ffmpeg.exe inputs maps output
    $finalOutput = Join-Path $muxPath ($outName + $containerExt)
    $cmdLine = "& $(Get-QuotedPath $ffmpegPath) $inputsAgg $mapsAgg $(Get-QuotedPath $finalOutput)"

    # 兼容性检查与自动修复
    if (($containerExt -in ".mp4", ".mov", ".mxf") -and $cmdLine -match "-c:t copy") {
        Show-Warning "检测到字体流（-c:t copy），但 MP4/MOV/MXF 不支持"
        Write-Host "`r`n请选择一个选项继续："
        Write-Host " d：删除导入语句"
        Write-Host " m：将容器格式更改为 MKV"
        Write-Host " Enter：忽略"

        $fix = Read-Host "请选择..."
        if ($fix -eq 'd') {
            $cmdLine = $cmdLine.Replace("-c:t copy", "")
        }
        elseif ($fix -eq 'm') { 
            $containerExt = ".mkv"
            $cmdLine = $cmdLine.Replace(".mp4", ".mkv").Replace(".mov", ".mkv").Replace(".mxf", ".mkv")
            Show-Success "已切换为 MKV"
        }
    }

    if (($containerExt -in ".mp4", ".mov") -and $cmdLine -match "-c:s copy") {
        Show-Warning "检测到字幕流 (-c:s copy)，MP4/MOV 支持较差，大概率无法封装"
        Write-Host "`r`n请选择一个选项继续："
        Write-Host " d：删除导入语句"
        Write-Host " m：将容器格式更改为 MKV"
        Write-Host " Enter：忽略"

        $fix = Read-Host "请选择..."
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

    # 写入 Bat 文件内容（去除 PowerShell 的 & 调用符，转为 CMD 格式）
    $cmdContent = $cmdLine.TrimStart('& ') 
    $batContent = @"

@echo off
chcp 65001 >nul
setlocal

REM ========================================
REM ffmpeg 封装工具
REM 生成时间：{0}
REM ========================================

echo.
echo 开始封装任务...
echo.

{1}

echo.
echo ========================================
echo  批处理执行完毕！
echo ========================================
echo.

endlocal
echo 按任意键进入命令提示符，输入 exit 退出...
pause >nul
cmd /k
"@ -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $cmdContent

    # 确保 ffmpeg 路径带引号
    #（虽然 $ffmpegPath 变量里可能没带，但上面组合时加了）
    
    Show-Border
    Write-TextFile -Path $batPath -Content $batContent -UseBOM $true
    
    Show-Success "任务完成！"
    Show-Info "命令已保存至：$batPath"
    Write-Host "提示：如果音画不同步，请在 -map 和 -c 之间添加 -itoffset <秒> 参数" -ForegroundColor DarkGray
    
    Pause
}

try { Main }
catch {
    Show-Error "脚本执行出错：$_"
    Write-Host "错误详情：" -ForegroundColor Red
    Write-Host $_.Exception.ToString()
    Read-Host "按回车键退出"
}