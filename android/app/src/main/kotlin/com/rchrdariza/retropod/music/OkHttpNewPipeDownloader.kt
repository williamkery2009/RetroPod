package com.rchrdariza.retropod.music

import java.util.Locale
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response as NewPipeResponse

/**
 * NewPipeExtractor owns the InnerTube protocol details (client versions,
 * player configs, signature and `n` parameter deciphering, poToken handling),
 * but it stays network agnostic: every request goes through [Downloader].
 *
 * This implementation routes those requests through a single [OkHttpClient],
 * which gives us connection pooling, HTTP/2 and transparent gzip handling.
 */
internal class OkHttpNewPipeDownloader(
    private val client: OkHttpClient,
    private val userAgent: String,
) : Downloader() {

    override fun execute(request: Request): NewPipeResponse {
        val builder = okhttp3.Request.Builder()
            .url(request.url())
            .method(request.httpMethod(), bodyFor(request))

        var hasUserAgent = false
        for ((name, values) in request.headers()) {
            val normalized = name.lowercase(Locale.US)
            if (normalized == "user-agent") {
                hasUserAgent = true
            }
            // OkHttp manages these itself. Forwarding Accept-Encoding would
            // disable its transparent gzip decoding and the extractor would
            // receive compressed bytes where it expects JSON.
            if (normalized in MANAGED_HEADERS) {
                continue
            }
            for (value in values) {
                builder.addHeader(name, value)
            }
        }
        if (!hasUserAgent) {
            builder.header("User-Agent", userAgent)
        }

        client.newCall(builder.build()).execute().use { response ->
            val responseBody = response.body?.string().orEmpty()
            return NewPipeResponse(
                response.code,
                response.message,
                response.headers.toMultimap(),
                responseBody,
                response.request.url.toString(),
            )
        }
    }

    private fun bodyFor(request: Request): RequestBody? {
        val data = request.dataToSend()
        val contentType = contentTypeOf(request)
        if (data != null) {
            return data.toRequestBody(contentType)
        }
        return when (request.httpMethod().uppercase(Locale.US)) {
            "POST", "PUT", "PATCH" -> ByteArray(0).toRequestBody(contentType)
            else -> null
        }
    }

    private fun contentTypeOf(request: Request): MediaType? =
        request.headers()
            .entries
            .firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }
            ?.value
            ?.firstOrNull()
            ?.toMediaTypeOrNull()

    private companion object {
        val MANAGED_HEADERS = setOf(
            "accept-encoding",
            "connection",
            "content-length",
            "expect",
            "host",
            "transfer-encoding",
        )
    }
}
