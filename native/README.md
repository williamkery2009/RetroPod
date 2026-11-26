# Mornye extension compatibility (Android, experimental)

RetroPod loads the actual `.sflx` JavaScript packages from the Mornye-Extension
registry. It embeds the pinned upstream Rust/QuickJS extension manager rather
than translating provider scripts or hard-coding a provider list.

Online Music > Extensions opens the catalog. Install/update downloads a bounded
package, checks its published SHA-256, displays its manifest permissions, and
asks the user to install. Installed packages can be enabled, disabled, removed,
configured, and selected for track search. The upstream installer rejects unsafe
archive paths and enforces manifest/runtime feature gates. Network/file access,
VM memory limits and interruption are enforced by the upstream host.

A metadata extension does not necessarily provide audio. Playback requires an
enabled download provider. Its output is prepared in app-private storage and
then handed to RetroPod's existing just_audio background player. This currently
waits for the complete file, not progressive streaming. FFmpeg audio conversion
uses the runtime's validated command queue. Encrypted outputs requiring a later
decryption/finalization step are rejected. There is no cross-provider song
substitution.

## Current limits

- Android only, API 23+. Other platforms retain the existing music sources.
- Registry installation/update only; arbitrary local package import is not exposed.
- Search and file-producing audio providers are connected. Album/playlist
  browsing, lyrics-provider hooks and post-processing extensions are not exposed.
- Plain, secret, boolean and choice settings are supported. Browser/OAuth
  sign-in, action settings and Mornye's deployment-specific signed session grants
  are not implemented. Packages requiring these can fail or remain unusable.
- Paid-service packages still need their own valid access; installation does not
  supply an account, entitlement, keys or shared-service authorization.
- Prepared audio is temporary and cleared on the next process start. It is not
  added to the user's permanent downloads or library.
- The native bridge and unit tests can run in CI; individual provider availability
  and playback still need device testing. Do not claim universal compatibility.

## Build and replace the runtime

Install Rust 1.100.0, cargo-ndk and Android NDK 28.2.13676358. Add Rust targets
`aarch64-linux-android`, `armv7-linux-androideabi`, and `x86_64-linux-android`.
Android Gradle's preBuild task runs `scripts/build_mornye_runtime.sh`. That script
checks out Mornye commit `af9a4d6422759541ec57a9ed696b3b47928a1bff`, adds this
small bridge crate to its workspace, and builds `libretropod_extensions.so` for
all three ABIs. The upstream library files are not modified. Keep its vendor
patches; they include Android filesystem compatibility fixes.

For host tests, run `bash scripts/prepare_mornye_runtime.sh`, then from
`build/mornye-source/rust_backend` run `cargo test -p retropod-extensions` and
`cargo test -p mornye-extensions package::`.

The bridge and Mornye runtime are LGPL-3.0-only. License text and notices are in
`assets/licenses/`. CI uploads the runtime source beside the APK. RetroPod source
and these build scripts allow rebuilding/relinking with a modified runtime and
signing/installing that build; no private signing key is needed for personal
builds. To use a modified upstream tree, change the pinned checkout/script to
your fork, rebuild the native library, and rebuild the APK. Extension packages
retain their original source and notices within their installed directory.
