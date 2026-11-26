package com.rchrdariza.retropod.music

/**
 * Constants shared by the extraction and playback layers.
 */
object YtDefaults {
    /**
     * User agent used both for InnerTube requests and for the media requests
     * made by ExoPlayer. `googlevideo.com` URLs are signed for a client, but a
     * stable, browser-like user agent avoids most of the "403 Forbidden"
     * responses that stock Android players trigger.
     */
    const val HTTP_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    const val WATCH_URL_PREFIX = "https://www.youtube.com/watch?v="

    const val DEFAULT_SEARCH_RESULTS = 25
    const val MAX_SEARCH_RESULTS = 50

    /** YouTube video ids are 11 characters out of a fixed alphabet. */
    val VIDEO_ID_PATTERN = Regex("^[A-Za-z0-9_-]{11}$")
}
