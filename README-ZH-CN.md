# PowerShell 批处理自定义参数压制工具

为提高编码参数配置阶段效率而开发的软件规格脚本，用于构建多种视频编码压制任务。逻辑上根据视频源属性，用户需求，引用各个程序的命令行格式等规则为前提，构建上游仅 Y4M 管道导出 + 下游深度定制参数的效率提升工具，实现了急用版压制教程的上位替代。

## 环境

**支持的管道上游程序**：
- ffmpeg
- vspipe（支持 API 3.0、4.0 自动识别）
- avs2yuv
- avs2pipemod
- SVFI

**支持的管道下游程序**：
- x264
- x265
- SVT-AV1

只要系统里有一个上游、一个下游程序即可。

## 优点

- [x] 图形 + 命令行交互界面：
  - 在选择文件、路径时调用高 DPI 模式的 Win Form 选窗
  - 在基本命令行选项上使用分色编码提示 + 纯选择交互逻辑（prompt）
- [x] 自动生成无滤镜 VS/AVS 脚本：加速完成脚本构建，或直接启动 vspipe、avs2yuv、avs2pipemod 上游
- [x] 独立封装命令脚本：导入视频流，音频流，字幕轨，字体
- [x] 深度定制编码参数：自动计算 + 用户定义实现尽可能符合需求的编码器配置
- [x] 快速命令行变更：在生成的批处理中，可以直接通过复制粘贴来替换先前导入的管道上游、下游工具；轻松衍生多种处理源与视频格式

-----

## 用法

如需确保安全性，则可以通过微软官方的 [PSScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview?view=ps-modules) 检测工具来验证：
```
Invoke-ScriptAnalyzer -Path "X:\...\Batch-batch-encoder\bbenc-source" -Settings PSGallery -Recurse
```

1. Windows 11 下需要确保安装了对应文件名语言的语言包（Windows 10）
    1. 例如，阿拉伯语文件名：`设置 → 时间和语言 →[左栏] 语言 → 添加语言 → 阿拉伯语`
2. 在设置 → 更新和安全 → 开发者选项中解除 PowerShell 的运行限制，如图：
![bbenc-ttl5zh.png](bbenc-ttl5zh.png)
3. 解压下载好的压缩包
4. 运行步骤 1 从而完成基本环境检测
    1. 如果安装了 VSCode，则建议直接安装微软 PowerShell 插件运行
    2. VSCode 选择 `文件 → 打开文件夹 → 打开脚本根目录（...\bbenc-source\ZH v1.x\）`
    3. VSCode 需要确认“信任发布者”才能运行脚本
5. 运行步骤 2（生成编码管线批处理）、3（ffprobe 读取源）、4（生成编码任务）
6. 运行步骤 4 生成的批处理以开始编码
    1. 若有多种格式的需求，去除备用参数的注释即可
7. 运行步骤 5 以封装编码结果

![脚本步骤 2 示例](zh-step2-example.png)
<p align="center">脚本步骤 2 示例（仅 CLI 窗口，在 VSCode 中运行效果最佳）</p>

## 下载链接

皆同步更新，QQ 群里有很高几率能得到问题答复

1. <a href='https://github.com/iAvoe/Batch-batch-encoder/tree/main/bbenc-source'>Github 直链</a>, 
2. <a href='https://drive.google.com/drive/folders/170tmk7yJBIz5eJuy7KXzqIgtvtDajyDu?usp=sharing'>谷歌盘</a>, 
3. <a href='https://pan.baidu.com/s/1jAXn066e6K7vSfUd5zJEcg'>百度云，提取码 hevc</a>, 
4. QQ 群存档：<a href='https://jq.qq.com/?_wv=1027&k=5YJFXyf'>691892901</a><br>

教程地图、工具下载见：<a href="https://iavoe.github.io/">iavoe.github.io</a>

## 缺陷信息

用于生成备用管线（pipe 命令行）的导入命令最终都使用单一源文件，这可能是视频、.vpy 或 .avs 文件。因此，根据选择的管道上游程序不同，备用命令行中的上游程序输入/导入参数可能会写作指定导入无效的文件。于是尽管格式正确，切换命令时仍可能需要手动编辑批处理。

## 打赏信息

开发这些工具并不容易。如果这套工具提高了你的效率，那么不妨赞助或推广一下下下。

<p align="center"><img src="bmc_qr.png" alt="支持一下 -_-"><br><img src="pp_tip_qr.png" alt="支持一下 =_="></p>

## 更新信息
**v1.4.5**
- 实现了 VOB 格式的元数据读取支持
- 实现了 VOB 与非 VOB 的逐行与隔行扫描识别功能
- 添加了自动指定 avs2pipemod、x264、x265 隔行扫描参数的功能（SVT-AV1 则提示原生不支持）
- 已完成 vspipe 到 x264、x265 测试，等待完成其他测试
- 修复了因管道上游同时选择了 AVS 类工具以及 vspipe 工具时，只能导入 .avs 或 .vpy 触发兼容检测失败（判断为应终止脚本）的逻辑问题（修改脚本源后缀名并检测文件是否存在，提示但无视错误）
- 步骤 3 升级为使用 ffprobe 检测真实封装文件格式的方案，不再用后缀名检测
- 步骤 2 添加了当只有一种工具链可用时自动选择的功能

**v1.3.9**
- 提前了批处理的变量清理（endlocal）时机，避免编码后直接关闭 CMD 窗口产生残留
- 添加了无法实现从 .vs，.avs 脚本读取视频源或者验证视频存在功能原因的说明

**v1.3.8**
- 完成了 SVFI 上游适配：
  - 自动从渲染配置 INI 获取 Task ID 和源视频路径（JSON 解析）并构建管道参数，从而跳过视频导入步骤
- 修复了 SVT-AV1 下游参数构建的格式失误
- 添加了导入 one_line_shot_args.exe 与 vspipe.exe 的自动路径检测功能（导入更简单）
- 添加了导入 SVFI INI 文件的自动路径检测功能（导入更简单）
- 添加了繁体中文版
  - 改善了用词本地化程度

**v1.3.7**
- 重写了所有代码
- 使用了数组、哈希表等等更合理的数据结构
- 改进了报错逻辑
- 进一步提高了对方括号路径、文件名的支持
- 构建了全局脚本，简化了代码
- 抛弃了大批量模式
- 添加了 SVT-AV1 基础支持
- 全部参数计算功能改写为函数，提高了模块化
- 添加了分色处理的提示文本，统一化了外观
- 改进了 vspipe 支持
- 改进了 SVFI 支持
- 添加了自动 VS、AVS 无滤镜脚本生成功能
- 缓存数据集中导出到单一文件夹
- 通过追加额外的 CSV，避免了步骤 4 脚本的重复导入，避免了 ffprobe 导出 CSV 兼容问题
- 改进了步骤 1 的操作逻辑
- 改进了 Y4M 管道支持
- 完善了封装命令的操作逻辑、流程
- 增加了更多优化操作相关的提示文本
- 强化了文件导入脚本的逻辑
- 行为变更：将 RAW 管道所需参数作为附录（Appendix）一并记录到输出批处理中
- 添加了 SVT-AV1 的 ColorMatrix、Transfer、Primaries 参数生成功能
- 已验证 ffmpeg 兼容性正常
- 已验证 vspipe 兼容性正常
- 已验证 avs2yuv 0.26+0.30 兼容性正常
- 已验证 avs2pipemod 兼容性正常
- 测试步骤 5（封装命令）已完成测试，弃用了所有 Invoke-Expression 来增加安全性