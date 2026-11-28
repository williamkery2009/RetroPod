## Unreleased — custom add-on compatibility

- Send manifest-declared defaults to search and stream instead of forcing a
  quality tier. Preserve endpoint query tokens and exact selected provider IDs.
- Resolve relative stream URLs, forward validated playback headers in memory,
  and use explicit DASH/HLS audio sources when the provider declares them.
- Keep encrypted/hybrid streams unsupported. Wrong-recording playback remains
  unverified against the live provider, which rejects development requests.

## Unreleased — custom add-on and sign-in recovery

- Add a configurable Lastwave-format HTTP add-on with manifest validation,
  encrypted endpoint storage, public search and direct HTTPS stream resolution.
  The LastWave Addons homepage opens for personal-account setup; it is not
  treated as an anonymous API. Encrypted/hybrid streams and private client
  signatures remain unsupported, and live provider playback is unverified.
- Allow trusted YouTube account and Google India sign-in redirects; recognize
  first-party session cookies. Show page/certificate errors, a slow-page notice,
  a bounded account check and Start over instead of silently blocking redirects.

## Unreleased — YouTube account sign-in

- Add experimental Android YouTube account sign-in and local sign-out.
- Encrypt the saved session with Android Keystore in non-backup storage;
  credentials stay native and are never passed to Piped or extensions.
- Try the saved web session before anonymous extraction; report rejected
  sessions and unsupported stream formats separately. Embedded Google sign-in
  and authenticated playback still require device verification.

## Unreleased — Mornye extension packages

- Fix string-valued extension setting choices (including YouTube format and
  country); identify unsupported button actions instead of rendering text fields.
- Preserve both YouTube and Piped failure causes; show HTTP status for proxy
  failures and safe categorized extension diagnostics without server bodies.
- These fixes do not provide browser sign-in, Mornye session verification or
  restore unavailable upstream servers.

- Preserve the updated base-branch lyric rendering when resolving the merge.

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
