package com.rchrdariza.retropod

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Private endpoint URLs may contain account tokens; never log them. */
object AddonSettings {
    private const val KEY = "retropod.http.addon.v1"
    private val worker = Executors.newSingleThreadExecutor()
    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "retropod/http_addon").setMethodCallHandler { call, result ->
            worker.execute {
                try {
                    val file = AtomicFile(File(app.noBackupFilesDir, "http-addon.bin"))
                    val value: String? = when (call.method) {
                        "get" -> if (!file.baseFile.exists()) null else {
                            val bytes = file.readFully()
                            require(bytes.size in 29..32768)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                            String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
                        }
                        "remove" -> { file.delete(); null }
                        "set" -> {
                            val url = call.argument<String>("url") ?: error("Missing URL")
                            require(url.length <= 8192)
                            val data = JSONObject().put("id", UUID.randomUUID().toString()).put("url", url)
                                .put("name", (call.argument<String>("name") ?: "Custom add-on").take(100))
                                .put("settings", JSONObject(call.argument<Map<String, String>>("settings") ?: emptyMap<String, String>())).toString()
                            require(data.toByteArray(Charsets.UTF_8).size <= 32000)
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            val out = file.startWrite()
                            try { out.write(cipher.iv + cipher.doFinal(data.toByteArray(Charsets.UTF_8))); file.finishWrite(out) }
                            catch (e: Exception) { file.failWrite(out); throw e }
                            data
                        }
                        else -> error("Unknown operation")
                    }
                    Handler(Looper.getMainLooper()).post { result.success(value) }
                } catch (_: Exception) {
                    Handler(Looper.getMainLooper()).post { result.error("ADDON_STORAGE", null, null) }
                }
            }
        }
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
}
