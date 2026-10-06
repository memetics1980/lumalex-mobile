# LumaLex Android User Guide

[简体中文](USER_GUIDE.zh-CN.md) | [English](USER_GUIDE.en.md) · [Overview](../README_EN.md)

For Android `0.1.0 build 48`. iOS / iPadOS remains in development; this guide does not provide installation or usage instructions for those platforms. The Android interface currently uses Chinese labels, translated below.

## 1. Download and install

Download `LumaLex-0.1.0-build48-arm64-v8a.apk` from the **Assets** of the [Android release](https://github.com/memetics1980/lumalex-mobile/releases/tag/v0.1.0-build48-android). This package supports **ARM64 devices running Android 7.0 (API 24) or later**. It does not contain 32-bit ARM or x86 builds.

Open the APK on your phone. Follow Android's prompt to allow installation from the browser or file manager you are using, then install. Prompt names vary by manufacturer. GitHub's source ZIP/TAR files are not installers.

An existing version signed with the same release key can normally be updated in place. If Android reports a signature mismatch, export learning data from the old version and check the package source before uninstalling. The application ID is `com.lumalex.dictionary`.

The release includes a SHA-256 file. To check download integrity on a computer, place it beside the APK and run:

```sh
shasum -a 256 -c LumaLex-0.1.0-build48-arm64-v8a.apk.sha256
```

## 2. Prepare and import dictionaries

LumaLex includes no dictionary data. Prepare MDX/MDD files you are authorized to use, extract any archive first, and keep the original structure. For example:

```text
MyDictionaries/
  Example/
    Example.mdx
    Example.mdd
    Example.1.mdd
    Example.2.mdd
```

MDX files contain entries; MDD files contain accompanying resources. Some dictionaries have only an MDX. Preserve resource-volume names and keep them beside the MDX. Retain supplied CSS, JavaScript, fonts and other sidecar files in their original locations too.

1. Open “词典” (Dictionaries) in bottom navigation, or side navigation on a wide layout.
2. Tap the “导入词典” (Import dictionaries) add button.
3. Select the dictionary folder in Android's system picker and grant read access.
4. Wait for scanning and import. LumaLex finds MDX files in the selected folder and its subfolders and pairs resource volumes.
5. Check that the dictionaries are enabled, then return to “查词” (Lookup).

Android creates an app-private MDX reading copy to improve random-access performance. Large MDD volumes remain at their original location and are read on demand. Original files are not modified. Allow additional storage for MDX copies, and keep the source folder in place, especially its MDD and sidecar files.

Indexes are prepared in the background; large dictionaries may take longer. Some devices restrict access to storage roots or protected folders. Move dictionaries into a regular dedicated subfolder and select that folder if necessary.


<a href="images/android-home.jpg"><img src="images/android-home.jpg" alt="LumaLex Android lookup home" width="320"></a>

## 3. Groups, enabled state and ordering

In Dictionaries, create a group, expand it, and use the group or dictionary's more-actions menu to manage display names, colors, ordering and group membership. Enabled state determines participation in lookup.

<a href="images/android-dictionary-groups.jpg"><img src="images/android-dictionary-groups.jpg" alt="Android dictionary groups" width="320"></a>

Group headers show both available dictionaries and the total managed count. Disabled or temporarily inaccessible records can remain in the total. “未分组” means Ungrouped. Group changes and display-name changes do not move or rename original files. Removing a dictionary from the library removes its app record, not its original files.

## 4. Look up words and switch dictionaries

1. Enter a word or phrase in Lookup and submit, or choose a prefix suggestion.
2. Tap the dictionary name to open the list and choose All dictionaries, a group, or Ungrouped as the lookup scope.
3. **Swipe left on the article to show the next dictionary with results; swipe right for the previous one.** You can also choose directly from the dictionary-name list.
4. A counter such as `1/6` shows the current result position. Swipes move among dictionaries with results in the current scope.

<a href="images/android-main-lookup.jpg"><img src="images/android-main-lookup.jpg" alt="Dictionary lookup result" width="320"></a>
<a href="images/android-dictionary-switch.jpg"><img src="images/android-dictionary-switch.jpg" alt="Another dictionary for the same word" width="320"></a>

Use one finger and a clear horizontal movement starting in the middle of the article. Vertical movement scrolls. Edge-originating and multitouch gestures do not switch dictionaries, helping avoid conflicts with system gestures. If a dictionary has its own horizontal controls, choose another dictionary from the name list instead.

Tap linked headwords to continue looking up words. Double-tapping ordinary article text can also trigger local lookup; links, sound controls and dictionary buttons are excluded. After an exact miss, LumaLex tries common inflections and limited spelling suggestions; manual query adjustment may still be necessary.

### Text size and pronunciation

Tap `Aa` at the upper right to show text-size controls, then use `− / +`. The saved text size is shared by the main reader and lookup window.

Tap a dictionary's speaker or pronunciation control for audio. Playback depends on accessible MDD resources and the dictionary's supplied audio. Controls that use system speech also depend on your phone's speech engine and language resources. Install offline speech resources first if you need offline system speech.

### Landscape and wide layouts

Wide layouts use side navigation and more space for articles. Use landscape or system split-screen where your device supports them. Article swipes and the dictionary-name list work the same way.

[![Android wide-screen reader](images/android-wide-reader.jpg)](images/android-wide-reader.jpg)

## 5. Look up selected text in another app

First open LumaLex and import and enable dictionaries. Then:

1. Select a word or phrase in a browser or reader.
2. Inspect Android's text-action menu, including any More or overflow menu.
3. Choose **“LumaLex 查词” (LumaLex lookup)** to open the window above the source app.

<a href="images/android-selected-text-lookup.jpg"><img src="images/android-selected-text-lookup.jpg" alt="Selected-text lookup over a browser" width="480"></a>

| Action | How |
| --- | --- |
| Change query | Enter another word in the window's search box |
| Switch dictionaries | Swipe on the article or tap the dictionary name |
| Change text size | Tap `Aa`, then adjust the size |
| Save a favorite | Tap the star in the title bar |
| Move the window | Drag the blank area of the title bar |
| Resize | Drag the bottom-right size control |
| Maximize / restore | Tap the diagonal-arrow control |
| Return to reading | Tap outside the window to close it |

The main app and lookup window share history, favorites, review records and text size; the main app refreshes when you return. This uses Android's `PROCESS_TEXT` entry point and requires no separate “display over other apps” permission.

Some apps have custom selection menus without this action. Scanned PDFs or images without selectable text cannot use it either. It is not OCR and cannot guarantee access to every app. Copy the word and enter it in LumaLex if needed.

## 6. Favorites, history and review

Tap an article's star to save or unsave a word. Open “词汇本 → 收藏” (Wordbook → Favorites) and tap a saved word to look it up again. Use the history icon or “管理历史” (Manage history) to revisit and manage earlier queries.

<a href="images/android-favorites.jpg"><img src="images/android-favorites.jpg" alt="Favorite vocabulary" width="320"></a>

Open “词汇本 → 复习” (Wordbook → Review), recall the meaning, then tap “显示释义” (Show definition). Answers come from local dictionaries; restore dictionary access first if needed. After revealing the answer, rate your recall:

| UI label | Meaning |
| --- | --- |
| 再来一次 — Again | Could not recall; review again soon |
| 有点模糊 — Hard | Recall was uncertain |
| 认识 — Good | Recalled normally |
| 很熟 — Easy | Recalled easily |

Your rating schedules the next review; the interval is shown beside each option. History and favorites support individual deletion, multi-selection and confirmed clearing. Removing a favorite affects its review card.

<a href="images/android-review.jpg"><img src="images/android-review.jpg" alt="Vocabulary review card" width="320"></a>

## 7. Backup, restore and diagnostics

Open “词典 → 关于与诊断” (Dictionaries → About and diagnostics):

- **导出学习数据 — Export learning data**: save a JSON file containing history, favorites, review progress and text size.
- **恢复学习数据 — Restore learning data**: choose an exported JSON file. Confirmation **replaces current learning records**, rather than merging them. Export current records first if you want to retain them.
- **保存诊断报告 — Save diagnostic report**: save a local report with version, runtime and reader-event information.

Learning backups do not contain dictionaries, dictionary-library structure or folder permissions. Prepare and re-import dictionaries on a new device. Phone and desktop records do not synchronize automatically. Uninstalling removes app-private data; export records you want to keep beforehand. Review diagnostic reports before sharing them.

## 8. Troubleshooting

| Problem | Check |
| --- | --- |
| APK will not install | Android 7.0+, ARM64, storage and install-source permission; in-place updates also need matching signatures |
| No usable dictionaries after import | Extract archives, check for MDX files, grant folder read access and enable dictionaries |
| No result in one dictionary | Lookup scope, enabled state, spelling and whether that dictionary contains the word |
| Missing images, fonts or audio | Matching and numbered MDD volumes, sidecar files and continued source-folder access |
| Swiping does not switch | Use one finger horizontally in the article's middle; ensure other dictionaries in scope have results, or choose from the name list |
| No LumaLex text-menu action | The source app may not support standard text actions; check More or enter the word in the main app |
| Slow first lookup in a large dictionary | Allow index preparation, check free space and consider narrowing the enabled lookup scope |
| Dictionary inaccessible after reopening | Restore the original folder or re-import to renew read access |
| Unexpected behavior after updating | Check the version in About and diagnostics, save a report and verify dictionary resources |

This version provides local MDX/MDD lookup, a selected-text window and vocabulary learning. The desktop edition's global shortcuts and AI contextual definitions are not Android features described by this guide.
