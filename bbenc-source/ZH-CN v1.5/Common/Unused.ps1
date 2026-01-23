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
                Write-Warning "x265 不支持 main422-8，降级为 main (4:2:0)"
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