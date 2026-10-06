# Android releases

Versioned Android APK and AAB deliverables belong in this directory.

Run `../build_release.sh` to create a signed arm64 APK for direct installation.
Pass `--with-aab` only when an Android App Bundle is needed for store delivery.
Configure the keystore path and alias in `../key.properties` (using
`../key.properties.example` as the template); the script securely prompts for
omitted passwords. CI can use the `LUMALEX_KEYSTORE_*` environment variables.
The script rejects debug certificates. Flutter's top-level `build/` directory
is an intermediate build cache, not the release delivery location.
