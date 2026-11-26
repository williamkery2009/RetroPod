package com.rchrdariza.retropod.music

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.ParsingException
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory
import org.schabi.newpipe.extractor.stream.ContentAvailability
import org.schabi.newpipe.extractor.stream.StreamInfoItem

/**
 * [YtMusicProvider] backed by NewPipeExtractor.
 *
 * The extractor handles the moving parts of the Innertube protocol that break
 * every few weeks if you implement them yourself:
 *
 * - current `WEB_REMIX` / player client versions and their headers;
 * - the `signatureCipher` and `n` throttling parameter transformations
 *   (executed through Rhino, the JavaScript engine bundled by the extractor);
 * - poToken and visitor data plumbing for clients that require them.
 *
 * All calls block, so they are always dispatched to [Dispatchers.IO].
 */
internal class NewPipeYtMusicProvider : YtMusicProvider {

    override suspend fun search(query: String, limit: Int): List<YtTrack> =
        withContext(Dispatchers.IO) {
            val trimmed = query.trim()
            if (trimmed.isEmpty()) {
                return@withContext emptyList()
            }
            try {
                val service = ServiceList.YouTube
                val queryHandler = service.searchQHFactory.fromQuery(
                    trimmed,
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
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (throwable: Throwable) {
                throw throwable.toYtMusicException()
            }
        }

    override suspend fun resolveStream(
        videoId: String,
        preferredFormat: YtAudioFormat,
    ): YtStreamInfo = withContext(Dispatchers.IO) {
        if (!YtDefaults.VIDEO_ID_PATTERN.matches(videoId)) {
            throw YtMusicException(
                YtErrorCode.INVALID_ID,
                "Not a YouTube video id: $videoId",
            )
        }
        try {
            val extractor = ServiceList.YouTube.getStreamExtractor(
                YtDefaults.WATCH_URL_PREFIX + videoId,
            )
            extractor.fetchPage()
            val availability = extractor.contentAvailability
            if (
                availability == ContentAvailability.PAID ||
                availability == ContentAvailability.MEMBERSHIP
            ) {
                throw YtMusicException(
                    YtErrorCode.PAID,
                    "The track requires a YouTube Music Premium subscription.",
                )
            }
            if (availability == ContentAvailability.UPCOMING) {
                throw YtMusicException(
                    YtErrorCode.UNAVAILABLE,
                    "The track has not been released yet.",
                )
            }

            val stream = YtStreamSelector.select(
                extractor.audioStreams,
                preferredFormat,
            ) ?: throw YtMusicException(
                YtErrorCode.NO_AUDIO_STREAM,
                "YouTube did not expose a progressive audio stream for " +
                    videoId + ". Live streams and some region locked tracks " +
                    "are only available as DASH.",
            )

            YtStreamInfo(
                videoId = videoId,
                url = stream.content,
                mimeType = stream.format?.mimeType ?: preferredFormat.mimeType,
                codec = stream.codec,
                bitrateKbps = YtStreamSelector.bitrateKbps(stream),
                itag = stream.itag,
                expiresAtEpochMs = YtStreamSelector.expiresAtEpochMs(
                    stream.content,
                ),
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (throwable: Throwable) {
            throw throwable.toYtMusicException()
        }
    }

    private fun StreamInfoItem.toYtTrack(): YtTrack? {
        val videoId = try {
            YoutubeStreamLinkHandlerFactory.getInstance().getId(url)
        } catch (exception: ParsingException) {
            return null
        }
        if (videoId.isBlank()) {
            return null
        }
        // The collector already resolved both fields while building the item.
        val artist = uploaderName.orEmpty()
        val durationSeconds = duration
        return YtTrack(
            videoId = videoId,
            title = name.orEmpty().ifBlank { videoId },
            artist = artist,
            thumbnailUrl = pickThumbnail(),
            durationMs = if (durationSeconds > 0) durationSeconds * 1000L else 0L,
        )
    }

    /**
     * YouTube Music returns the same artwork at several resolutions. Prefer the
     * largest variant that is still reasonable for a list tile, and fall back to
     * whatever is available.
     */
    private fun StreamInfoItem.pickThumbnail(): String? {
        val images = thumbnails.orEmpty()
        if (images.isEmpty()) {
            return null
        }
        val sized = images.filter { image ->
            image.width in 1..DISPLAY_ARTWORK_MAX_PX
        }
        val largestSized = sized.maxByOrNull { image -> image.width }
        val largest = images.maxByOrNull { image -> image.width }
        return (largestSized ?: largest)?.url
    }

    private companion object {
        const val DISPLAY_ARTWORK_MAX_PX = 600
    }
}
