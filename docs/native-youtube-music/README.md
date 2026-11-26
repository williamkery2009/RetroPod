# Native Android YouTube Music architecture

This is a Kotlin reference implementation, separate from RetroPod's Flutter
runtime. It is not wired into the application or Android Gradle build. The Dart
provider in this PR remains the implementation used by RetroPod. A native switch
would require a Flutter platform bridge and one shared playback owner; do not run
a second native player alongside just_audio/audio_service.

## Library choice

For a native Android implementation, use **NewPipe Extractor v0.27.1**. It has a
YouTube Music songs search filter and handles stream extraction behind a stable
Java API callable from Kotlin. It is more substantial than a small Innertube
wrapper, but avoids owning the response parsers and extractor maintenance yourself.

NewPipe Extractor is **GPL-3.0-or-later**. That is a material difference from
RetroPod's MIT license: review distribution/license compatibility before linking
it into a shipped app. These sample files do not add it to RetroPod's dependencies.
For the existing Flutter implementation, youtube_explode_dart 3.1.0 is used instead.

This accesses public unauthenticated results without a YouTube Data API key. It
is unofficial, can break, and does not guarantee unrestricted/free access to every
track. No login cookies, CAPTCHA workarounds, account restrictions, or paid-content
access are implemented. Return a recoverable error and an Open YouTube Music action
when extraction is unavailable.

## Architecture and lifecycle

1. UI/ViewModel debounces search (about 400-500 ms), cancels obsolete jobs, and
   displays track metadata. It stores the stable video ID, not a signed stream URL.
2. MusicRepository performs blocking NewPipe calls on Dispatchers.IO. A shared
   mutex protects extractor state. Network timeouts bound blocking operations;
   cancellation checks prevent a late result from replacing a newer selection.
   Coroutine cancellation does not immediately abort every blocking HTTP call.
3. A MediaController sends the selected video ID to PlaybackService.
4. The service resolves a fresh audio-only progressive HTTPS URL, then gives that
   URL and its MIME type to Media3. URLs may expire or depend on network/IP; do not
   put them in a permanent library or share them between devices.
5. A MediaSessionService owns the player and media session. Its lifetime is separate
   from the Activity, allowing background playback and system media controls.
6. A PCM audio processor receives decoded audio for visualization. Compressed
   m4a/webm network bytes are not suitable input to an FFT or waveform renderer.

The sample intentionally accepts one track at a time. For long queues, resolve
items just before playback/preparation rather than eagerly resolving an entire
playlist. On a 403/410, resolve once again using the stable ID and restore position;
if that fails, surface an error. Do not create an unlimited retry loop. Implement
this recovery before calling a production queue reliable.

## Dependencies

Add JitPack in settings.gradle.kts, alongside your existing repositories:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

In the native app/module build.gradle.kts (use a Kotlin 2.1-compatible toolchain
for the pinned coroutine release):

```kotlin
android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("com.github.teamnewpipe:NewPipeExtractor:v0.27.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2")
    implementation("com.google.guava:guava:33.4.8-android")

    val media3 = "1.11.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-session:$media3")

    // NewPipe requires the NIO desugaring variant below Android API 33.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
}
```

No HLS/DASH module is required for the selected progressive m4a/webm audio streams.
This example rejects manifest-backed streams instead of incorrectly treating
manifest XML as a direct URL. Use a current compatible compileSdk/AGP for Media3;
these are dependency fragments for an existing native Android app, not a complete
Gradle wrapper/project.

For a minified release, include the extractor's documented R8 rules:

```proguard
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.tools.**
```

## Search and extraction

Copy [MusicRepository.kt](MusicRepository.kt). It includes the required OkHttp
Downloader adapter, one-time NewPipe initialization, the result types, and these
suspend functions:

```kotlin
val results: List<TrackResult> = MusicRepository.search("Blinding Lights")
val track = results.firstOrNull() ?: return
val stream: DirectAudio = MusicRepository.resolveAudio(track.videoId)
// stream.url is a temporary HTTPS URL; stream.mimeType is audio/mp4 or audio/webm.
```

Search uses `YoutubeSearchQueryHandlerFactory.MUSIC_SONGS`, not generic YouTube
video search. It returns videoId, title, artist/uploader display name, and thumbnail.
It fetches the first page only. Preserve continuation pages if implementing
pagination, and do not start playback automatically from a search result.

Resolution filters for `isUrl`, `PROGRESSIVE_HTTP`, and audio formats M4A/WEBMA/
WEBMA_OPUS. It prefers M4A for compatibility and then highest offered bitrate.
This is a selection preference, not a promise of lossless or Premium quality.
Language/dub preference can be added using AudioStream's audio-track metadata.

## Minimal direct ExoPlayer usage

For an isolated foreground prototype, use `createRemotePlayer` from
[PlaybackService.kt](PlaybackService.kt). Run player operations on its application
looper (the main thread in this example):

```kotlin
// In a main-dispatcher coroutine; resolveAudio switches its network work to IO.
val stream = MusicRepository.resolveAudio(track.videoId)
player.setMediaItem(
    MediaItem.Builder()
        .setMediaId(track.videoId)
        .setUri(stream.url)
        .setMimeType(stream.mimeType)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(track.title)
                .setArtist(track.artist)
                .build()
        )
        .build()
)
player.prepare()
player.play()
```

Do not append `.m4a` or `.webm` to the URL. A signed Googlevideo URL may have no
file extension. Let the DataSource manage Range requests, redirects and byte
positions; do not hard-code a Range header or arbitrary Content-Length values.

## Background playback

Copy [PlaybackService.kt](PlaybackService.kt), including MusicApplication, into a
native module and adapt `com.example.music` to your package. Merge the following
into its AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

<application android:name=".MusicApplication">
    <service
        android:name=".PlaybackService"
        android:exported="true"
        android:foregroundServiceType="mediaPlayback">
        <intent-filter>
            <action android:name="androidx.media3.session.MediaSessionService" />
        </intent-filter>
    </service>
</application>
```

If your application already has an Application class, call initialize() there;
do not replace its existing initialization. In RetroPod, do not replace its
Flutter Application setup with this native sample.

From a user action in a visible Activity, connect and play in its lifecycleScope:

```kotlin
val controller = connectController(this@MainActivity)
val results = MusicRepository.search("Blinding Lights")
results.firstOrNull()?.let { playTrack(controller, it) }
// Retain controller for transport controls; release() it when this UI owner ends.
// Releasing a controller does not release the service-owned ExoPlayer.
```

The service's onAddMediaItems() performs resolution and returns a
ListenableFuture, so extraction does not block the main thread. Add UI handling
for asynchronous controller/session errors and Player.Listener.onPlayerError.
The service releases the player/session and cancels its scope in onDestroy().
Media3 handles the media notification/foreground lifecycle. Start playback from
a user-visible interaction to respect Android foreground-service restrictions.

## Visualizers

For app-owned PCM, use `androidx.media3.exoplayer.audio.TeeAudioProcessor` and its
`AudioBufferSink` through `DefaultAudioSink.Builder.setAudioProcessors(...)` in a
custom `DefaultRenderersFactory`. Its `handleBuffer(ByteBuffer)` callback receives
decoded samples and `flush(sampleRateHz, channelCount, encoding)` supplies format
changes. This does not require Android Visualizer's RECORD_AUDIO permission.

- Read from a duplicate/read-only view of the ByteBuffer. Never change the player's
  buffer positions, and do not retain a buffer after the callback returns.
- Respect encoding and channel count: PCM16 and float PCM need different conversion.
- Copy only the samples needed into a bounded ring buffer, then run FFT/RMS work off
  the playback thread. Publish UI values at about 30-60 Hz, not every audio buffer.
- Keep offload/tunneling disabled when visualization is required; those paths may
  bypass app-side PCM processing. Recheck the Media3 audio-offload preferences API
  if enabling offload elsewhere. Account for playback latency when syncing visuals.
- A sample tap is not a complete visualizer; FFT, windowing, smoothing and rendering
  are separate layers.

## Validation and boundaries

The Kotlin files were checked against the v0.27.1 extractor source interfaces and
Media3 documentation. They are reference snippets, not a separately compiled or
device-tested native app. RetroPod's Dart implementation has its own tests and CI.
Before shipping native code, test search, no results, extraction failure, expired
URLs, switching networks, wired/Bluetooth disconnect, screen-off playback,
notification controls, process recreation, R8 release builds, and visualizer
format changes. Anonymous extraction may fail on restricted or bot-checked
connections; an available search result is not proof that extraction will succeed.

Primary references:

- [NewPipe Extractor v0.27.1](https://github.com/TeamNewPipe/NewPipeExtractor/tree/v0.27.1)
- [YouTube Music search filter](https://github.com/TeamNewPipe/NewPipeExtractor/blob/v0.27.1/extractor/src/main/java/org/schabi/newpipe/extractor/services/youtube/linkHandler/YoutubeSearchQueryHandlerFactory.java)
- [Extractor stream model](https://github.com/TeamNewPipe/NewPipeExtractor/blob/v0.27.1/extractor/src/main/java/org/schabi/newpipe/extractor/stream/Stream.java)
- [Media3 releases](https://developer.android.com/jetpack/androidx/releases/media3)
- [Background playback](https://developer.android.com/media/media3/session/background-playback)
- [PCM tap](https://developer.android.com/reference/androidx/media3/exoplayer/audio/TeeAudioProcessor.AudioBufferSink)
