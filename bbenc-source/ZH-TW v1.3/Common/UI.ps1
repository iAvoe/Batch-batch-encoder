if (-not ("System.Windows.Forms.Form" -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms
}

# 高 DPI 支持（只註冊一次）
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