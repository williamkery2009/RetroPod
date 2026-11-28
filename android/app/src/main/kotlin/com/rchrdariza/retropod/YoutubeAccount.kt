package com.rchrdariza.retropod

import android.app.Activity
import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection

/** No cookies, credentials or response bodies cross the Flutter channel. */
object YoutubeAccount {
    private const val ORIGIN = "https://music.youtube.com"
    private const val KEY = "retropod.youtube.session.v1"
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var loginOpen = false
    private var activeDialog: Dialog? = null
    fun closeLogin() { activeDialog?.dismiss() }
    private class Failure(val code: String) : Exception()

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "retropod/youtube_account").setMethodCallHandler { call, result ->
            if (call.method == "signIn") {
                if (loginOpen) result.error("YT_ACCOUNT_BUSY", null, null)
                else try { signIn(activity, result) } catch (_: Exception) {
                    loginOpen = false
                    result.error("YT_ACCOUNT_UNAVAILABLE", null, null)
                }
            } else if (loginOpen) {
                result.error("YT_ACCOUNT_BUSY", null, null)
            } else {
                worker.execute {
                    try {
                        val value: Any? = when (call.method) {
                            "status" -> read(activity) != null
                            "signOut" -> { sessionFile(activity).delete(); true }
                            "resolve" -> resolve(activity, call.argument<String>("videoId") ?: "")
                            else -> throw Failure("YT_ACCOUNT_UNAVAILABLE")
                        }
                        main.post {
                            if (call.method == "signOut") {
                                WebStorage.getInstance().deleteAllData()
                                CookieManager.getInstance().removeAllCookies {
                                    CookieManager.getInstance().flush()
                                    result.success(value)
                                }
                            } else result.success(value)
                        }
                    } catch (e: Failure) {
                        main.post { result.error(e.code, null, null) }
                    } catch (_: Exception) {
                        main.post { result.error("YT_ACCOUNT_UNAVAILABLE", null, null) }
                    }
                }
            }
        }
    }

    private fun sessionFile(context: Context) = AtomicFile(File(context.noBackupFilesDir, "youtube-session.bin"))
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized private fun save(context: Context, value: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        val file = sessionFile(context)
        val out = file.startWrite()
        try { out.write(encrypted); file.finishWrite(out) }
        catch (e: Exception) { file.failWrite(out); throw e }
    }
    @Synchronized private fun read(context: Context): JSONObject? {
        val file = sessionFile(context)
        if (!file.baseFile.exists()) return null
        try {
            val bytes = file.readFully()
            require(bytes.size in 29..131072)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        } catch (_: Exception) {
            file.delete()
            throw Failure("YT_SESSION_EXPIRED")
        }
    }

    // Restrict top-level navigation; no JavaScript interface and no TLS overrides.


    @Suppress("SetJavaScriptEnabled")
    private fun signIn(activity: Activity, result: MethodChannel.Result) {
        loginOpen = true
        val dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar)
        val layout = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val note = TextView(activity).apply {
            text = "Sign in on Google's page, then tap Use account. Google may block embedded sign-in. Saving a session does not guarantee playback."
            setPadding(16, 16, 16, 8)
            setTextColor(Color.BLACK)
        }
        val address = TextView(activity).apply { setPadding(16, 0, 16, 8) }
        val web = WebView(activity)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            setSupportMultipleWindows(false)
            mediaPlaybackRequiresUserGesture = true
            cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
        }
        val cookies = CookieManager.getInstance()
        cookies.setAcceptCookie(true)
        cookies.setAcceptThirdPartyCookies(web, true)
        var rendererGone = false
        var saved = false
        var closing = false
        var saving = false
        var attempt = 0
        val loginHandler = Handler(Looper.getMainLooper())
        val slowPage = Runnable {
            if (!closing && !saving) note.text = "The page is taking a long time. Finish any Google verification, tap Return to YouTube Music, or Start over."
        }
        val use = Button(activity).apply { text = "Use account" }
        web.webViewClient = object : WebViewClient() {
            private fun blocked(uri: Uri): Boolean {
                if (YoutubeSignInPolicy.allows(uri.toString())) return false
                note.text = "Sign-in stopped at an unsupported page (${uri.host ?: "unknown host"}). Use Start over; tap Start over to retry."
                return true
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = blocked(request.url)
            @Deprecated("Legacy navigation")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = blocked(Uri.parse(url))
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                address.text = Uri.parse(url).host ?: ""
                loginHandler.removeCallbacks(slowPage)
                loginHandler.postDelayed(slowPage, 30000)
            }
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                address.text = Uri.parse(url).host ?: ""
                if (Uri.parse(url).host == "music.youtube.com" && YoutubeSignInPolicy.hasSession(cookies.getCookie(ORIGIN) ?: "")) {
                    note.text = "YouTube Music has session cookies. Tap Use account to check and save this session."
                }
            }
            override fun onPageFinished(view: WebView, url: String) {
                loginHandler.removeCallbacks(slowPage)
                address.text = Uri.parse(url).host ?: ""
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: android.webkit.WebResourceError) {
                if (request.isForMainFrame) {
                    loginHandler.removeCallbacks(slowPage)
                    note.text = "The sign-in page could not load. Check the connection or tap Start over."
                }
            }
            override fun onReceivedSslError(view: WebView, handler: android.webkit.SslErrorHandler, error: android.net.http.SslError) {
                handler.cancel()
                loginHandler.removeCallbacks(slowPage)
                note.text = "The page certificate could not be verified. Check the phone's date and time, then Start over."
            }
            override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
                rendererGone = true
                android.widget.Toast.makeText(activity, "The sign-in browser stopped. Reopen YouTube account to retry.", android.widget.Toast.LENGTH_LONG).show()
                dialog.dismiss()
                return true
            }
        }
        use.setOnClickListener {
            if (saving || closing) return@setOnClickListener
            if (Uri.parse(web.url ?: "").let { it.scheme != "https" || it.host != "music.youtube.com" }) {
                note.text = "Finish signing in, then return to music.youtube.com before using this account."
                return@setOnClickListener
            }
            saving = true
            use.isEnabled = false
            val currentAttempt = ++attempt
            val checkTimeout = Runnable {
                if (!closing && attempt == currentAttempt && saving) {
                    attempt++
                    saving = false; use.isEnabled = true
                    note.text = "The page did not answer the account check. Tap Return to YouTube Music and try Use account again, or Start over."
                }
            }
            loginHandler.postDelayed(checkTimeout, 10000)
            // The expression also checks its own origin to prevent navigation races.
            web.evaluateJavascript("""(() => {
                if (location.origin !== 'https://music.youtube.com' || !window.ytcfg) return null;
                return {loggedIn: ytcfg.get('LOGGED_IN') === true,
                    version: ytcfg.get('INNERTUBE_CLIENT_VERSION'),
                    visitor: ytcfg.get('VISITOR_DATA'),
                    authUser: String(ytcfg.get('SESSION_INDEX') || '0')};
            })()""".trimIndent()) { raw ->
                if (closing || currentAttempt != attempt) return@evaluateJavascript
                loginHandler.removeCallbacks(checkTimeout)
                try {
                    val config = JSONTokener(raw).nextValue() as? JSONObject
                    val cookie = cookies.getCookie(ORIGIN) ?: ""
                    if (config == null || !config.optBoolean("loggedIn") || config.optString("version").isBlank() ||
                        !YoutubeSignInPolicy.hasSession(cookie)) {
                        note.text = "No signed-in YouTube Music session detected. Complete Google's sign-in first. If Google blocks this browser, this method is unavailable."
                        saving = false; use.isEnabled = true
                        return@evaluateJavascript
                    }
                    config.put("cookie", cookie).put("userAgent", web.settings.userAgentString)
                    worker.execute {
                        try {
                            // A cancelled or destroyed dialog discards this pending save.
                            save(activity, config)
                            main.post {
                                if (closing) worker.execute { sessionFile(activity).delete() }
                                else { saved = true; dialog.dismiss() }
                            }
                        } catch (_: Exception) {
                            main.post {
                                note.text = "Could not securely save the session."
                                saving = false; use.isEnabled = true
                            }
                        }
                    }
                } catch (_: Exception) {
                    note.text = "Could not read a signed-in YouTube Music session."
                    saving = false; use.isEnabled = true
                }
            }
        }
        val restart = Button(activity).apply {
            text = "Start over"
            setOnClickListener {
                if (!saving) {
                    attempt++
                    loginHandler.removeCallbacksAndMessages(null)
                    web.stopLoading(); web.clearCache(true); web.clearHistory()
                    WebStorage.getInstance().deleteAllData()
                    note.text = "Starting a fresh Google sign-in."
                    cookies.removeAllCookies { if (!closing) web.loadUrl(ORIGIN) }
                }
            }
        }
        val home = Button(activity).apply { text = "Return to YouTube Music"; setOnClickListener { if (!saving) web.loadUrl(ORIGIN) } }
        val cancel = Button(activity).apply { text = "Cancel"; setOnClickListener { dialog.dismiss() } }
        layout.addView(note); layout.addView(address)
        layout.addView(web, LinearLayout.LayoutParams(-1, 0, 1f))
        val buttons = LinearLayout(activity)
        buttons.addView(use); buttons.addView(cancel)
        layout.addView(home); layout.addView(restart); layout.addView(buttons)
        dialog.setContentView(layout)
        dialog.setOnKeyListener { _, code, event ->
            if (code == android.view.KeyEvent.KEYCODE_BACK) {
                if (event.action == android.view.KeyEvent.ACTION_UP) dialog.dismiss()
                true
            } else false
        }
        dialog.setOnDismissListener {
            activeDialog = null
            closing = true
            attempt++
            loginHandler.removeCallbacksAndMessages(null)
            if (!rendererGone) { web.stopLoading(); web.loadUrl("about:blank"); web.clearHistory(); web.clearCache(true) }
            web.destroy()
            WebStorage.getInstance().deleteAllData()
            cookies.removeAllCookies {
                cookies.flush()
                loginOpen = false
                result.success(saved)
            }
        }
        activeDialog = dialog
        dialog.show()
        dialog.window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        // Always offer a fresh account selection; do not reuse other app sessions.
        cookies.removeAllCookies { if (!closing) web.loadUrl("https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F") }
    }

    private fun resolve(context: Context, id: String): String? {
        if (!Regex("^[A-Za-z0-9_-]{11}$").matches(id)) throw Failure("YT_ACCOUNT_UNAVAILABLE")
        val session = read(context) ?: return null
        val cookie = session.getString("cookie")
        val values = cookie.split(';').mapNotNull {
            val pair = it.trim().split('=', limit = 2)
            if (pair.size == 2) pair[0] to pair[1] else null
        }.toMap()
        val sapisid = values["SAPISID"] ?: values["__Secure-3PAPISID"] ?: values["__Secure-1PAPISID"] ?: throw Failure("YT_SESSION_EXPIRED")
        val timestamp = System.currentTimeMillis() / 1000
        val hash = MessageDigest.getInstance("SHA-1").digest("$timestamp $sapisid $ORIGIN".toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val connection = URL("$ORIGIN/youtubei/v1/player?prettyPrint=false").openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 10000; connection.readTimeout = 15000
            connection.requestMethod = "POST"; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Cookie", cookie)
            connection.setRequestProperty("Authorization", "SAPISIDHASH ${timestamp}_$hash")
            connection.setRequestProperty("Origin", ORIGIN)
            connection.setRequestProperty("X-Origin", ORIGIN)
            connection.setRequestProperty("X-Goog-AuthUser", session.optString("authUser", "0"))
            connection.setRequestProperty("User-Agent", session.getString("userAgent"))
            val client = JSONObject().put("clientName", "WEB_REMIX").put("clientVersion", session.getString("version"))
                .put("hl", "en").put("visitorData", session.optString("visitor"))
            val body = JSONObject().put("context", JSONObject().put("client", client)).put("videoId", id)
            connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            YoutubePlaybackPolicy.httpFailure(status)?.let { throw Failure(it) }
            val bytes = connection.inputStream.use { it.readBytesBounded(2 * 1024 * 1024) }
            val response = JSONObject(String(bytes, Charsets.UTF_8))
            val playability = response.optJSONObject("playabilityStatus")?.optString("status") ?: ""
            YoutubePlaybackPolicy.playabilityFailure(playability)?.let { throw Failure(it) }
            val streaming = response.optJSONObject("streamingData")
                ?: throw Failure("YT_SESSION_NO_AUDIO")
            fun formats(name: String): List<YoutubePlaybackPolicy.Format> {
                val array = streaming.optJSONArray(name) ?: return emptyList()
                return (0 until array.length()).mapNotNull { array.optJSONObject(it) }.map {
                    YoutubePlaybackPolicy.Format(
                        it.optString("url"), it.optString("mimeType"), it.optInt("bitrate"),
                        it.has("signatureCipher") || it.has("cipher"),
                    )
                }
            }
            val adaptive = formats("adaptiveFormats")
            val combined = formats("formats")
            // No signature/PO-token bypass: unsupported responses get a distinct error.
            return YoutubePlaybackPolicy.pick(adaptive, combined)
                ?: throw Failure(YoutubePlaybackPolicy.noAudioFailure(adaptive + combined))
        } catch (_: java.io.IOException) {
            // Native messages can include request details, so only a code leaves.
            throw Failure("YT_ACCOUNT_NETWORK")
        } finally { connection.disconnect() }
    }

    private fun java.io.InputStream.readBytesBounded(limit: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            if (out.size() + count > limit) throw Failure("YT_SESSION_REJECTED")
            out.write(buffer, 0, count)
        }
        return out.toByteArray()
    }
}
