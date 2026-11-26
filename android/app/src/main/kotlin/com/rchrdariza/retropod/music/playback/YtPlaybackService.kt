package com.rchrdariza.retropod.music.playback

import android.app.PendingIntent
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import com.rchrdariza.retropod.music.YtDefaults
import com.rchrdariza.retropod.music.YtMusicProvider
import com.rchrdariza.retropod.music.YtMusicProviders
import com.rchrdariza.retropod.music.toYtMusicException
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Background playback for YouTube Music streams.
 *
 * A [MediaSessionService] is used instead of a plain foreground service so the
 * system (lock screen, Bluetooth, Android Auto, media resumption) controls
 * playback through the standard Media3 session. The notification, its media
 * style and the transport controls come from Media3 defaults.
 *
 * Stream URLs are resolved inside the session callbacks, which keeps queue
 * handling simple: the controller only ever sends `ytmusic://track/<id>`
 * placeholders and the service decides when (and with which format) the real
 * URL is fetched.
 */
@OptIn(UnstableApi::class)
class YtPlaybackService : MediaSessionService() {

    private lateinit var player: ExoPlayer
    private lateinit var provider: YtMusicProvider
    private var mediaSession: MediaSession? = null

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var lastRetriedMediaId: String? = null

    override fun onCreate() {
        super.onCreate()
        provider = YtMusicProviders.get()
        player = buildPlayer()
        player.addListener(playerListener)

        val sessionBuilder = MediaSession.Builder(this, player)
            .setCallback(YtSessionCallback())
        launchIntent()?.let { pendingIntent ->
            sessionBuilder.setSessionActivity(pendingIntent)
        }
        mediaSession = sessionBuilder.build()
        instance.set(this)
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo,
    ): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val current = mediaSession?.player
        if (current == null || !current.playWhenReady || current.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        instance.compareAndSet(this, null)
        mediaSession?.release()
        mediaSession = null
        if (::player.isInitialized) {
            player.release()
        }
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun buildPlayer(): ExoPlayer {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(YtDefaults.HTTP_USER_AGENT)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
            .setReadTimeoutMs(READ_TIMEOUT_MS)
        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        return ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setSeekBackIncrementMs(SEEK_INCREMENT_MS)
            .setSeekForwardIncrementMs(SEEK_INCREMENT_MS)
            .build()
    }

    private fun launchIntent(): PendingIntent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?: return null
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private val playerListener = object : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            // Signed googlevideo URLs expire after roughly six hours and are
            // rejected when the device IP changes. Re-resolving once turns a
            // hard playback failure into a short hiccup.
            if (error.errorCode != PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS) {
                return
            }
            val item = player.currentMediaItem ?: return
            val mediaId = YtMediaItems.videoIdOf(item) ?: return
            if (mediaId == lastRetriedMediaId) {
                return
            }
            lastRetriedMediaId = mediaId
            retryWithFreshStream(item, mediaId)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (mediaItem?.mediaId != lastRetriedMediaId) {
                lastRetriedMediaId = null
            }
        }
    }

    private fun retryWithFreshStream(item: MediaItem, videoId: String) {
        val positionMs = player.currentPosition
        val resumePlayback = player.playWhenReady
        serviceScope.launch {
            val freshStream = try {
                provider.resolveStream(videoId)
            } catch (exception: Exception) {
                return@launch
            }
            launch(Dispatchers.Main) {
                player.setMediaItem(
                    item.buildUpon()
                        .setUri(freshStream.url)
                        .setMimeType(freshStream.mimeType)
                        .build(),
                    positionMs,
                )
                player.prepare()
                player.playWhenReady = resumePlayback
            }
        }
    }

    /**
     * Resolves the placeholder URI of [item] into a playable URL.
     */
    private suspend fun resolve(item: MediaItem): MediaItem {
        val videoId = YtMediaItems.videoIdOf(item) ?: return item
        val stream = provider.resolveStream(videoId)
        return item.buildUpon()
            .setUri(stream.url)
            .setMimeType(stream.mimeType)
            .build()
    }

    /**
     * Runs [block] on [serviceScope] and exposes it as a [ListenableFuture],
     * which is the return type Media3 expects from the session callbacks.
     */
    private fun <T> resolveFuture(block: suspend () -> T): ListenableFuture<T> {
        // Media3 exposes Guava's ListenableFuture in its public session API, so
        // SettableFuture is the natural bridge between a coroutine and a session
        // callback that must return immediately.
        val future = SettableFuture.create<T>()
        val job = serviceScope.launch {
            try {
                future.set(block())
            } catch (cancellation: CancellationException) {
                future.setException(cancellation)
            } catch (throwable: Throwable) {
                future.setException(throwable.toYtMusicException())
            }
        }
        future.addListener(
            { if (future.isCancelled) job.cancel() },
            Executor { command -> command.run() },
        )
        return future
    }

    private inner class YtSessionCallback : MediaSession.Callback {

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
        ): ListenableFuture<List<MediaItem>> = resolveFuture {
            mediaItems.map { item -> resolve(item) }
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> =
            resolveFuture {
                val resolved = mediaItems.map { item -> resolve(item) }
                val index = startIndex.coerceIn(0, maxOf(0, resolved.lastIndex))
                MediaSession.MediaItemsWithStartPosition(
                    resolved,
                    index,
                    startPositionMs,
                )
            }
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val SEEK_INCREMENT_MS = 10_000L
        private const val UNKNOWN_AUDIO_SESSION = -1

        private val instance = AtomicReference<YtPlaybackService?>(null)

        /**
         * Audio session id of the ExoPlayer instance, used by the visualizer.
         * Returns a negative value while the service is not running.
         */
        fun audioSessionId(): Int {
            val service = instance.get() ?: return UNKNOWN_AUDIO_SESSION
            return service.player.audioSessionId
        }

        fun isRunning(): Boolean = instance.get() != null
    }
}
