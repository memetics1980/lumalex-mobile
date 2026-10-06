# iOS and iPadOS releases

Versioned iOS/iPadOS IPA deliverables belong in this directory.

Run `../build_release.sh` for a development-signed IPA, or pass an export
method such as `app-store` when the corresponding distribution signing is
configured. Flutter's top-level `build/` directory is an intermediate build
cache, not the release delivery location.
