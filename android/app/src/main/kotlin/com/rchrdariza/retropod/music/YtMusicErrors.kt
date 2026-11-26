package com.rchrdariza.retropod.music

import java.io.IOException
import org.schabi.newpipe.extractor.exceptions.AccountTerminatedException
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.ExtractionException
import org.schabi.newpipe.extractor.exceptions.GeographicRestrictionException
import org.schabi.newpipe.extractor.exceptions.HttpResponseException
import org.schabi.newpipe.extractor.exceptions.PaidContentException
import org.schabi.newpipe.extractor.exceptions.ParsingException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import org.schabi.newpipe.extractor.exceptions.YoutubeMusicPremiumContentException

/**
 * Stable error identifiers shared with the Flutter side. Keep these names in
 * sync with the Dart wrapper (`YtMusicErrorCode`), they are part of the bridge
 * contract.
 */
enum class YtErrorCode {
    NETWORK,
    RATE_LIMITED,
    BOT_CHECK,
    AGE_RESTRICTED,
    PAID,
    PRIVATE,
    GEO_BLOCKED,
    UNAVAILABLE,
    INVALID_ID,
    NO_AUDIO_STREAM,
    PLAYBACK,
    EXTRACTION_FAILED,
    UNKNOWN,
}

/** Single exception type crossing the platform channel boundary. */
class YtMusicException(
    val code: YtErrorCode,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Normalizes everything the extractor can throw into a [YtMusicException], so
 * the bridge can forward a small, stable set of error codes.
 *
 * The clauses are ordered from the most specific extractor exception to the
 * most generic one because most of them extend each other.
 */
fun Throwable.toYtMusicException(): YtMusicException {
    if (this is YtMusicException) {
        return this
    }
    return when (this) {
        is SignInConfirmNotBotException -> YtMusicException(
            YtErrorCode.BOT_CHECK,
            "YouTube requires a sign-in confirmation (bot check). " +
                "A poToken provider or account cookies are required.",
            this,
        )

        is ReCaptchaException -> YtMusicException(
            YtErrorCode.RATE_LIMITED,
            "YouTube rate limited the request. Retry later.",
            this,
        )

        is AgeRestrictedContentException -> YtMusicException(
            YtErrorCode.AGE_RESTRICTED,
            "The track is age restricted and needs account cookies.",
            this,
        )

        is AccountTerminatedException -> YtMusicException(
            YtErrorCode.UNAVAILABLE,
            "The channel of this track has been terminated.",
            this,
        )

        is GeographicRestrictionException -> YtMusicException(
            YtErrorCode.GEO_BLOCKED,
            "The track is not available in this country.",
            this,
        )

        is YoutubeMusicPremiumContentException, is PaidContentException ->
            YtMusicException(
                YtErrorCode.PAID,
                "The track requires a YouTube Music Premium subscription.",
                this,
            )

        is PrivateContentException -> YtMusicException(
            YtErrorCode.PRIVATE,
            "The track is private.",
            this,
        )

        is ContentNotAvailableException -> YtMusicException(
            YtErrorCode.UNAVAILABLE,
            "The track is not available.",
            this,
        )

        is HttpResponseException -> YtMusicException(
            YtErrorCode.NETWORK,
            message ?: "YouTube answered with an unexpected HTTP response.",
            this,
        )

        is ParsingException -> YtMusicException(
            YtErrorCode.EXTRACTION_FAILED,
            "YouTube changed its response format, the extractor could not " +
                "parse it. Updating the extractor usually fixes this.",
            this,
        )

        is ExtractionException -> YtMusicException(
            YtErrorCode.EXTRACTION_FAILED,
            message ?: "Extraction failed.",
            this,
        )

        is IOException -> YtMusicException(
            YtErrorCode.NETWORK,
            "Network error: ${message ?: "unknown"}",
            this,
        )

        else -> YtMusicException(
            YtErrorCode.UNKNOWN,
            message ?: this::class.java.simpleName,
            this,
        )
    }
}
