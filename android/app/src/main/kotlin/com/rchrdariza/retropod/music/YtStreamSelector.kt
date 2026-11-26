package com.rchrdariza.retropod.music

import android.net.Uri
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.AudioTrackType
import org.schabi.newpipe.extractor.stream.DeliveryMethod

/**
 * Chooses which of the audio streams offered by YouTube should be played.
 *
 * Only progressive HTTP streams are usable as a plain ExoPlayer `MediaItem`
 * URI. YouTube also exposes DASH audio, but for those streams the extractor
 * returns a base64 initialization segment instead of a URL, and the real
 * playback would need the DASH manifest and a signed segment template.
 *
 * The selection rules are isolated from the extractor and the player, so they
 * can be unit tested with a fake list of streams (the expiry parser needs an
 * Android `Uri`, so those tests run under Robolectric or on a device).
 */
object YtStreamSelector {

    fun select(
        streams: List<AudioStream>,
        preferredFormat: YtAudioFormat,
    ): AudioStream? {
        val progressive = streams.filter { stream ->
            stream.isUrl &&
                stream.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP &&
                isOriginalAudio(stream)
        }
        if (progressive.isEmpty()) {
            return null
        }
        val preferred = progressive.filter { stream ->
            stream.format?.mimeType == preferredFormat.mimeType
        }
        val pool = preferred.ifEmpty { progressive }
        return pool.maxByOrNull { bitrateKbps(it) }
    }

    /** Bitrate in kbit/s, or 0 when YouTube did not report one. */
    fun bitrateKbps(stream: AudioStream): Int {
        val bitsPerSecond = when {
            stream.averageBitrate > 0 -> stream.averageBitrate
            stream.bitrate > 0 -> stream.bitrate
            else -> 0
        }
        return bitsPerSecond / 1000
    }

    /**
     * Expiry of a signed `googlevideo.com` URL, taken from its `expire` query
     * parameter (seconds since the epoch).
     */
    fun expiresAtEpochMs(url: String): Long? =
        Uri.parse(url)
            .getQueryParameter("expire")
            ?.toLongOrNull()
            ?.times(1000L)

    private fun isOriginalAudio(stream: AudioStream): Boolean {
        val trackType = stream.audioTrackType ?: return true
        return trackType == AudioTrackType.ORIGINAL
    }
}
