package com.rchrdariza.retropod

import java.net.URI

/** Decisions about player responses. Protected links are detected, never decoded. */
internal object YoutubePlaybackPolicy {
    data class Format(
        val url: String,
        val mimeType: String,
        val bitrate: Int,
        val isProtected: Boolean,
    )

    /** Failure code for a non-200 player request, or null when it succeeded. */
    fun httpFailure(status: Int): String? = when (status) {
        200 -> null
        401 -> "YT_SESSION_EXPIRED"
        429 -> "YT_ACCOUNT_RATE_LIMIT"
        in 500..599 -> "YT_ACCOUNT_SERVER"
        else -> "YT_SESSION_REJECTED"
    }

    /** Failure code for the response's playability status, or null when playable. */
    fun playabilityFailure(status: String): String? = when (status) {
        "OK" -> null
        "LOGIN_REQUIRED", "AGE_CHECK_REQUIRED", "AGE_VERIFICATION_REQUIRED",
        "CONTENT_CHECK_REQUIRED" -> "YT_ACCOUNT_VERIFY"
        "UNPLAYABLE", "ERROR", "LIVE_STREAM_OFFLINE" -> "YT_TRACK_UNAVAILABLE"
        else -> "YT_SESSION_REJECTED"
    }

    fun isStreamUrl(url: String): Boolean = try {
        val uri = URI(url)
        val host = uri.host?.lowercase()
        uri.scheme == "https" && uri.rawUserInfo == null && uri.port in listOf(-1, 443) &&
            host != null && (host == "googlevideo.com" || host.endsWith(".googlevideo.com"))
    } catch (_: Exception) { false }

    /**
     * Picks from audio-only formats first (AAC before Opus, then bitrate). If none
     * has a direct link, uses a combined MP4, preferring the lowest bitrate
     * because its video is downloaded but never shown.
     */
    fun pick(adaptive: List<Format>, combined: List<Format>): String? {
        fun List<Format>.direct() = filter { !it.isProtected && isStreamUrl(it.url) }
        val audio = adaptive.direct().filter {
            it.mimeType.startsWith("audio/mp4") || it.mimeType.startsWith("audio/webm")
        }.sortedWith(
            compareByDescending<Format> { it.mimeType.startsWith("audio/mp4") }
                .thenByDescending { it.bitrate },
        ).firstOrNull()
        if (audio != null) return audio.url
        return combined.direct().filter { it.mimeType.startsWith("video/mp4") }
            .minByOrNull { if (it.bitrate > 0) it.bitrate else Int.MAX_VALUE }?.url
    }

    fun noAudioFailure(formats: List<Format>): String =
        if (formats.any { it.isProtected }) "YT_PROTECTED_ONLY" else "YT_SESSION_NO_AUDIO"
}
