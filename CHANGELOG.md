## Unreleased — Mornye extension packages

- Add Android `.sflx` registry installation/update, permission review, settings,
  enable/disable/removal and installed-provider search.
- Reuse pinned Mornye Rust/QuickJS runtime with scoped host services; prepare
  audio-provider files for the existing background player.
- Keep metadata-only providers distinct; account authorization, session grants,
  extension lyrics and album browsing remain unsupported.
- Fix malformed fallback notification artwork URL for tracks without artwork.

Add public SoundCloud search and fresh progressive/HLS playback, plus an experimental configurable JioSaavn API adapter.

Add Audius public-track search and streaming, excluding restricted tracks and preserving remix titles and uploader attribution.

Add selectable Piped audio resolution, an editable HTTPS API server, and one Piped fallback after YouTube extraction failure.

Update the YouTube extraction client for upstream audio-stream 403 failures and show safe, specific playback diagnostics.

Use subtle consistent blur on inactive lyrics and keep active/browsed lines sharp. Add experimental YouTube Music search and fresh audio-stream resolution, plus a separate Kotlin/NewPipe/Media3 architecture guide.

Keep inactive lyrics crisp and readable. Add online music previews, HTTPS radio stations, and optional LRCLIB lyrics lookup for local songs.

[prepared for F-Droid: reproducible builds, MIT license, free fonts](https://github.com/RchrdAriza/RetroPod/releases/tag/1.14.0)

[replaced proprietary Helvetica font with Liberation Sans (SIL OFL) and documented asset licenses](https://github.com/RchrdAriza/RetroPod)

[changed launcher icon background from purple to red](https://github.com/RchrdAriza/RetroPod)

[🚀 updated CI/CD to build windows installer](https://github.com/RchrdAriza/RetroPod/commit/3fc038606228a9c1e70404b7b902806a97c89324)

[✨ added ability to run debug app without keystore](https://github.com/RchrdAriza/RetroPod/commit/549c6cfec0bb33ae0b565b42a8077dc458a9ac1e)

[🐛 fixed playlist deletion bugs](https://github.com/RchrdAriza/RetroPod/commit/ca6409c3a59346090b417392ddef53bdc3bd4a22)

[✨ added CI/CD with build boolean inputs](https://github.com/RchrdAriza/RetroPod/commit/6f7846d7dd17f824e7da79bad5c867b9ddc511fd)
