# When using a Y4M pipeline, 'profiles' can be obtained automatically
# For a RAW pipeline, parameters such as CSP and resolution needs to be specified directly
# The profile should only be specified when hardware compatibility is required
function Get-x265SVTAV1Profile {
    # Note: Since HEVC inherently supports a limited number of CSP values, all other CSP values ​​are else.
    # Note: NV12: 8-bit 2-plane YUV420; NV16: 8-bit 2-plane YUV422
    # Warning: Interlaced video is not currently supported.
    Param (
        [Parameter(Mandatory=$true)]$CSVpixfmt, # i.e., yuv444p12le, yuv422p, nv12
        [bool]$isIntraOnly=$false,
        [bool]$isSVTAV1=$false
    )
    # Remove any possible "-pix_fmt" prefixes (although unlikely to encounter)
    $pixfmt = $CSVpixfmt -replace '^-pix_fmt\s+', ''

    # Parse chroma sampling format and bit depth
    $chromaFormat = $null
    $depth = 8  # Defualt to 8bit
    
    # Parse bit depth
    if ($pixfmt -match '(\d+)(le|be)$') {
        $depth = [int]$matches[1]
    }
    # elseif ($pixfmt -eq 'nv12' -or $pixfmt -eq 'nv16') {
    #     $depth = 8 # Commented out as same as default
    # }
    
    # Parse HEVC chroma subsampling
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
    else { # Default to 4:2:0
        $chromaFormat = 'i420'
        Show-Warning "Unknown pixel format: $pixfmt, using the default value instead (4:2:0 8bit)."
    }

    # Parse SVT-AV1 chroma sampling
    # - Main: 4:0:0 (gray) - 4:2:0, maximum 10-bit full sampling
    # - High: Additional support for 4:4:4 sampling
    # - Professional: Additional support for 4:2:2 sampling, maximum 12-bit full sampling
    $svtav1Profile = 0 # Default as main
    switch ($chromaFormat) {
        'i444' {
            if ($depth -eq 12) { $svtav1Profile = 2 } # Professional
            else { $svtav1Profile = 1 } # High
        }
        'i422' { $svtav1Profile = 2 } # Professional only
        'gray' {
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 } # Main (conservative)
        }
        default { # i420
            if ($depth -eq 12) { $svtav1Profile = 2 }
            else { $svtav1Profile = 0 }
        }
    }

    # Parse bit depth
    if ($depth -notin @(8, 10, 12)) {
        Show-Warning "Video encoder is not likely to support $depth bit." # $depth = 8
    }

    # Check the range of profiles actually supported by x265:
    # 8bit：main, main-intra，main444-8, main444-intra
    # 10bit：main10, main10-intra，main422-10, main422-10-intra，main444-10, main444-10-intra
    # 12 bit：main12, main12-intra，main422-12, main422-12-intra，main444-12, main444-12-intra
    $profileBase = ""
    $inputCsp = ""

    # Return the corresponding profile based on the chroma format and bit depth.
    if ($isSVTAV1) {
        return ("--profile " + $svtav1Profile)
    }

    switch ($chromaFormat) {
        'i422' {
            if ($depth -eq 8) {
                Write-Warning "x265 does not support main422-8, downgrading to main (4:2:0)."
                $profileBase = "main"
            }
            else {
                $profileBase = "main422-$depth"
            }
        }
        'i444' { # Special case: 8-bit 4:4:4 intra profile is main444-intra, not main444-8-intra
            if ($depth -eq 8) {
                $profileBase = "main444-8"
            }
            else {
                $profileBase = "main444-$depth"
            }
        }
        'gray' { # Grayscale also uses main/main10/main12
            $inputCsp = "--input-csp i400"
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
        default { # i420 and others
            switch ($depth) {
                8  { $profileBase = "main" }
                10 { $profileBase = "main10" }
                12 { $profileBase = "main12" }
                default { $profileBase = "main" }
            }
        }
    }

   # Add -intra suffix for intra-only encoding
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