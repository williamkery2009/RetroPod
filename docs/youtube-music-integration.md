# YouTube Music streaming (Innertube) integration

Status: Kotlin module implemented, not yet wired to a Flutter screen.
Verification: the module compiles and links into a release APK. The
`Build Test APK` workflow runs `flutter build apk --release --flavor dev`, which
exercises Kotlin compilation, JitPack resolution of NewPipeExtractor and its
nanojson fork, and R8 shrinking against the keep rules below. Behaviour on a
device is still unproven: run the checklist at the end before treating it as
done.

Installable build:
<https://github.com/williamkery2009/RetroPod/releases/download/dev-apk/app-dev-release.apk>
(the rolling `dev-apk` pre-release, rebuilt from this branch on every push,
signed with a throwaway debug key, so Android asks for unknown-source
permission). The same APK is attached to each workflow run as the
`retropod-dev-apk` artifact.

## 0. Read this before shipping

Two constraints matter more than any code below.

**Licensing.** NewPipeExtractor is GPL-3.0. Linking it into RetroPod, which is
MIT (`LICENSE`), makes the resulting APK a GPL-3.0 derivative work. You cannot
ship the binary under MIT terms while it contains the extractor. Options:

1. Relicense RetroPod to GPL-3.0 (what NewPipe, ViMusic, InnerTune and
   Metrolist do). Simplest, and compatible with the existing `LICENSE` being
   replaced for future releases only.
2. Keep the streaming module out of the MIT app: implement a pure Innertube
   client in this repository (no third-party GPL code). That is a much larger,
   never-finished project because YouTube changes player clients, signature
   ciphers, `n` transforms and poToken requirements continuously.
3. Ship the module in a separate GPL-3.0 fork/flavor, keeping the MIT build
   clean.

The rest of this document assumes option 1 or 3. If you cannot change the
license, delete `android/app/src/main/kotlin/com/rchrdariza/retropod/music/`
and the dependency from `android/app/build.gradle.kts`.

**Terms of service.** Scraping YouTube bypasses the official Data API and the
Premium entitlement. That is the same trade-off every client named in the
request makes, and it is also why F-Droid lists such apps with the `NonFreeNet`
anti-feature. Get legal advice if RetroPod is distributed commercially.

## 1. Scraper/wrapper library

Recommendation: **NewPipeExtractor `v0.27.1`** (released 2026-11-10), the
extraction engine behind NewPipe and used by most maintained Android YouTube
Music clients.

| Option | Size | Maintenance | Innertube coverage | Verdict |
| --- | --- | --- | --- | --- |
| NewPipeExtractor `v0.27.1` | ~2.5 MB jar + Rhino, jsoup, protobuf-lite | Very active, releases every few weeks | Search, player, signature/`n` decipher, poToken hooks, cookies | Recommended |
| `MetrolistGroup/innertubex` | Kotlin, smaller | Active, young | InnerTube in Kotlin, GPL-3.0 | Viable alternative, fewer contributors |
| `ZemerTeam/zemer-cipher` | small | Active | Only cipher/`n`/poToken, you write the protocol | Use if you build your own client |
| Hand-written Innertube client | smallest | Your problem | Breaks whenever YouTube ships a new player | Not recommended for a music player |
| Piped / Invidious instance | none | Depends on a third party | Search + streams through a proxy | No local extraction, instance trust and uptime risk |

Why the extractor: it hides the parts that break first. It keeps track of
current `WEB_REMIX`, `ANDROID_VR`, `IOS`, `TVHTML5` and `WEB` client versions,
executes YouTube's player JavaScript in Rhino to undo the `signatureCipher` and
`n` throttling transformations, and exposes hooks for poTokens and cookies.
Search and metadata come from `music.youtube.com` directly, so results match the
YouTube Music catalogue rather than generic video search.

Dependencies added by this change:

`android/build.gradle.kts` (repository, content-filtered so JitPack is never
used for anything else):

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://jitpack.io")
            content { includeGroup("com.github.teamnewpipe") }
        }
    }
}
```

`android/app/build.gradle.kts`:

```kotlin
val media3Version = "1.4.1" // keep in sync with just_audio
implementation("androidx.media3:media3-exoplayer:$media3Version")
implementation("androidx.media3:media3-session:$media3Version")
implementation("com.github.teamnewpipe:NewPipeExtractor:v0.27.1")
implementation("com.squareup.okhttp3:okhttp:4.12.0")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
```

No explicit Guava dependency is needed: Media3 exposes Guava's
`ListenableFuture`/`SettableFuture` as part of `media3-common`'s public API, so
`YtPlaybackService` can hand session callbacks a future without adding another
library.

`isCoreLibraryDesugaringEnabled = true` is required: the extractor uses
`java.time` and `List.of`, which do not exist on the older Android versions
RetroPod still supports. `android/app/proguard-rules.pro` keeps Rhino alive,
which R8 would otherwise strip because it is only reached through reflection.

## 2. Architecture

```
Flutter (Dart)
  |  MethodChannel retropod/yt_music            EventChannels events + spectrum
  v                                                     ^
YtMusicBridge  ------------------------------------------+
  |   search / resolveStream            | playback commands
  v                                     v
YtMusicProviders.get()            MediaController (Media3)
  |                                     |
  v                                     v
NewPipeYtMusicProvider            YtPlaybackService : MediaSessionService
  |  search -> StreamInfoItem        - ExoPlayer + MediaSession
  |  resolve -> AudioStream URL      - resolves placeholders in onSetMediaItems
  v                                 - retries expired URLs on HTTP 403
OkHttpNewPipeDownloader             - notification, lock screen, Bluetooth
  |
YouTube / music.youtube.com
```

Files:

- `music/YtMusicModels.kt` - `YtTrack`, `YtStreamInfo`, `YtAudioFormat`.
- `music/YtMusicErrors.kt` - stable error codes shared with Dart.
- `music/YtStreamSelector.kt` - chooses the playable audio stream (pure logic).
- `music/OkHttpNewPipeDownloader.kt` - extractor network layer.
- `music/NewPipeYtMusicProvider.kt` - search and stream resolution.
- `music/YtMusicProvider.kt` - provider interface + singleton initialization.
- `music/playback/YtMediaItems.kt` - `MediaItem` mapping.
- `music/playback/YtPlaybackService.kt` - Media3 session and ExoPlayer.
- `music/visualizer/YtAudioSpectrum.kt` - FFT bands for custom visualizers.
- `music/bridge/YtMusicBridge.kt` - Flutter platform channels.
- `MainActivity.kt` - registers the bridge, now extends `AudioServiceActivity`.

Threading: every extractor call is blocking, so the provider always runs on
`Dispatchers.IO`. The bridge replies on the main thread. `YtPlaybackService`
never resolves on the main thread: `onSetMediaItems`/`onAddMediaItems` return a
`ListenableFuture` fed by a coroutine on the service scope.

## 3. Search

Implemented in `NewPipeYtMusicProvider.search`, exposed to Flutter as
`search`. The essential part:

```kotlin
override suspend fun search(query: String, limit: Int): List<YtTrack> =
    withContext(Dispatchers.IO) {
        val service = ServiceList.YouTube
        val queryHandler = service.searchQHFactory.fromQuery(
            query.trim(),
            listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS),
            "",
        )
        val extractor = service.getSearchExtractor(queryHandler)
        extractor.fetchPage()
        extractor.initialPage.items
            .asSequence()
            .filterIsInstance<StreamInfoItem>()
            .mapNotNull { item -> item.toYtTrack() }
            .distinctBy { track -> track.videoId }
            .take(limit.coerceIn(1, YtDefaults.MAX_SEARCH_RESULTS))
            .toList()
    }
```

Notes:

- `MUSIC_SONGS` switches the extractor to `music.youtube.com` with the "Songs"
  filter, so results carry a real artist rather than the video uploader.
- Other filters exist and can be added as a `contentFilters` argument:
  `MUSIC_VIDEOS`, `MUSIC_ALBUMS`, `MUSIC_PLAYLISTS`, `MUSIC_ARTISTS`.
- The video id is extracted with `YoutubeStreamLinkHandlerFactory.getId`, so
  playlists, shorts and livestream links all normalize to an 11 character id.
- Items that fail to parse are skipped instead of failing the whole search:
  YouTube Music search pages contain ads and shelves that do not map to tracks.

## 4. Stream extraction

Implemented in `NewPipeYtMusicProvider.resolveStream` plus `YtStreamSelector`:

```kotlin
val extractor = ServiceList.YouTube.getStreamExtractor(
    "https://www.youtube.com/watch?v=$videoId",
)
extractor.fetchPage()
val stream = YtStreamSelector.select(extractor.audioStreams, YtAudioFormat.M4A)
    ?: throw YtMusicException(YtErrorCode.NO_AUDIO_STREAM, "Only DASH available")
YtStreamInfo(
    videoId = videoId,
    url = stream.content,
    mimeType = stream.format?.mimeType ?: "audio/mp4",
    codec = stream.codec,
    bitrateKbps = YtStreamSelector.bitrateKbps(stream),
    itag = stream.itag,
    expiresAtEpochMs = YtStreamSelector.expiresAtEpochMs(stream.content),
)
```

Selection rules:

1. Keep only streams where `isUrl` is true and the delivery method is
   `PROGRESSIVE_HTTP`. Those are the plain `https://...googlevideo.com/videoplayback?...`
   URLs that ExoPlayer can play directly. DASH audio streams return a base64
   initialization segment instead of a URL and are not playable without a DASH
   manifest.
2. Keep the original audio track (`AudioTrackType.ORIGINAL`); dubbed and
   descriptive tracks are excluded when the stream exposes a track type.
3. Prefer the requested container (`audio/mp4` = AAC in `.m4a` by default,
   `audio/webm` = Opus). Fall back to whatever container is offered.
4. Among the candidates, take the highest bitrate (`itag` 140 is 128 kbit/s AAC,
   `itag` 251 is ~160 kbit/s Opus).

Things to handle around the URL:

- **Expiry.** The URL carries `expire` (epoch seconds); parsed into
  `expiresAtEpochMs`. Treat resolved URLs as short-lived, never persist them.
- **IP binding.** A URL resolved on Wi-Fi generally stops working on mobile
  data. Re-resolve on network change, or rely on the service's 403 retry.
- **403 throttling.** YouTube occasionally answers with `403 Forbidden` or
  throttles a range. `YtPlaybackService` re-resolves once per media id and
  resumes at the last position.
- **Age-restricted and premium-only tracks** need account cookies. The
  extractor reads cookies from the `Cookie` header of your `Downloader`; add a
  per-user cookie store if you want to support sign-in. The current module
  reports `AGE_RESTRICTED` / `PAID` instead of failing silently.
- **poToken / bot check.** Some clients require a proof-of-origin token. The
  extractor exposes `YoutubeStreamExtractor.setPoTokenProvider(...)`; without an
  implementation, affected requests surface as `BOT_CHECK`. Porting the
  WebView-based provider NewPipe ships is the next step if that error appears.
- **Live streams** (`AUDIO_LIVE_STREAM`) have no progressive stream; the module
  returns `NO_AUDIO_STREAM`. Supporting them needs the DASH/HLS path.

## 5. ExoPlayer / Media3 integration

`YtPlaybackService` is a `MediaSessionService`, which is the pattern Android
recommends for background audio: notification, media buttons, Bluetooth, Android
Auto, media resumption and audio focus are all handled by Media3.

Player configuration (remote streams included):

```kotlin
val httpFactory = DefaultHttpDataSource.Factory()
    .setUserAgent(YtDefaults.HTTP_USER_AGENT)      // avoids many 403s
    .setAllowCrossProtocolRedirects(true)
    .setConnectTimeoutMs(15_000)
    .setReadTimeoutMs(30_000)
val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)

ExoPlayer.Builder(this)
    .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
    .setAudioAttributes(
        AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build(),
        true, // request audio focus and duck/handle interruptions
    )
    .setHandleAudioBecomingNoisy(true)  // pause when headphones unplug
    .setWakeMode(C.WAKE_MODE_NETWORK)   // keep the CPU awake while streaming
    .setSeekBackIncrementMs(10_000)
    .setSeekForwardIncrementMs(10_000)
    .build()
```

Queue entries are placeholders. Resolution happens in the session callbacks, so
`prepare()` and auto-advance always get a fresh URL:

```kotlin
override fun onSetMediaItems(
    mediaSession: MediaSession,
    controller: MediaSession.ControllerInfo,
    mediaItems: List<MediaItem>,
    startIndex: Int,
    startPositionMs: Long,
): ListenableFuture<MediaSession.MediaItemsWithStartPosition> = resolveFuture {
    val resolved = mediaItems.map { resolve(it) } // ytmusic:// -> googlevideo
    MediaSession.MediaItemsWithStartPosition(
        resolved,
        startIndex.coerceIn(0, maxOf(0, resolved.lastIndex)),
        startPositionMs,
    )
}
```

The service is declared in `AndroidManifest.xml` with the
`androidx.media3.session.MediaSessionService` action and
`foregroundServiceType="mediaPlayback"`. `INTERNET` and `ACCESS_NETWORK_STATE`
were added, since RetroPod previously never touched the network.

Playback is driven from Flutter through a `MediaController` bound to the
service, not by touching ExoPlayer directly, so the system and the app see the
same session.

## 6. Visualizers

ExoPlayer exposes the audio session id it renders to. Attaching
`android.media.audiofx.Visualizer` to that session gives FFT frames of our own
playback without recording the microphone:

```kotlin
val sessionId = YtPlaybackService.audioSessionId()
val visualizer = Visualizer(sessionId)
visualizer.captureSize = Visualizer.getCaptureSizeRange()[1]
visualizer.setDataCaptureListener(listener, Visualizer.getMaxCaptureRate() / 2, false, true)
visualizer.enabled = true
```

`YtAudioSpectrum` wraps this, converts the 8-bit FFT magnitudes into 24
normalized bands (0..1) and posts them to Flutter at roughly 10-20 Hz. Details:

- `RECORD_AUDIO` is required by `Visualizer` on modern Android. The manifest
  declares it; request it at runtime and call
  `setVisualizerEnabled(enabled: true)` only after it is granted.
- The audio session id changes when ExoPlayer recreates its audio renderer, so
  the session is polled once a second and the `Visualizer` is rebound when it
  changes; the Flutter side needs no rebinding logic.
- Capture stops when the spectrum event channel has no listener or the module is
  disabled.
- If you only need a decorative animation, prefer a waveform derived from
  playback position over `Visualizer`; it avoids the `RECORD_AUDIO` permission
  entirely.

## 7. Flutter bridge contract

Method channel `retropod/yt_music`:

| Method | Arguments | Result |
| --- | --- | --- |
| `search` | `query: String`, `limit: Int` | `List<Map>` tracks |
| `resolveStream` | `videoId: String` | `Map` stream info |
| `playTracks` | `tracks: List<Map>`, `startIndex: Int` | `true` |
| `play` / `pause` | none | `true` |
| `seekTo` | `positionMs: Int` | `true` |
| `skipNext` / `skipPrevious` | none | `true` |
| `stop` | none | `true` (pauses and clears the queue) |
| `getState` | none | current state map |
| `setVisualizerEnabled` | `enabled: Bool` | `Bool`, false when `RECORD_AUDIO` is missing |

Track map: `videoId`, `title`, `artist`, `thumbnailUrl`, `durationMs`.
Stream map: `videoId`, `url`, `mimeType`, `codec`, `bitrateKbps`, `itag`,
`expiresAtEpochMs`.

Event channel `retropod/yt_music/events` emits maps with `type: "state"` plus
`isPlaying`, `playWhenReady`, `playbackState` (Media3 constants: 1 idle,
2 buffering, 3 ready, 4 ended), `mediaId`, `title`, `artist`, `positionMs`,
`durationMs`, `index`, `queueSize`, `audioSessionId`, or `type: "error"` with
`code` and `message`.

Event channel `retropod/yt_music/spectrum` emits `List<double>` of 24 bands in
0..1.

Method errors use the `YtErrorCode` name as code: `NETWORK`, `RATE_LIMITED`,
`BOT_CHECK`, `AGE_RESTRICTED`, `PAID`, `PRIVATE`, `GEO_BLOCKED`, `UNAVAILABLE`,
`INVALID_ID`, `NO_AUDIO_STREAM`, `PLAYBACK`, `EXTRACTION_FAILED`, `UNKNOWN`.

Dart side (not added to `lib/` yet; adapt naming to the feature layout):

```dart
class YtMusicService {
  static const MethodChannel _methods = MethodChannel('retropod/yt_music');
  static const EventChannel _events = EventChannel('retropod/yt_music/events');
  static const EventChannel _spectrum =
      EventChannel('retropod/yt_music/spectrum');

  Future<List<Map<String, Object?>>> search(String query) async {
    final List<Object?>? results =
        await _methods.invokeMethod<List<Object?>>('search', <String, Object?>{
      'query': query,
      'limit': 25,
    });
    return results
            ?.whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> map) => map.cast<String, Object?>())
            .toList() ??
        <Map<String, Object?>>[];
  }

  Future<void> playTracks(
    List<Map<String, Object?>> tracks, {
    int startIndex = 0,
  }) async {
    await _methods.invokeMethod<bool>('playTracks', <String, Object?>{
      'tracks': tracks,
      'startIndex': startIndex,
    });
  }

  Future<void> setVisualizerEnabled(bool enabled) async {
    await _methods.invokeMethod<bool>(
      'setVisualizerEnabled',
      <String, Object?>{'enabled': enabled},
    );
  }

  Stream<Object?> get events => _events.receiveBroadcastStream();
  Stream<Object?> get spectrum => _spectrum.receiveBroadcastStream();
}
```

## 8. Coexistence with the existing local player

RetroPod already uses `just_audio` + `audio_service` for local files, and that
stack owns its own `MediaBrowserService` and notification. Two media sessions in
one app are allowed by Android, but they must not play at the same time.

Policy implemented/expected:

- Starting a YouTube Music track pauses the local player
  (`audioPlayerServiceProvider.pause()` from Dart) and vice versa.
- Both sessions appear in the system media switcher; the user can return to
  either one.
- Audio focus is requested by both players, so the OS pauses the inactive one
  when the other starts; the Dart policy above just makes that deterministic.
- `MainActivity` now extends `AudioServiceActivity`, so `audio_service` keeps
  working exactly as before.

## 9. Known gaps and next steps

1. No Dart UI. Add a search screen, a result list and a "play" action that calls
   `search` and `playTracks`. The existing click-wheel navigation model maps
   well to a paginated search list.
2. No queue persistence. `MediaItem` placeholders are cheap to serialize, so
   save `videoId`/`title`/`artist` pairs and rebuild on start.
3. No prefetching. Resolving the next track while the current one plays removes
   the 1-2 second gap between tracks.
4. No offline cache. If downloading is wanted, resolve once and write the stream
   to `getExternalFilesDir("music")`, then play it with the existing local
   pipeline. That is also the only way to support F-Droid builds that must not
   hit the network at runtime.
5. poToken. If device testing returns `BOT_CHECK`, implement
   `PoTokenProvider` (WebView + BotGuard, as NewPipe does) and register it with
   `YoutubeStreamExtractor.setPoTokenProvider`.
6. Licensing decision from section 0.

## 10. Device verification checklist

1. `flutter pub get` and `flutter build apk --debug` resolve JitPack and Media3.
2. Debug build installs; app still opens and plays local files (the
   `MainActivity` change is the riskiest edit).
3. Search "Blinding Lights" returns tracks with artists and artwork.
4. Tap a track: audio starts, notification shows title and artist, seek works.
5. Background the app, lock the screen, pause/play from the lock screen.
6. Unplug headphones: playback pauses.
7. Toggle airplane mode mid-track: `NETWORK` surfaces, no crash.
8. Leave a track paused for more than the URL lifetime (six hours) or switch
   networks, then resume: the 403 retry re-resolves instead of failing.
9. Enable the visualizer after granting `RECORD_AUDIO`: bands move with the
   music and settle to zero when paused.
10. Local playback and streaming do not overlap.
