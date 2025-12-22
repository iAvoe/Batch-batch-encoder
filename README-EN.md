# Batch Batch Encoder

This tool analyzes video to perform actual x264, x265, SVT-AV1 parameter customizations. Assisted with filter-less VS/AVS script generation, semi-auto multiplex/encapsulation, and offers GUI and color-coded CLI for extra user guidance. This tool automates tedious format alignment, simplifies operations, and starts your encoding ASAP.

[TODO] English Translation progress: 3/5 of main scripts

## Environment

**Supported Upstream Programs**:
- ffmpeg
- vspipe (supports automatic parameter API recognition)
- avs2yuv
- avs2pipemod
- SVFI

**Supported Downstream Programs**:
- x264
- x265
- SVT-AV1

Only one upstream and one downstream program are needed on the system.

## Advantages

- [x] Graphical + Command-line Interactive Interface:
    - High-DPI WinForm selection window when selecting files or paths
    - Color-coded hints + pure selection interaction logic (prompt) on basic command-line options
- [x] Automatic generation of filter-free VS/AVS scripts: Accelerates script building or directly launches upstream tools such as vspipe, avs2yuv, and avs2pipemod
- [x] Independently packaged command scripts: Import video streams, audio streams, subtitle tracks, and fonts
- [x] Deeply customized encoding parameters: Automatic calculation + user-defined encoder configuration to meet your needs as much as possible
- [x] Quick command-line changes: In the generated batch, you can directly replace previously imported upstream and downstream tools by copying and pasting; easily generate multiple processing sources and video formats.

-----

## Usage

If you need to ensure security, you can verify it using Microsoft's official PSScriptAnalyzer tool: [PSScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules).
```
Invoke-ScriptAnalyzer -Path "X:\...\Batch-batch-encoder\bbenc-source" -Settings PSGallery -Recurse
```

1. For Windows 11, ensure the language pack for the corresponding filename language is installed (Windows 10).
    1. For example, Arabic filenames: `Settings → Time & Language → [Left Column] Language → Add a language → Arabic`
2. In Settings → Update & Security → Developer options, remove the PowerShell execution restriction, as shown in the image:
![bbenc-ttl5zh.png](bbenc-ttl5en.png)
3. Unzip the downloaded compressed file.
4. Run step 1 to complete the basic environment check.
    1. If VSCode is installed, it is recommended to directly install the Microsoft PowerShell plugin to run it.
    2. In VSCode, select `File → Open Folder → Open Script Root Directory (...\bbenc-source\ZH v1.x\)`
    3. VSCode requires confirmation of "Trust Publisher" before running the script.
5. Run steps 2 (Generate Coding Pipeline Batch), 3 (ffprobe Reads Source), and 4 (Generate Coding Tasks).
6. Run step 4. The generated batch file begins encoding.
    1. If multiple formats are required, simply remove the comments from the alternative parameters.
7. Run step 5 to encapsulate the encoding results.


![Script-Step-2-example (To be added)](zh-step2-example-en.png)
<p align="center">Example fur running step 2（CLI window only, this works even better in VSCode）</p>

-----

## Downloads
1. <a href='./bbenc-source'>On Github</a>
2. <a href='https://drive.google.com/drive/folders/170tmk7yJBIz5eJuy7KXzqIgtvtDajyDu?usp=sharing'>Google Drive</a>,

## Support pls

Developing these tools wasn't easy. If this tool improve your efficiency, consider sponsoring or sharing them.

<p align="center"><img src="bmc_qr.png" alt="Support me -_-"><br><img src="pp_tip_qr.png" alt="Support me =_="></p>

## Update Information

**v1.3.2**
- Rewrote entire codebase
- Used more reasonable data structures such as arrays and hash tables
- Improved error reporting logic
- Further improved support for square bracket paths and filenames
- Built a global script, simplifying the code
- Abandoned the batch mode
- Added basic SVT-AV1 support
- Rewrote all parameter calculation functions into functions, improving modularity
- Added color-coded prompt text, unifying the appearance
- Improved vspipe support
- Improved SVFI support
- Added automatic VS and AVS filterless script generation function
- Centralized export of cached datasets to a single folder
- Avoided step 4 by appending an additional CSV Repeated script imports avoid ffprobe CSV export compatibility issues.
- Improved the operation logic of step 1.
- Improved Y4M pipeline support.
- Refined the operation logic and process of the encapsulation command.
- Added more optimization-related prompt text.
- Strengthened the logic of the file import script.
- Behavior change: Required parameters for the RAW pipeline are now recorded as an appendix in the output batch.
- Added SVT-AV1 ColorMatrix, Transfer, and Primarys parameter generation functionality.
- Completed runtime testing of ffmpeg and vspe upstream to all downstream components.
    - TODO: Testing of avs2yuv, avs2pipemod, and SVFI is pending; however, theoretically, since the logic is identical, it should run fine...
- Step 5 (multiplex script) testing completed, deprecating all Invoke-Expression to increase security