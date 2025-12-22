if (-not ("System.Windows.Forms.Form" -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms
}

# High-DPI GUI support (Register only once)
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