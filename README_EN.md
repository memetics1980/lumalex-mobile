<img src="app/assets/branding/lumalex-icon-ui.png" alt="LumaLex app icon" width="96" height="96">

# LumaLex Mobile

[简体中文](README.md) | [English](README_EN.md)

Keep your offline dictionaries local, look up words while reading on your phone, and turn favorites into vocabulary you can review.

LumaLex is a mobile MDX/MDD dictionary reader built with Flutter and Rust. Import your own dictionaries to look up words offline, compare multiple dictionaries, open a lookup window from compatible text-selection menus, and keep favorites and review progress.

| Platform | Download and status |
| --- | --- |
| Android 7.0 or later, ARM64 | [Android build 48 APK](https://github.com/memetics1980/lumalex-mobile/releases/tag/v0.1.0-build48-android) |
| iOS / iPadOS | In development; no installer or user guide yet |

This page and its screenshots cover the **current Android version**. LumaLex does not bundle or distribute commercial dictionaries; supply your own dictionary files. Download the APK from the release Assets. The source ZIP is not an installer.

[Download Android APK](https://github.com/memetics1980/lumalex-mobile/releases/tag/v0.1.0-build48-android) · [Android user guide](docs/USER_GUIDE.en.md) · [中文使用说明](docs/USER_GUIDE.zh-CN.md) · [Android build guide](docs/ANDROID_BUILD.md) · [Desktop edition](https://github.com/memetics1980/lumalex-desktop)

Click a screenshot to view it at full size. Dictionary entries and reading materials shown are demonstrations and are not distributed with the app. The current Android interface uses Chinese labels; this English guide includes their translations.

## Features

### Offline dictionaries and side-by-side comparisons

Read MDX entries and accompanying MDD images, fonts and audio while retaining dictionary layouts and interactions where supported. A lookup searches enabled dictionaries in the selected scope. **Swipe left on the article for the next dictionary with results, or right for the previous one.** Tap the dictionary name above the article to choose directly from a list.

<a href="docs/images/android-main-lookup.jpg"><img src="docs/images/android-main-lookup.jpg" alt="Android dictionary lookup" width="320"></a>
<a href="docs/images/android-dictionary-switch.jpg"><img src="docs/images/android-dictionary-switch.jpg" alt="The same word in another dictionary" width="320"></a>

The same word, `tag`, shown in the first and second dictionaries with results. Headword and example pronunciation depend on the dictionary's audio resources or system speech support.

### Dictionary groups and lookup scopes

Create groups, change display names and ordering, and enable or disable dictionaries for lookup. Search a group, all dictionaries, or ungrouped dictionaries. Group management does not move or rename the original files.

<a href="docs/images/android-dictionary-groups.jpg"><img src="docs/images/android-dictionary-groups.jpg" alt="Dictionary group management" width="320"></a>

### Look up selected text while reading

Select a word or phrase in a browser, reader, or another app that supports Android's standard text-action menu, then choose **“LumaLex 查词” (LumaLex lookup)** to open a lookup window above the source app.

The window supports article swipes, text-size adjustment, favorites, dragging, resizing and maximizing. It uses Android's text-processing entry point and does not require a separate “display over other apps” permission. Tap outside the window to return to reading. Availability depends on the source app's selection menu; this is not OCR.

<a href="docs/images/android-selected-text-lookup.jpg"><img src="docs/images/android-selected-text-lookup.jpg" alt="LumaLex lookup window over a browser" width="480"></a>

### Favorites, history and vocabulary review

Tap the star on an article to save the word. Revisit favorites or review vocabulary cards in “词汇本” (Wordbook). Recall the meaning, reveal the answer, and rate your recall as Again, Hard, Good or Easy to schedule the next review. History, favorites and review progress stay on your device.

<a href="docs/images/android-favorites.jpg"><img src="docs/images/android-favorites.jpg" alt="Favorite words" width="320"></a>
<a href="docs/images/android-review.jpg"><img src="docs/images/android-review.jpg" alt="Vocabulary card review" width="320"></a>

### Phone and wide-screen reading

Compact layouts use bottom navigation; wider layouts use side navigation. Adjust article text size with `Aa` to suit your reading preferences.

[![Android wide-screen dictionary reader](docs/images/android-wide-reader.jpg)](docs/images/android-wide-reader.jpg)

## Quick start

1. Download `LumaLex-0.1.0-build48-arm64-v8a.apk` from the release and open it on Android. Follow the system prompt to allow installation from your chosen download source.
2. Keep your `.mdx` beside matching `.mdd`, `.1.mdd` and other resource volumes. In “词典” (Dictionaries), tap “导入词典” (Import dictionaries) and grant access through the system folder picker.
3. Enter a word or phrase in “查词” (Lookup) and choose a lookup scope. Swipe left/right on the article or tap the dictionary name to switch results.
4. Tap the star to save words and continue in “词汇本 → 收藏 / 复习” (Wordbook → Favorites / Review).
5. Select text in another app and try “LumaLex 查词” in its text-action menu. If the action is unavailable, enter the query directly in LumaLex.

Import prepares dictionary indexes; a large library may take longer. See the [user guide](docs/USER_GUIDE.en.md) for full instructions and troubleshooting.

## Data and privacy

- Local dictionary lookup requires no account, AI service or internet connection. This Android version does not include the desktop edition's AI contextual definitions.
- Android keeps the original files and creates an app-private reading copy of each MDX. Large MDD volumes are read on demand from their original location. Keep the source folder and access grant, and allow storage for the MDX copies.
- “词典 → 关于与诊断” (Dictionaries → About and diagnostics) provides learning-data export/restore and local diagnostic reports. Learning exports include history, favorites, review progress and text size, but not MDX/MDD files or dictionary-folder permissions.
- Phone and desktop data do not synchronize automatically. Prepare and import dictionaries separately on a new device, then restore learning data. Export records you want to retain before uninstalling.

## Development and repository layout

See the [Android build guide](docs/ANDROID_BUILD.md) for building, signing and publishing. The iOS / iPadOS project remains in the repository for development and is not part of this Android release.

```text
docs/                      Bilingual user guides and screenshots
app/lib/                   Shared UI, dictionary and learning services
app/android/               Android integration and release tooling
app/ios/                   iOS / iPadOS project (in development)
app/test/                  Flutter tests
app/rust_builder/          Flutter / Rust build integration
crates/                    Rust dictionary engine and API bridge
vendor/mdictlib/           Patched MDX/MDD parser
```

Dictionary data, installers, build caches, signing keys and sensitive configuration are excluded from source commits. Retain third-party license files. Possessing a dictionary file does not grant redistribution rights.
