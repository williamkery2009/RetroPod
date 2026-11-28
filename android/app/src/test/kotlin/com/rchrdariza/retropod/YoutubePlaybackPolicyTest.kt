package com.rchrdariza.retropod

import com.rchrdariza.retropod.YoutubePlaybackPolicy.Format
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class YoutubePlaybackPolicyTest {
    private fun format(name: String, mime: String, bitrate: Int, isProtected: Boolean = false) =
        Format("https://r1.googlevideo.com/$name", mime, bitrate, isProtected)

    @Test fun prefersAacThenBitrate() {
        val picked = YoutubePlaybackPolicy.pick(
            listOf(
                format("opus", "audio/webm; codecs=\"opus\"", 160000),
                format("low", "audio/mp4", 48000),
                format("high", "audio/mp4", 128000),
            ),
            listOf(format("muxed", "video/mp4", 500000)),
        )
        assertEquals("https://r1.googlevideo.com/high", picked)
    }

    @Test fun fallsBackToSmallestDirectCombinedMp4() {
        val picked = YoutubePlaybackPolicy.pick(
            listOf(Format("", "audio/mp4", 128000, true)),
            listOf(
                format("large", "video/mp4", 2000000),
                format("small", "video/mp4", 500000),
                format("unknown", "video/mp4", 0),
                format("webm", "video/webm", 100),
            ),
        )
        assertEquals("https://r1.googlevideo.com/small", picked)
    }

    @Test fun neverPicksProtectedOrForeignLinks() {
        val protectedOnly = listOf(format("a", "audio/mp4", 1, isProtected = true))
        assertNull(YoutubePlaybackPolicy.pick(protectedOnly, emptyList()))
        assertEquals("YT_PROTECTED_ONLY", YoutubePlaybackPolicy.noAudioFailure(protectedOnly))
        assertEquals("YT_SESSION_NO_AUDIO", YoutubePlaybackPolicy.noAudioFailure(emptyList()))
        for (url in listOf(
            "http://r1.googlevideo.com/a",
            "https://googlevideo.com.evil.test/a",
            "https://user@r1.googlevideo.com/a",
            "https://r1.googlevideo.com:444/a",
        )) {
            assertNull(YoutubePlaybackPolicy.pick(listOf(Format(url, "audio/mp4", 1, false)), emptyList()))
        }
    }

    @Test fun separatesFailureReasons() {
        assertNull(YoutubePlaybackPolicy.httpFailure(200))
        assertEquals("YT_SESSION_EXPIRED", YoutubePlaybackPolicy.httpFailure(401))
        assertEquals("YT_SESSION_REJECTED", YoutubePlaybackPolicy.httpFailure(403))
        assertEquals("YT_ACCOUNT_RATE_LIMIT", YoutubePlaybackPolicy.httpFailure(429))
        assertEquals("YT_ACCOUNT_SERVER", YoutubePlaybackPolicy.httpFailure(503))
        assertNull(YoutubePlaybackPolicy.playabilityFailure("OK"))
        assertEquals("YT_ACCOUNT_VERIFY", YoutubePlaybackPolicy.playabilityFailure("LOGIN_REQUIRED"))
        assertEquals("YT_TRACK_UNAVAILABLE", YoutubePlaybackPolicy.playabilityFailure("UNPLAYABLE"))
        assertEquals("YT_SESSION_REJECTED", YoutubePlaybackPolicy.playabilityFailure(""))
    }
}
