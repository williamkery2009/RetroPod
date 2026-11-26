package com.rchrdariza.retropod.music

/**
 * Metadata of a single YouTube Music track.
 *
 * [videoId] is the YouTube video id (for example `fHI8X4OXluQ` for "Blinding
 * Lights"). It is the only identifier needed to search, resolve a stream or
 * restore a queue, so it is also the media id used by the Media3 session.
 */
data class YtTrack(
    val videoId: String,
    val title: String,
    val artist: String,
    val thumbnailUrl: String?,
    val durationMs: Long,
) {
    /** Flat representation handed to the Flutter side of the bridge. */
    fun toMap(): Map<String, Any?> = mapOf(
        "videoId" to videoId,
        "title" to title,
        "artist" to artist,
        "thumbnailUrl" to thumbnailUrl,
        "durationMs" to durationMs,
    )

    companion object {
        /** Rebuilds a track from the map produced by [toMap]. */
        fun fromMap(map: Map<*, *>): YtTrack? {
            val videoId = (map["videoId"] as? String)?.trim().orEmpty()
            if (videoId.isEmpty()) {
                return null
            }
            return YtTrack(
                videoId = videoId,
                title = map["title"] as? String ?: videoId,
                artist = map["artist"] as? String ?: "",
                thumbnailUrl = map["thumbnailUrl"] as? String,
                durationMs = (map["durationMs"] as? Number)?.toLong() ?: 0L,
            )
        }
    }
}

/**
 * Audio containers we ask YouTube for.
 *
 * YouTube serves the same audio twice: AAC inside an MP4 container (`itag`
 * 140/139, the `.m4a` stream) and Opus inside WebM (`itag` 251/250, the
 * `.webm` stream). AAC is the safer default because it is decoded by the
 * platform on every supported Android version, while Opus in WebM relies on
 * device and device-version support.
 */
enum class YtAudioFormat(val mimeType: String, val extension: String) {
    M4A("audio/mp4", "m4a"),
    WEBM("audio/webm", "webm"),
}

/**
 * A resolved, directly playable audio stream.
 *
 * [url] is a signed `googlevideo.com` URL. It is bound to the requesting IP
 * address and expires (see [expiresAtEpochMs]), so it must never be cached for
 * long or shared between devices.
 */
data class YtStreamInfo(
    val videoId: String,
    val url: String,
    val mimeType: String,
    val codec: String?,
    val bitrateKbps: Int,
    val itag: Int,
    val expiresAtEpochMs: Long?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "videoId" to videoId,
        "url" to url,
        "mimeType" to mimeType,
        "codec" to codec,
        "bitrateKbps" to bitrateKbps,
        "itag" to itag,
        "expiresAtEpochMs" to expiresAtEpochMs,
    )
}
