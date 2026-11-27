package com.rchrdariza.retropod

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YoutubeSignInPolicyTest {
    @Test fun acceptsGoogleRedirectsAndFirstPartySessions() {
        assertTrue(YoutubeSignInPolicy.allows("https://accounts.youtube.com/accounts/SetSID"))
        assertTrue(YoutubeSignInPolicy.allows("https://accounts.google.co.in/ServiceLogin"))
        assertTrue(YoutubeSignInPolicy.hasSession("PREF=x; __Secure-1PAPISID=test"))
    }
    @Test fun rejectsLookalikesAndUnsafeOrigins() {
        for (url in listOf("http://accounts.google.com", "https://accounts.google.com.evil.test", "https://evilgoogle.com", "https://user@music.youtube.com", "https://accounts.google.com:444")) {
            assertFalse(YoutubeSignInPolicy.allows(url))
        }
        assertFalse(YoutubeSignInPolicy.hasSession("SAPISID=; PREF=test"))
        assertFalse(YoutubeSignInPolicy.hasSession("NOT_SAPISID=test"))
    }
}
