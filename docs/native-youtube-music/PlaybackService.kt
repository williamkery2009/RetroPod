package com.example.music

import android.app.Application
import android.content.Context
import android.content.ComponentName
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.guava.future

class MusicApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MusicRepository.initialize()
    }
}

@UnstableApi
fun createRemotePlayer(context: Context): ExoPlayer {
    val http = DefaultHttpDataSource.Factory()
        .setUserAgent("RetroPod-NativeExample/1.0")
        .setConnectTimeoutMs(15_000)
        .setReadTimeoutMs(20_000)
    return ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(http))
        .build()
        .apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true, // Let the player manage audio focus.
            )
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_NETWORK)
        }
}

/** The Service, not the Activity, owns playback. */
@UnstableApi
class PlaybackService : MediaSessionService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val player = createRemotePlayer(this)
        session = MediaSession.Builder(this, player)
            .setCallback(object : MediaSession.Callback {
                override fun onAddMediaItems(
                    mediaSession: MediaSession,
                    controller: MediaSession.ControllerInfo,
                    mediaItems: List<MediaItem>,
                ): ListenableFuture<List<MediaItem>> = scope.future {
                    // Resolve in the service, not the UI. Cancellation/errors
                    // propagate through the returned future. Start with a single
                    // track; production queues should resolve each track just in time.
                    require(mediaItems.size <= 1) { "This reference sample plays one track at a time" }
                    mediaItems.map { item ->
                        val audio = MusicRepository.resolveAudio(item.mediaId)
                        item.buildUpon()
                            .setUri(audio.url)
                            .setMimeType(audio.mimeType)
                            .build()
                    }
                }
            })
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        scope.cancel()
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }
}

/** Call from a visible Activity's lifecycleScope on the main dispatcher. */
suspend fun connectController(context: Context): MediaController =
    MediaController.Builder(
        context,
        SessionToken(context, ComponentName(context, PlaybackService::class.java)),
    ).buildAsync().await()

fun playTrack(controller: MediaController, track: TrackResult) {
    controller.setMediaItem(
        MediaItem.Builder()
            .setMediaId(track.videoId) // The service turns this into a fresh URL.
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(track.title)
                    .setArtist(track.artist)
                    .build(),
            )
            .build(),
    )
    controller.prepare()
    controller.play()
}
