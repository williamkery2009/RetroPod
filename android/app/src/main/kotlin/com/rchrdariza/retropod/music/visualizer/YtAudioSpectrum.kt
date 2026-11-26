package com.rchrdariza.retropod.music.visualizer

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import com.rchrdariza.retropod.music.playback.YtPlaybackService
import kotlin.math.max
import kotlin.math.min

/**
 * Audio spectrum capture for custom visualizers.
 *
 * ExoPlayer exposes the audio session it renders to through
 * `ExoPlayer.audioSessionId`; attaching an `android.media.audiofx.Visualizer`
 * to that session gives FFT frames without touching the microphone and without
 * routing playback through a recorder. `Visualizer` still requires the
 * `RECORD_AUDIO` runtime permission on Android 9+, which is why the manifest
 * declares it and why enabling the visualizer returns false when the user has
 * not granted it.
 *
 * The audio session id can change whenever ExoPlayer re-creates its audio
 * renderer, so the session is polled once per second and the `Visualizer` is
 * rebound when it changes.
 */
object YtAudioSpectrum {

    /** Number of frequency bands pushed to the UI. */
    const val BAND_COUNT = 24

    private const val SESSION_POLL_MS = 1_000L

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: ((FloatArray) -> Unit)? = null

    private var visualizer: Visualizer? = null
    private var boundSessionId = 0
    private var enabled = false

    private val sessionWatcher = object : Runnable {
        override fun run() {
            if (!enabled) {
                return
            }
            val sessionId = YtPlaybackService.audioSessionId()
            if (sessionId > 0 && sessionId != boundSessionId) {
                bind(sessionId)
            }
            mainHandler.postDelayed(this, SESSION_POLL_MS)
        }
    }

    /** Consumer of normalized band magnitudes, called on the main thread. */
    fun setSink(consumer: ((FloatArray) -> Unit)?) {
        sink = consumer
    }

    /**
     * Enables or disables capture.
     *
     * @return true when capture was requested, the permission is granted and
     * playback is ready to be captured. Bands start flowing one poll later if
     * the audio session is not available yet.
     */
    fun setEnabled(context: Context, enable: Boolean): Boolean {
        val granted = hasRecordPermission(context)
        mainHandler.post { apply(enable, granted) }
        return enable && granted
    }

    fun isEnabled(): Boolean = enabled

    private fun apply(enable: Boolean, granted: Boolean) {
        enabled = enable && granted
        mainHandler.removeCallbacks(sessionWatcher)
        if (!enabled) {
            releaseVisualizer()
            boundSessionId = 0
            return
        }
        sessionWatcher.run()
    }

    private fun hasRecordPermission(context: Context): Boolean =
        context.packageManager.checkPermission(
            Manifest.permission.RECORD_AUDIO,
            context.packageName,
        ) == PackageManager.PERMISSION_GRANTED

    private fun bind(sessionId: Int) {
        releaseVisualizer()
        boundSessionId = sessionId
        val created = try {
            Visualizer(sessionId)
        } catch (exception: Exception) {
            boundSessionId = 0
            return
        }
        val listener = object : Visualizer.OnDataCaptureListener {
            override fun onWaveFormDataCapture(
                visualizer: Visualizer?,
                waveform: ByteArray?,
                samplingRate: Int,
            ) = Unit

            override fun onFftDataCapture(
                visualizer: Visualizer?,
                fft: ByteArray?,
                samplingRate: Int,
            ) {
                if (fft == null) {
                    return
                }
                val bands = bandsFromFft(fft)
                mainHandler.post { sink?.invoke(bands) }
            }
        }
        val configured = try {
            created.captureSize = Visualizer.getCaptureSizeRange()[1]
            created.setDataCaptureListener(
                listener,
                max(Visualizer.getMaxCaptureRate() / 2, 1),
                false,
                true,
            )
            created.enabled = true
            true
        } catch (exception: Exception) {
            false
        }
        if (configured) {
            visualizer = created
        } else {
            created.release()
        }
    }

    private fun releaseVisualizer() {
        val current = visualizer ?: return
        visualizer = null
        try {
            current.enabled = false
        } catch (exception: Exception) {
            // The session may already be gone; releasing is enough.
        }
        try {
            current.release()
        } catch (exception: Exception) {
            // Nothing else to clean up.
        }
    }

    /**
     * Converts Android's 8-bit FFT magnitudes into [BAND_COUNT] normalized
     * bands. `fft` holds interleaved (real, imaginary) bytes; only the real
     * part carries a usable magnitude.
     */
    private fun bandsFromFft(fft: ByteArray): FloatArray {
        val bands = FloatArray(BAND_COUNT)
        val bins = fft.size / 2
        if (bins <= 0) {
            return bands
        }
        for (band in 0 until BAND_COUNT) {
            val from = (bins * band / BAND_COUNT)
            val to = min(
                max(from + 1, bins * (band + 1) / BAND_COUNT),
                bins,
            )
            var sum = 0f
            var count = 0
            for (bin in from until to) {
                sum += (fft[2 * bin].toInt() and 0xFF) / 255f
                count += 1
            }
            bands[band] = if (count > 0) {
                (sum / count).coerceIn(0f, 1f)
            } else {
                0f
            }
        }
        return bands
    }
}
