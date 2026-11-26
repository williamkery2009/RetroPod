package com.rchrdariza.retropod.music

import java.util.Locale
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization

/**
 * Everything the player needs from YouTube Music.
 *
 * The interface is deliberately tiny and free of NewPipe types so the
 * extractor can be swapped (a pure Innertube client, a self-hosted Piped or
 * Invidious instance, a cached/local source) without touching playback code.
 */
interface YtMusicProvider {
    /**
     * Searches the YouTube Music catalogue for songs matching [query].
     *
     * @param limit maximum number of tracks returned, clamped to
     * [YtDefaults.MAX_SEARCH_RESULTS].
     */
    suspend fun search(query: String, limit: Int = 25): List<YtTrack>

    /**
     * Resolves the direct audio URL of [videoId].
     *
     * @param preferredFormat container to prefer; the resolver falls back to
     * the other container when the preferred one is not offered.
     */
    suspend fun resolveStream(
        videoId: String,
        preferredFormat: YtAudioFormat = YtAudioFormat.M4A,
    ): YtStreamInfo
}

/**
 * Lazily creates the single provider used by the process and performs the
 * one-time NewPipeExtractor initialization.
 *
 * `NewPipe.init` configures global state (downloader, content country,
 * preferred localization), so it has to run exactly once before any extractor
 * is created.
 */
object YtMusicProviders {
    @Volatile
    private var cached: YtMusicProvider? = null

    fun get(): YtMusicProvider {
        cached?.let { return it }
        return synchronized(this) {
            cached ?: create().also { cached = it }
        }
    }

    private fun create(): YtMusicProvider {
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(60, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .build()

        val locale = Locale.getDefault()
        val country = locale.country
            .takeIf { it.isNotBlank() }
            ?.let { ContentCountry(it) }
            ?: ContentCountry.DEFAULT

        NewPipe.init(
            OkHttpNewPipeDownloader(client, YtDefaults.HTTP_USER_AGENT),
            Localization.fromLocale(locale),
            country,
        )
        return NewPipeYtMusicProvider()
    }
}
