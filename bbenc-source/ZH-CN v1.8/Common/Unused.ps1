# 使用 Y4M 管道时能够自动获取 profile 参数，RAW 管道则直接指定 CSP、分辨率等参数即可，除非要实现硬件兼容才指定 Profile
function Get-x265SVTAV1Profile {
    # 注：由于 HEVC 本就支持有限的 CSP，因此其它 CSP 值皆为 else
    # 注：NV12：8bit 2 平面 YUV420；NV16：8bit 2 平面 YUV422
    Param (
        [Parameter(Mandatory=$true)]$CSVpixfmt, # i.e., yuv444p12le, yuv422p, nv12
        [bool]$isIntraOnly=$false,
        [bool]$isSVTAV1=$false
    )
    # 移除可能的 "-pix_fmt " 前缀（尽管实际情况不会遇到）
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''

    # 解析色度采样格式和位深
    $chromaFormat = $null
    $depth = 8  # 默认 8bit
    
    # 解析位深
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    # elseif ($pixfmt -eq 'nv12' -or $pixfmt -eq 'nv16') {
    #     $depth = 8 # 同默认，判断直接注释
    # }
    
    # 解析 HEVC 色度采样
    if ($pixfmt -match '^yuv420' -or $pixfmt -eq 'nv12') {
        $chromaFormat = 'i420'
    }
    elseif ($pixfmt -match '^yuv422' -or $pixfmt -eq 'nv16') {
        $chromaFormat = 'i422'
    }
    elseif ($pixfmt -match '^yuv444') {
        $chromaFormat = 'i444'
    }
    elseif ($pixfmt -match '^(gray|yuv400)') {
        $chromaFormat = 'gray'
    }
    else { # 默认 4:2:0
        $chromaFormat = 'i420'
        Show-Warning "未知像素格式：$pixfmt，将使用默认值（4:2:0 8bit）"
    }

    # 解析 SVT-AV1 色度采样
    # - Main：        4:0:0（gray）-4:2:0，全采样最高 10bit
    # - High：        额外支持 4:4:4 采样
    # - Professional：额外支持 4:2:2 采样，全采样最高 12bit
    $svtav1Profile = 0 # 默认 main
    switch ($chromaFormat) {
        'i444' {
            if ($depth -eq 12) { $svtav1Profile = 2 } # Professional
            else { $svtav1Profile = 1 } # High
        }
        'i422' { $svtav1Profile = 2 } # Professional only
        'gray' {
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 } # Main（保守）
        }
        default { # i420
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 }
        }
    }

    # 检查位深
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "视频编码可能不支持 $depth bit 位深" # $depth = 8
    }

    # 检查 x265 实际支持的 profile 范围：
    # 8bit：main, main-intra，main444-8, main444-intra
    # 10bit：main10, main10-intra，main422-10, main422-10-intra，main444-10, main444-10-intra
    # 12 bit：main12, main12-intra，main422-12, main422-12-intra，main444-12, main444-12-intra
    $profileBase = ""
    $inputCsp = ""

    # 根据色度格式和位深度返回对应的 profile
    if ($isSVTAV1) {
        return ("--profile " + $svtav1Profile)
    }

    switch ($chromaFormat) {
        'i422' {
            if ($depth -eq 8) {
                Show-Warning "x265 不支持 main422-8，降级为 main (4:2:0)"
                $profileBase = "main"
            }
            else {
                $profileBase = "main422-$depth"
            }
        }
        'i444' { # 特殊：8-bit 4:4:4 的 intra profile 是 main444-intra，不是 main444-8-intra
            if ($depth -eq 8) {
                $profileBase = "main444-8"
            }
            else {
                $profileBase = "main444-$depth"
            }
        }
        'gray' { # 灰度图像可以用 main/main10/main12
            $inputCsp = "--input-csp i400"
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
        default { # i420 和其他
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
    }

   # 若使用 intra-only 编码，则添加 -intra 后缀
    if ($isIntraOnly) {
        if ($profileBase -eq "main444-8") {
            $profileBase = "main444-intra"
        }
        else {
            $profileBase = "$profileBase-intra"
        }
    }

    $result = "--profile $profileBase"
    if ($inputCsp) { $result += " $inputCsp" }
    return $result
}

    # 优化前的工具导入代码，用于暂存
    <#
    $i=0
    foreach ($tool in @($upstreamTools.Keys)) {
        $i++
        $savedPath = $upstreamTools[$tool]
        $isSwapNeeded = $true # 标记是否已经确定了路径

        # 读取到保存的路径则询问是否更新，否则退回旧选择
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n 检测到已保存的 $tool 路径：$savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [上游] ($i/$($upstreamTools.Count)) 是否更换 $tool ？(y=换，Enter 不换)"
            $isSwapNeeded = if ('y' -eq $c) { $true } else { $false }
        }
        else {
            Write-Host "`r`n 未保存 $tool 的路径，需要手动导入" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [上游] ($i/$($upstreamTools.Count)) 导入 $tool 可执行文件？（y=是，Enter 跳过）"
            $isSwapNeeded = if ('y' -eq $c) { $true } else { $false }
        }

        # 使用 Invoke-AutoSearch 获取自动找到的路径
        if ($isSwapNeeded) {
            $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir
            if ($autoPath) {
                Write-Host "自动检测到 $tool 位于：$autoPath" -ForegroundColor Green
                if ('n' -eq (Read-Host "是否使用此文件？（Enter=确认, n=手动选择）")) {
                    $upstreamTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
                }
                else {
                    $upstreamTools[$tool] = $autoPath
                }
            }
            else {
                Write-Host " 未自动检测到 $tool，请手动选择"
                if ($tool -eq 'svfi') {
                    Write-Host " SVFI（one_line_shot_args.exe）Steam 发布版的路径是 X:\SteamLibrary\steamapps\common\SVFI\"
                }
                elseif ($tool -eq 'vspipe') {
                    Write-Host " 安装版 VapourSynth 的默认可执行文件路径是 C:\Program Files\VapourSynth\core\vspipe.exe"
                }
                elseif ($tool -eq 'avs2yuv') {
                    Write-Host "`r`n 支持 AviSynth（0.26）和 AviSynth+（0.30）的 avs2yuv" -ForegroundColor DarkGray
                }
                $upstreamTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
            }
        }
        Show-Success "$tool 已导入: $($upstreamTools[$tool])"

        # 检测 vspipe API 版本以及 avs2yuv 版本，无论是否切换工具
        if ($tool -eq 'vspipe' -and $upstreamTools[$tool]) {
            Write-Host ''
            Show-Info "检测 VapourSynth 管道参数..."
            $vspipeInfo = Get-VSPipeY4MArgument -VSpipePath $upstreamTools[$tool]
            Show-Success $($vspipeInfo.Note)
        }
        elseif ($tool -eq 'avs2yuv' -and $upstreamTools[$tool]) {
            # 不导入 AviSynth，故无法检测版本，需手动指定
            while ($true) {
                Show-Info "选择使用的 avs2yuv(64).exe 类型："
                $avs2yuvVer = Read-Host " [默认 Enter/a: AviSynth+ (0.30) | b: AviSynth (up to 0.26)]"
                if ([string]::IsNullOrWhiteSpace($avs2yuvVer) -or 'a' -eq $avs2yuvVer) {
                    $isAVSPlus = $true
                    break
                }
                elseif ('b' -eq $avs2yuvVer) {
                    $isAvsPlus = $false
                    break
                }
                Show-Warning "输入值超出理解，请重试"
            }
        }
    }
    #>

    # Write-Host ("─" * 50)
    # Show-Info "开始导入下游编码工具..."
    # Import-ToolPaths -ToolsToHave $downstreamTools -CategoryName "下游" -toolTips $toolHintsZHCN -ScriptDir $scriptDir
    <#
    $i=0
    foreach ($tool in @($downstreamTools.Keys)) {
        $i++
        $savedPath = $downstreamTools[$tool]

        # 读取到保存的路径则询问是否更新，否则退回旧选择
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n 检测到已保存的 $tool 路径: $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [下游] ($i/$($downstreamTools.Count)) 是否更换 $tool ？(y=换，Enter 不换)"
            if ('y' -ne $c) { continue }
        }
        else {
            Write-Host "`r`n 未保存 $tool 的路径，需要手动导入" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [下游] ($i/$($downstreamTools.Count)) 导入 $tool 可执行文件？（y=是，Enter 跳过）"
            if ('y' -ne $c) { continue }
        }
        
        # 使用 Invoke-AutoSearch 获取自动找到的路径
        $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir
        if ($autoPath) {
            Write-Host "自动检测到 $tool 位于：$autoPath" -ForegroundColor Green
            $useAuto = Read-Host "是否使用此文件？(Enter=确认, n=手动选择)"
            if ($useAuto -eq 'n') {
                $downstreamTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
            }
            else { $downstreamTools[$tool] = $autoPath }
        }
        else {
            Write-Host "未自动检测到 $tool，请手动选择。"
            $downstreamTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
        }

        Show-Success "$tool 已导入: $($downstreamTools[$tool])"
    }
    #>

    # Write-Host ("─" * 50)
    # Show-Info "开始导入检测工具..."
    # Import-ToolPaths -ToolsToHave $analysisTools -CategoryName "检测" -toolTips $toolHintsZHCN -ScriptDir $scriptDir
    <#
    $i=0
    foreach ($tool in @($analysisTools.Keys)) {
        $i++
        $savedPath = $analysisTools[$tool]

        # 读取到保存的路径则询问是否更新，否则退回旧选择
        if (Test-NullablePath $savedPath) {
            Write-Host "`r`n 检测到已保存的 $tool 路径: $savedPath" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [检测] ($i/$($analysisTools.Count)) 是否更换 $tool ？(y=换，Enter 不换)"
            if ('y' -ne $c) { continue }
        }
        else {
            Write-Host "`r`n 未保存 $tool 的路径，需要手动导入，跳过后仍可在步骤 3 导入" -ForegroundColor DarkGray
            $c = Read-Host "`r`n [检测] ($i/$($analysisTools.Count)) 导入 $tool 可执行文件？（y=是，Enter 跳过）"
            if ('y' -ne $c) { continue }
        }

        # 使用 Invoke-AutoSearch 获取自动找到的路径
        $autoPath = Invoke-AutoSearch -ToolName $tool -ScriptDir $scriptDir
        if ($autoPath) {
            Write-Host "自动检测到 $tool 位于：$autoPath" -ForegroundColor Green
            $useAuto = Read-Host "是否使用此文件？(Enter=确认, n=手动选择)"
            if ($useAuto -eq 'n') {
                $analysisTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
            }
            else { $analysisTools[$tool] = $autoPath }
        }
        else {
            Write-Host "未自动检测到 $tool，请手动选择。"
            $analysisTools[$tool] = Select-File -Title "选择 $tool 可执行文件" -ExeOnly
        }

        Show-Success "$tool 已导入: $($analysisTools[$tool])"
    }
    #>