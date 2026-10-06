# LumaLex Mobile

Private mobile source repository for **Android, iOS and iPadOS**. LumaLex is a
local-first MDX/MDD dictionary reader built with Flutter and a Rust engine.

## Project layout

| Directory | Content |
| --- | --- |
| `app/lib/` | Shared lookup, dictionary groups, reader, history and learning UI |
| `app/android/` | Android native integration and release tooling |
| `app/ios/` | iPhone/iPad integration and patched WebView plugin |
| `app/rust_builder/` | Android/iOS Rust build integration via Cargokit |
| `crates/` | MDX/MDD engine and Flutter/Rust bridge |
| `vendor/mdictlib/` | Locally patched dictionary parser and upstream license |
| `app/test/` | Flutter regression tests |

See [project status](docs/PROJECT_STATUS.md) and
[platform management](app/docs/PLATFORM_MANAGEMENT.md) for implementation details.

## Setup and checks

Install Flutter stable, Rust stable, and the Android SDK/NDK for Android.
iOS/iPadOS builds additionally require macOS, Xcode and CocoaPods.

```sh
cargo test -p dictionary-core
cd app
flutter pub get
flutter test
flutter run -d <device-id>
```

The generated Dart bridge is checked in. Relative paths in the Rust workspace
and Cargokit build scripts require keeping the repository layout intact.

## Android delivery

Configure `app/android/key.properties` from its example with your own signing
key, then run from `app/`:

```sh
android/build_release.sh
# Optionally: android/build_release.sh --with-aab
```

Signed deliverables are written to `app/android/releases/`. Keys and local
properties are excluded from Git. The script rejects debug signing certificates.

## iOS / iPadOS delivery

Open `app/ios/Runner.xcworkspace` after `flutter pub get` and CocoaPods setup.
The checked-in bundle ID is `com.jinbo.lumalex`; select an appropriate signing
team and provisioning configuration in Xcode for your devices. From `app/`:

```sh
flutter build ios --release --no-codesign --no-pub
# With signing configured:
ios/build_release.sh development
```

The unsigned `.app` is a build check. Installable IPA deliveries require signing
and are written to `app/ios/releases/`.

## Dictionary data

Dictionary data is supplied locally by the user and is excluded from this
repository. On iPhone/iPad, place complete MDX/MDD folders in
`On My iPhone/iPad > LumaLex > Dictionaries`, or import from Files.
On Android, import through the system folder picker.

## Source and synchronization

This repository contains the mobile snapshot of the local `dictionary` project
at version **0.1.0+48**, including the iOS article-swipe fix. The desktop runners
and prior local commit history are omitted. Future updates should synchronize
shared Flutter/Rust changes and the two mobile native projects together, then
run the platform checks before release.

No app license has been selected for this private repository; bundled third-party
components retain their own license files.
