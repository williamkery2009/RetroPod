package com.rchrdariza.retropod.music.playback

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.rchrdariza.retropod.music.YtTrack

/**
 * Builds the `MediaItem`s that enter the Media3 queue.
 *
 * The URI stored in the queue is a placeholder (`ytmusic://track/<videoId>`),
 * never a stream URL: signed `googlevideo.com` URLs expire and are bound to the
 * device IP, so resolving them lazily (when a track is actually about to play)
 * is the only reliable approach. [YtPlaybackService] swaps the placeholder for
 * the real URL in `onSetMediaItems` / `onAddMediaItems`.
 */
internal object YtMediaItems {

    private const val SCHEME = "ytmusic"
    private const val HOST = "track"

    fun uriFor(videoId: String): Uri = Uri.parse("$SCHEME://$HOST/$videoId")

    fun fromTrack(track: YtTrack): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(track.title)
            .setArtist(track.artist)
            .setIsBrowsable(false)
            .setIsPlayable(true)
        val artworkUrl = track.thumbnailUrl
        if (artworkUrl != null && artworkUrl.startsWith("https://")) {
            metadata.setArtworkUri(Uri.parse(artworkUrl))
        }
        return MediaItem.Builder()
            .setMediaId(track.videoId)
            .setUri(uriFor(track.videoId))
            .setMediaMetadata(metadata.build())
            .build()
    }

    fun videoIdOf(item: MediaItem): String? {
        if (item.mediaId.isNotBlank()) {
            return item.mediaId
        }
        val placeholder = item.localConfiguration?.uri ?: return null
        if (placeholder.scheme != SCHEME) {
            return null
        }
        return placeholder.lastPathSegment
    }
}
