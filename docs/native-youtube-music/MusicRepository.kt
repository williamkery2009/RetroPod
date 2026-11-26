package com.example.music

import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfoItem

/** Blocking HTTP transport required by NewPipe; used only on Dispatchers.IO. */
class ExtractorDownloader(private val client: OkHttpClient) : Downloader() {
    override fun execute(request: Request): Response {
        val contentType = request.headers().entries
            .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
            ?.value?.firstOrNull()?.toMediaTypeOrNull()
        val body = request.dataToSend()?.toRequestBody(contentType)
            ?: if (request.httpMethod() in setOf("POST", "PUT", "PATCH")) {
                ByteArray(0).toRequestBody(contentType)
            } else null
        val builder = okhttp3.Request.Builder().url(request.url())
            .header("User-Agent", "RetroPod-NativeExample/1.0")
        request.headers().forEach { (name, values) ->
            builder.removeHeader(name)
            values.forEach { builder.addHeader(name, it) }
        }
        builder.method(request.httpMethod(), body)
        return client.newCall(builder.build()).execute().use { response ->
            if (response.code == 429) throw IOException("YouTube rate limited this request")
            Response(
                response.code,
                response.message,
                response.headers.toMultimap(),
                response.body?.string().orEmpty(),
                response.request.url.toString(),
            )
        }
    }
}

data class TrackResult(
    val videoId: String,
    val title: String,
    val artist: String,
    val thumbnail: String?,
)

data class DirectAudio(
    val videoId: String,
    val url: String,
    val mimeType: String,
    val bitrateKbps: Int,
)

/** Initialize once in Application.onCreate(), not on each search. */
object MusicRepository {
    private val youtube = ServiceList.YouTube
    private val extractionMutex = Mutex()
    private val validId = Regex("^[A-Za-z0-9_-]{11}$")
    @Volatile private var initialized = false

    @Synchronized
    fun initialize() {
        if (initialized) return
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            .build()
        NewPipe.init(ExtractorDownloader(client))
        initialized = true
    }

    /** First result page; debounce calls in the UI. */
    suspend fun search(query: String): List<TrackResult> = withContext(Dispatchers.IO) {
        if (query.isBlank()) return@withContext emptyList()
        check(initialized) { "Call MusicRepository.initialize() first" }
        extractionMutex.withLock {
            currentCoroutineContext().ensureActive()
            val extractor = youtube.getSearchExtractor(
                query.trim(),
                listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS),
                "",
            )
            extractor.fetchPage()
            val items = extractor.initialPage.items
            currentCoroutineContext().ensureActive()
            items.filterIsInstance<StreamInfoItem>().map { item ->
                TrackResult(
                    videoId = youtube.streamLHFactory.getId(item.url),
                    title = item.name,
                    artist = item.uploaderName.orEmpty(),
                    thumbnail = item.thumbnails
                        .maxByOrNull { it.width.coerceAtLeast(0) }?.url,
                )
            }.distinctBy { it.videoId }
        }
    }

    /** Selects an audio-only progressive stream, never a video/muxed stream. */
    suspend fun resolveAudio(videoId: String): DirectAudio = withContext(Dispatchers.IO) {
        require(validId.matches(videoId)) { "Invalid YouTube video ID" }
        check(initialized) { "Call MusicRepository.initialize() first" }
        extractionMutex.withLock {
            currentCoroutineContext().ensureActive()
            val extractor = youtube.getStreamExtractor("https://www.youtube.com/watch?v=$videoId")
            extractor.fetchPage()
            val streams = extractor.audioStreams.filter { stream ->
                stream.isUrl &&
                    stream.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP &&
                    URI(stream.content).scheme == "https" &&
                    stream.format in setOf(MediaFormat.M4A, MediaFormat.WEBMA, MediaFormat.WEBMA_OPUS)
            }
            currentCoroutineContext().ensureActive()
            // Prefer AAC/M4A for compatibility, then the highest offered bitrate.
            val selected = streams.maxWithOrNull(
                compareBy<org.schabi.newpipe.extractor.stream.AudioStream> {
                    if (it.format == MediaFormat.M4A) 1 else 0
                }.thenBy { it.averageBitrate },
            ) ?: throw IOException("No supported public audio stream is available")
            DirectAudio(
                videoId = videoId,
                url = selected.content,
                mimeType = if (selected.format == MediaFormat.M4A) "audio/mp4" else "audio/webm",
                bitrateKbps = selected.averageBitrate,
            )
        }
    }
}
