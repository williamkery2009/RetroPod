package com.rchrdariza.retropod

import java.net.URI

internal object YoutubeSignInPolicy {
    private val hosts = setOf(
        "music.youtube.com", "youtube.com", "www.youtube.com", "m.youtube.com",
        "accounts.youtube.com", "accounts.google.com", "consent.google.com",
        "consent.youtube.com", "www.google.com", "www.google.co.in", "accounts.google.co.in"
    )
    fun allows(url: String): Boolean = try {
        val uri = URI(url)
        uri.scheme == "https" && uri.rawUserInfo == null && uri.port in listOf(-1, 443) &&
            uri.host?.lowercase() in hosts
    } catch (_: Exception) { false }

    fun hasSession(cookie: String): Boolean = cookie.split(';').any {
        val parts = it.trim().split('=', limit = 2)
        parts.size == 2 && parts[1].isNotBlank() &&
            parts[0] in setOf("SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID")
    }
}
