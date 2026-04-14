# WinForm 窗口支持
# WinForm 窗口支持
# WinForm Support
if (-not ("System.Windows.Forms.Form" -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms
}

# 高 DPI 支持（只注册一次）、高 DPI 支持（只註冊一次）、High-DPI support (register once)
if (-not ("DpiHelper" -as [type])) {
    Add-Type @"
using System.Runtime.InteropServices;
public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
    [void][DpiHelper]::SetProcessDPIAware()
}

# 窗口焦点设定支持，使 CLI 在 WinForm 关闭后再聚焦，不支援 VSCode
# 窗口焦點設定支持，使 CLI 在 WinForm 關閉後再聚焦，不支援 VSCode
# Window Focus config support, allowing refocus of CLI after closing WinForm, doesn't support VSCode
if (-not ("WinAPI" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
}

<#
# 尝试实现 VSCode 窗口的再聚焦（失败）
# 嘗試實現 VSCode 視窗的再聚焦（失败）
# Attempting to implement VSCode CLI refocus (failed)
function Assert-VSCodeWindow {
    $proc = Get-Process -Name Code -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne 0) {
        [WinAPI]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
    }
}
#>