# Mobile project status

Source snapshot: 2026-10-06, shared app version 0.1.0+48. This repository starts
from the current working files, including the iOS/iPadOS article-swipe fix;
previous local Git history is not imported.

## Included

- Shared Flutter interface, generated Flutter/Rust bridge, and automated tests.
- Android SAF imports, MDX performance copies, aggregate dictionary reader,
  selected-text lookup activity, and guarded release build script.
- iOS/iPadOS Files imports, security-scoped folder access, bounded WKWebView
  retention, foreground recovery, local WebView plugin patch, and release script.
- Rust MDX/MDD engine and locally patched mdictlib parser, with upstream licenses.
- Branding assets and dependency lockfiles.

Mobile readers switch dictionaries by swiping horizontally on the article body.
The dictionary name opens the list on tap. Android and iOS retain their distinct
reader rendering and memory policies.

## Excluded

Desktop application runners and bridge platform registrations, packaged
dictionaries, dictionary-generation tools, MIUI theme packaging, generated build
outputs, signing keys, passwords, local SDK paths, and local Git history.
Shared Dart still includes desktop-compatible branches and tests where those
help preserve shared behavior; this repository ships mobile application runners.

## Android distribution

Android 0.1.0 build 48 is published as the existing release-signed ARM64 APK.
It supports Android 7.0+ (API 24); the APK versionCode is 2048. The documentation
update does not rebuild the package. SHA-256 and signature verification accompany
the release. User-facing bilingual documentation currently covers Android only;
iOS/iPadOS remains in development with no installable release.

## Validation boundary

The article-swipe change previously passed 120 Flutter tests and an unsigned
iOS Release build. Device validation is still needed on iPhone and iPad for
article gestures, large entries, dictionary switching, audio, background/resume,
orientation changes, and iPad multitasking. This is not a signed IPA delivery.

`docs/MVP.md` preserves the original milestone notes; use this file and the
platform management guide for the current mobile scope.
