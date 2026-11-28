package com.rchrdariza.retropod

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection

/** Runtime is process-owned; channel operations never execute on the UI thread. */
object MornyeExtensions {
    private class ProviderFailure(val code: String) : Exception()
    interface Bridge : Library {
        fun rp_call(request: String): Pointer
        fun rp_free(value: Pointer)
    }
    private val bridge by lazy { Native.load("retropod_extensions", Bridge::class.java) }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var initialized = false
    private lateinit var root: File
    private val packages = mutableMapOf<String, File>()

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "retropod/mornye").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    initialize(app)
                    val request = JSONObject(call.arguments as? String ?: "{}")
                    val value = handle(app, call.method, request)
                    main.post { result.success(JSONObject().put("value", value ?: JSONObject.NULL).toString()) }
                } catch (e: ProviderFailure) {
                    main.post { result.error(e.code, null, null) }
                } catch (e: Exception) {
                    // Native errors may contain provider credentials/URLs: never forward them.
                    main.post { result.error("extension_failed", "Extension operation failed. Check its settings, compatibility and network connection.", null) }
                } catch (e: LinkageError) {
                    main.post { result.error("runtime_missing", "This build does not include the Mornye runtime.", null) }
                }
            }
        }
    }
    private fun native(request: JSONObject): Any? {
        val pointer = bridge.rp_call(request.toString())
        val response = try { JSONObject(pointer.getString(0, "UTF-8")) } finally { bridge.rp_free(pointer) }
        if (response.has("error")) throw ProviderFailure(response.optString("error", "EXT_FAILED"))
        return response.opt("value").takeUnless { it == JSONObject.NULL }
    }
    private fun initialize(context: Context) {
        if (initialized) return
        root = File(context.noBackupFilesDir, "mornye").apply { mkdirs() }
        // Audio is transient; do not retain prepared tracks between process launches.
        File(root, "audio").deleteRecursively()
        native(JSONObject().put("op", "init").put("root", root.path).put("key", masterKey()))
        initialized = true
        Executors.newSingleThreadExecutor().execute {
            while (true) {
                try {
                    val pending = native(JSONObject().put("op", "ffmpegPoll")) as JSONArray
                    for (i in 0 until pending.length()) {
                        val command = pending.getJSONObject(i)
                        val args = command.getJSONArray("arguments")
                        // Arguments come from the runtime's path/operation validator, never a shell.
                        val session = FFmpegKit.executeWithArguments(Array(args.length()) { args.getString(it) })
                        native(JSONObject().put("op", "ffmpegComplete")
                            .put("id", command.getString("command_id"))
                            .put("success", ReturnCode.isSuccess(session.returnCode)))
                    }
                } catch (_: Exception) { Thread.sleep(1000) }
            }
        }
    }
    private fun masterKey(): String {
        val alias = "retropod-mornye-storage"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = if (store.containsAlias(alias)) store.getKey(alias, null) as SecretKey else {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
        }
        val file = File(root, "storage-key")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        if (file.exists()) {
            val bytes = file.readBytes()
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0,12)))
            return String(cipher.doFinal(bytes.copyOfRange(12,bytes.size)), Charsets.UTF_8)
        }
        val value = Base64.encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }, Base64.NO_WRAP)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        file.writeBytes(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)))
        return value
    }
    private fun handle(context: Context, method: String, request: JSONObject): Any? {
        when (method) {
            "prepare" -> {
                // Only this registry's raw package URLs are accepted. Redirects are disabled.
                val url = URL(request.getString("url"))
                require(url.protocol == "https" && url.host == "raw.githubusercontent.com" && url.port == -1 && url.userInfo == null)
                require(url.path.startsWith("/mornyeapp/Mornye-Extension/main/extensions/") && url.path.endsWith(".sflx") && url.query == null)
                val checksum = request.getString("sha256")
                require(checksum.matches(Regex("[0-9a-f]{64}")))
                val file = File(context.cacheDir, "${UUID.randomUUID()}.sflx")
                try {
                    val conn = url.openConnection() as HttpsURLConnection
                    conn.instanceFollowRedirects = false
                    conn.connectTimeout = 15000; conn.readTimeout = 15000
                    try {
                        require(conn.responseCode == 200)
                        conn.inputStream.use { input -> file.outputStream().use { output ->
                            val buffer = ByteArray(65536); var total = 0
                            while (true) { val count = input.read(buffer); if (count < 0) break
                                total += count; require(total <= 16 * 1024 * 1024); output.write(buffer,0,count) }
                        } }
                    } finally { conn.disconnect() }
                    val digest = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
                    require(digest == checksum)
                    val manifest = native(JSONObject().put("op","inspect").put("path",file.path)) as JSONObject
                    require(manifest.getString("name") == request.getString("id"))
                    require(manifest.getString("version") == request.getString("version"))
                    val token = UUID.randomUUID().toString()
                    // At most one pending package, and no abandoned copies.
                    packages.values.forEach { it.delete() }; packages.clear(); packages[token] = file
                    return JSONObject().put("token",token).put("manifest",manifest)
                } catch (e: Exception) { file.delete(); throw e }
            }
            "install", "discard" -> {
                val file = packages.remove(request.getString("token")) ?: error("Package expired")
                return try { if (method == "install") native(JSONObject().put("op","install").put("path",file.path)) else null } finally { file.delete() }
            }
            "download" -> {
                val audio = File(root,"audio")
                // Bound temporary cache growth without deleting the most recent playing file.
                audio.listFiles()?.filter { it.isFile }?.sortedByDescending { it.lastModified() }?.drop(20)?.forEach { it.delete() }
                val output = File(audio, "${UUID.randomUUID()}.m4a")
                request.put("path",output.path).put("itemId",UUID.randomUUID().toString()).put("op","download")
                val response = native(request) as JSONObject
                if (!response.optBoolean("success")) throw ProviderFailure("EXT_FAILED")
                if (response.has("decryption") || response.optString("decryption_key").isNotEmpty()) throw ProviderFailure("EXT_FINALIZATION")
                val reported = response.optString("file_path").ifEmpty { response.optString("output_path").ifEmpty { output.path } }
                val file = File(reported).canonicalFile
                if (!file.path.startsWith(File(root,"audio").canonicalPath + File.separator) || !file.isFile || file.length() == 0L) throw ProviderFailure("EXT_NO_FILE")
                return file.toURI().toString()
            }
            "installed", "remove", "enable", "settings", "saveSettings", "search" -> {
                request.put("op",method)
                return native(request)
            }
            else -> error("Unsupported operation")
        }
    }
}
