<img src="app/assets/branding/lumalex-icon-ui.png" alt="LumaLex app icon" width="96" height="96">

# LumaLex Mobile

[简体中文](README.md) | [English](README_EN.md)

让离线词典留在本地，让查词融入手机阅读，让收藏变成可以复习的词汇。

LumaLex 是由 Flutter 与 Rust 构建的移动端 MDX/MDD 词典阅读器。导入自己的词典后，可离线查词、对照多本词典，在支持文字选择的应用中打开查词浮窗，并保存收藏与复习记录。

| 平台 | 下载与状态 |
| --- | --- |
| Android 7.0 及以上，ARM64 | [Android build 48 APK](https://github.com/memetics1980/lumalex-mobile/releases/tag/v0.1.0-build48-android) |
| iOS / iPadOS | 开发中，暂不提供安装包和使用说明 |

本文和截图介绍 **Android 当前版本**。LumaLex 不内置或分发商业词典，词典文件需由用户自行准备。本次发布为 APK 安装包，请从 Release 的 Assets 下载，不要把源码 ZIP 当作安装包。

[下载 Android APK](https://github.com/memetics1980/lumalex-mobile/releases/tag/v0.1.0-build48-android) · [完整使用说明](docs/USER_GUIDE.zh-CN.md) · [English user guide](docs/USER_GUIDE.en.md) · [Android 构建指南](docs/ANDROID_BUILD.md) · [桌面版](https://github.com/memetics1980/lumalex-desktop)

点击截图可查看原尺寸图片。截图中的词典和阅读材料仅用于演示，不随程序分发。

## 特色功能

### 离线词典与多词典对照

支持 MDX 词条与配套 MDD 图片、字体、音频等资源，尽量保留词典原有的排版和交互。同一次查询检索当前范围内的已启用词典，在词条正文左右滑动即可对照不同词典：**左滑下一本，右滑上一本**。点按上方词典名称也可打开列表直接选择。

<a href="docs/images/android-main-lookup.jpg"><img src="docs/images/android-main-lookup.jpg" alt="Android 主窗口查词" width="320"></a>
<a href="docs/images/android-dictionary-switch.jpg"><img src="docs/images/android-dictionary-switch.jpg" alt="同一个词在另一本词典中的释义" width="320"></a>

同一个 `tag`，从第 1 本切换到第 2 本有结果的词典。词条与例句的发音取决于词典提供的音频或系统语音支持。

### 词典分组与查找范围

可为词典建立分组、调整显示名称与排列顺序，并决定哪些词典参与查询。查词时可选某个分组、“全部词典”或“未分组”；分组管理不移动或重命名原始词典文件。

<a href="docs/images/android-dictionary-groups.jpg"><img src="docs/images/android-dictionary-groups.jpg" alt="词典分组管理" width="320"></a>

### 不离开阅读页面的取词浮窗

在支持 Android 标准文字操作菜单的浏览器、阅读器等应用中选中单词或短语，再选择 **“LumaLex 查词”**，即可在原应用上方打开查词窗口。

浮窗支持正文滑动切换词典、调整字号、收藏、拖动、缩放和最大化。它使用 Android 的文字处理入口，无需单独授予“在其他应用上层显示”权限；点击窗口外可关闭并继续阅读。是否显示入口取决于来源应用的文字选择菜单，它不是 OCR。

<a href="docs/images/android-selected-text-lookup.jpg"><img src="docs/images/android-selected-text-lookup.jpg" alt="浏览器选词后打开 LumaLex 浮窗" width="480"></a>

### 收藏、历史与词汇复习

点按词条页的星形按钮收藏单词，在“词汇本”中重新查词或使用词汇卡复习。先回想释义，再显示答案并选择“再来一次”“有点模糊”“认识”或“很熟”，安排下一次复习。搜索历史、收藏和复习进度均保存在本机。

<a href="docs/images/android-favorites.jpg"><img src="docs/images/android-favorites.jpg" alt="收藏词汇列表" width="320"></a>
<a href="docs/images/android-review.jpg"><img src="docs/images/android-review.jpg" alt="词汇卡复习" width="320"></a>

### 适应手机与宽屏阅读

紧凑屏幕使用底部导航，宽屏布局使用侧边导航。通过 `Aa` 调整词条字号，按自己的阅读习惯浏览词典。

[![Android 宽屏词条阅读](docs/images/android-wide-reader.jpg)](docs/images/android-wide-reader.jpg)

## 快速开始

1. 下载 Release 中的 `LumaLex-0.1.0-build48-arm64-v8a.apk`，在 Android 上打开安装；按系统提示允许当前下载来源安装应用。
2. 把自己的 `.mdx` 与同名 `.mdd`、`.1.mdd` 等配套文件放在同一文件夹，在“词典”页点“导入词典”，通过系统文件夹选择器授权读取。
3. 在“查词”页输入单词或短语，选择查找范围。正文左滑/右滑切换有结果的词典，也可点词典名称选择。
4. 点星形按钮收藏，在“词汇本 → 收藏 / 复习”继续学习。
5. 在其他应用中选词，尝试从文字操作菜单打开“LumaLex 查词”。找不到入口时可直接回到 LumaLex 输入查询。

首次导入会准备索引；较大的词典库可能需要更长时间。详细步骤和故障排查见[使用说明](docs/USER_GUIDE.zh-CN.md)。

## 数据与隐私

- 本地词典查词不需要账号、AI 服务或联网；本 Android 版本未提供桌面版的 AI 语境释义。
- Android 保留原始词典文件，并为 MDX 建立应用私有的读取副本；大型 MDD 资源按需从原位置读取。请保留原文件夹和读取授权，并为 MDX 副本预留空间。
- 在“词典 → 关于与诊断”导出或恢复学习数据，也可保存诊断报告。学习数据包含历史、收藏、复习进度和字号，不包含 MDX/MDD 或词典库文件授权。
- 不会在手机与桌面版之间自动同步。更换设备时需另行准备词典、重新导入并恢复学习数据；卸载前先导出需要保留的记录。

## 开发与仓库结构

Android 源码构建、签名与发布步骤见 [Android 构建指南](docs/ANDROID_BUILD.md)。iOS / iPadOS 工程保留在仓库中继续开发，不作为本次 Android Release 的交付内容。

```text
docs/                      中英文使用说明与截图
app/lib/                   共享界面、词典与学习服务
app/android/               Android 原生集成与发布脚本
app/ios/                   iOS / iPadOS 工程（开发中）
app/test/                  Flutter 测试
app/rust_builder/          Flutter / Rust 构建桥接
crates/                    Rust 词典引擎与 API 桥接
vendor/mdictlib/           修补后的 MDX/MDD 解析器
```

词典数据、安装包、编译缓存、签名密钥和敏感配置不作为源码提交。请保留第三方组件的许可文件；拥有词典文件不代表拥有再分发权。
