# Android 构建与发布 / Android Build and Release

[中文介绍](../README.md) · [English overview](../README_EN.md)

## 中文

准备 Flutter stable、Rust stable、JDK 17 及 Android SDK/NDK，保留本仓库的完整 Flutter/Rust 目录结构。从仓库根目录验证并解析依赖：

```sh
cargo test -p dictionary-core
cd app
flutter pub get
flutter test
flutter run -d <android-device-id>
```

正式发布前，将 `app/android/key.properties.example` 复制为 `key.properties`，填写自己的签名文件路径和 alias。发布脚本会提示输入未保存的密码；CI 可用 `LUMALEX_KEYSTORE_FILE`、`LUMALEX_KEY_ALIAS`、`LUMALEX_KEYSTORE_PASSWORD` 与 `LUMALEX_KEY_PASSWORD`。密钥、密码和本机 SDK 路径不得提交。

在 `app/` 下运行：

```sh
android/build_release.sh
# 需要商店上传包时：
android/build_release.sh --with-aab
```

脚本生成并验证正式签名的 ARM64 APK，拒绝 Android Debug 证书，输出到 `app/android/releases/`；使用 `--with-aab` 才生成 AAB。新安装包交付应递增 `pubspec.yaml` 的 build number，保持同一签名以支持覆盖更新。生成的 APK versionCode 可能包含 Flutter 的 ABI 偏移，不应把它误写为单独的 build number。

发布前在 Android 实机检查：文件夹导入、MDX/MDD 资源、较大词条、正文左右滑动、字号、音频、收藏、后台恢复，以及其他应用的 `PROCESS_TEXT` 取词。共享代码的测试结果不能代替 iOS / iPadOS 真机验证。

将 APK 与 SHA-256 校验文件作为 GitHub Release 附件，不把二进制安装包作为源码提交。使用 `--notes-file` 提交中英文发布说明，标签应明确 Android 平台与 build number。不要上传签名密钥或词典数据。

本仓库首次 Android Release 发布已有正式签名的 `0.1.0 build 48` APK；本次文档更新不重新编译或变更安装包版本。其文件摘要、签名和平台信息已核验，见 Release 说明。

## English

Install Flutter stable, Rust stable, JDK 17 and the Android SDK/NDK. Keep the complete Flutter/Rust repository layout. From the repository root:

```sh
cargo test -p dictionary-core
cd app
flutter pub get
flutter test
flutter run -d <android-device-id>
```

Copy `app/android/key.properties.example` to `key.properties` and configure your signing-key path and alias. The guarded release script prompts for omitted passwords. CI can supply `LUMALEX_KEYSTORE_FILE`, `LUMALEX_KEY_ALIAS`, `LUMALEX_KEYSTORE_PASSWORD` and `LUMALEX_KEY_PASSWORD`. Do not commit keys, passwords or local SDK paths.

From `app/`, run:

```sh
android/build_release.sh
# Only when an app-store bundle is needed:
android/build_release.sh --with-aab
```

The script creates and verifies a release-signed ARM64 APK, refuses Android Debug certificates, and writes deliverables to `app/android/releases/`. An AAB is generated only with `--with-aab`. Increment the `pubspec.yaml` build number for a new binary delivery, and keep the same signing key for in-place updates. Flutter's ABI offset can make the APK versionCode differ from the build number.

Before release, check folder imports, MDX/MDD resources, large articles, horizontal article swipes, text size, audio, favorites, foreground recovery and `PROCESS_TEXT` lookup on a physical Android device. Shared tests do not replace iOS / iPadOS device validation.

Attach APK and SHA-256 files to a GitHub Release rather than committing binaries. Supply bilingual notes with `--notes-file` and identify Android and the build number in the tag. Never upload signing keys or dictionary files.

The first Android release publishes the existing release-signed `0.1.0 build 48` APK. This documentation update does not rebuild it or change its version. The artifact checksum, signature and platform metadata have been verified; see the release notes.
