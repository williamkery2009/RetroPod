package com.rchrdariza.retropod.music.bridge

import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.rchrdariza.retropod.music.YtMusicProvider
import com.rchrdariza.retropod.music.YtMusicProviders
import com.rchrdariza.retropod.music.YtTrack
import com.rchrdariza.retropod.music.playback.YtMediaItems
import com.rchrdariza.retropod.music.playback.YtPlaybackService
import com.rchrdariza.retropod.music.toYtMusicException
import com.rchrdariza.retropod.music.visualizer.YtAudioSpectrum
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Platform-channel facade of the YouTube Music module.
 *
 * Flutter talks to the native side exclusively through this class:
 *
 * - `retropod/yt_music` (method channel): search, stream resolution, queue
 *   control and playback commands;
 * - `retropod/yt_music/events` (event channel): playback state and errors;
 * - `retropod/yt_music/spectrum` (event channel): visualizer bands.
 *
 * Playback itself lives in [YtPlaybackService]; the bridge only drives a
 * [MediaController] bound to that service, so commands work with the same
 * semantics the system uses for lock screen and Bluetooth controls.
 */
@androidx.annotation.OptIn(UnstableApi::class)
class YtMusicBridge private constructor(
    private val context: Context,
    private val provider: YtMusicProvider,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var controller: MediaController? = null
    private var stateSink: EventChannel.EventSink? = null
    private var spectrumSink: EventChannel.EventSink? = null

    private val playerListener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            emitState(player)
        }

        override fun onPlayerError(error: PlaybackException) {
            stateSink?.success(
                mapOf(
                    "type" to "error",
                    "code" to "PLAYBACK",
                    "message" to (error.message ?: "Playback failed"),
                ),
            )
        }
    }

    private val stateStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            stateSink = events
            controller?.let { emitState(it) }
        }

        override fun onCancel(arguments: Any?) {
            stateSink = null
        }
    }

    private val spectrumStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            spectrumSink = events
            YtAudioSpectrum.setSink { bands ->
                spectrumSink?.success(bands.map { band -> band.toDouble() })
            }
        }

        override fun onCancel(arguments: Any?) {
            spectrumSink = null
            YtAudioSpectrum.setSink(null)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "search" -> search(call, result)
            "resolveStream" -> resolveStream(call, result)
            "playTracks" -> playTracks(call, result)
            "play" -> runOnController(result) { it.play() }
            "pause" -> runOnController(result) { it.pause() }
            "seekTo" -> seekTo(call, result)
            "skipNext" -> runOnController(result) {
                it.seekToNextMediaItem()
            }
            "skipPrevious" -> runOnController(result) {
                it.seekToPreviousMediaItem()
            }
            "stop" -> runOnController(result) {
                it.pause()
                it.clearMediaItems()
            }
            "getState" -> getState(result)
            "setVisualizerEnabled" -> setVisualizerEnabled(call, result)
            else -> result.notImplemented()
        }
    }

    private fun search(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query")?.trim().orEmpty()
        if (query.isEmpty()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val limit = (call.argument<Number>("limit")?.toInt() ?: 25)
        scope.launch {
            try {
                val tracks = provider.search(query, limit)
                result.success(tracks.map { track: YtTrack -> track.toMap() })
            } catch (throwable: Throwable) {
                replyError(result, throwable)
            }
        }
    }

    private fun resolveStream(call: MethodCall, result: MethodChannel.Result) {
        val videoId = call.argument<String>("videoId")?.trim().orEmpty()
        if (videoId.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "Missing videoId", null)
            return
        }
        scope.launch {
            try {
                result.success(provider.resolveStream(videoId).toMap())
            } catch (throwable: Throwable) {
                replyError(result, throwable)
            }
        }
    }

    private fun playTracks(call: MethodCall, result: MethodChannel.Result) {
        val rawTracks = call.argument<List<*>>("tracks").orEmpty()
        val tracks = rawTracks.mapNotNull { entry ->
            (entry as? Map<*, *>)?.let { map -> YtTrack.fromMap(map) }
        }
        if (tracks.isEmpty()) {
            result.error("INVALID_ARGUMENTS", "No playable tracks provided", null)
            return
        }
        val startIndex = (call.argument<Number>("startIndex")?.toInt() ?: 0)
            .coerceIn(0, tracks.lastIndex)
        val items = tracks.map { track -> YtMediaItems.fromTrack(track) }
        connect { connected ->
            if (connected == null) {
                result.error(
                    "NOT_CONNECTED",
                    "The YouTube Music playback service is unavailable",
                    null,
                )
                return@connect
            }
            connected.setMediaItems(items, startIndex, 0L)
            connected.prepare()
            connected.play()
            result.success(true)
        }
    }

    private fun seekTo(call: MethodCall, result: MethodChannel.Result) {
        val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
        runOnController(result) { it.seekTo(positionMs) }
    }

    private fun setVisualizerEnabled(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val enable = call.argument<Boolean>("enabled") ?: false
        result.success(YtAudioSpectrum.setEnabled(context, enable))
    }

    private fun getState(result: MethodChannel.Result) {
        // Deliberately does not connect: reading state should not spin up the
        // media session (and its ExoPlayer) just because the UI asked once.
        val current = controller
        result.success(current?.let { stateMap(it) } ?: emptyStateMap())
    }

    private fun runOnController(
        result: MethodChannel.Result,
        block: (MediaController) -> Unit,
    ) {
        connect { connected ->
            if (connected == null) {
                result.error(
                    "NOT_CONNECTED",
                    "The YouTube Music playback service is unavailable",
                    null,
                )
                return@connect
            }
            try {
                block(connected)
                result.success(true)
            } catch (throwable: Throwable) {
                result.error("PLAYBACK", throwable.message, null)
            }
        }
    }

    private fun connect(onReady: (MediaController?) -> Unit) {
        val existing = controller
        if (existing != null) {
            onReady(existing)
            return
        }
        val token = SessionToken(
            context,
            ComponentName(context, YtPlaybackService::class.java),
        )
        val future: ListenableFuture<MediaController> =
            MediaController.Builder(context, token).buildAsync()
        future.addListener(
            {
                val connected = try {
                    future.get()
                } catch (exception: Exception) {
                    null
                }
                if (connected != null) {
                    controller = connected
                    connected.addListener(playerListener)
                }
                onReady(connected)
            },
            mainExecutor,
        )
    }

    private fun emitState(player: Player) {
        val payload = stateMap(player) + mapOf("type" to "state")
        stateSink?.success(payload)
    }

    private fun stateMap(player: Player): Map<String, Any?> {
        val item: MediaItem? = player.currentMediaItem
        val duration = player.duration
        return mapOf(
            "isPlaying" to player.isPlaying,
            "playWhenReady" to player.playWhenReady,
            "playbackState" to player.playbackState,
            "mediaId" to item?.mediaId,
            "title" to item?.mediaMetadata?.title?.toString(),
            "artist" to item?.mediaMetadata?.artist?.toString(),
            "positionMs" to player.currentPosition,
            "durationMs" to if (duration == C.TIME_UNSET) -1L else duration,
            "index" to player.currentMediaItemIndex,
            "queueSize" to player.mediaItemCount,
            "audioSessionId" to player.audioSessionId,
        )
    }

    private fun emptyStateMap(): Map<String, Any?> = mapOf(
        "isPlaying" to false,
        "playWhenReady" to false,
        "playbackState" to Player.STATE_IDLE,
        "mediaId" to null,
        "title" to null,
        "artist" to null,
        "positionMs" to 0L,
        "durationMs" to -1L,
        "index" to 0,
        "queueSize" to 0,
        "audioSessionId" to -1,
    )

    private fun replyError(result: MethodChannel.Result, throwable: Throwable) {
        val error = throwable.toYtMusicException()
        result.error(error.code.name, error.message, null)
    }

    companion object {
        const val METHODS_CHANNEL = "retropod/yt_music"
        const val EVENTS_CHANNEL = "retropod/yt_music/events"
        const val SPECTRUM_CHANNEL = "retropod/yt_music/spectrum"

        /**
         * Registers all three channels on [engine]. Must be called once, from
         * `MainActivity.configureFlutterEngine`.
         */
        @JvmStatic
        fun attach(engine: FlutterEngine, context: Context) {
            val appContext = context.applicationContext
            val bridge = YtMusicBridge(appContext, YtMusicProviders.get())
            val messenger = engine.dartExecutor.binaryMessenger
            MethodChannel(messenger, METHODS_CHANNEL)
                .setMethodCallHandler(bridge)
            EventChannel(messenger, EVENTS_CHANNEL)
                .setStreamHandler(bridge.stateStreamHandler)
            EventChannel(messenger, SPECTRUM_CHANNEL)
                .setStreamHandler(bridge.spectrumStreamHandler)
        }
    }
}
