package com.example.frontend

import android.security.keystore.KeyGenParameterSpec
import android.os.SystemClock
import android.provider.Settings
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.io.File
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "cunismart/device_credentials"
    private val keyAlias = "cunismart_device_credential"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cunismart/session_clock")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                } else {
                    try {
                        val bootCount = Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT)
                        val installationFile = File(noBackupFilesDir, "session_installation_id")
                        if (!installationFile.exists()) {
                            installationFile.writeText(UUID.randomUUID().toString())
                        }
                        result.success(mapOf(
                            "bootCount" to bootCount,
                            "elapsedMilliseconds" to SystemClock.elapsedRealtime(),
                            "installationId" to UUID.fromString(installationFile.readText()).toString(),
                        ))
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "exportPublicKey" -> result.success(exportPublicKeyPem())
                        "sign" -> {
                            val nonce = call.argument<String>("nonce").orEmpty()
                            result.success(signNonce(nonce))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("keystore", e.message, null)
                }
            }
    }

    private fun ensureKey() {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(keyAlias)) return
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            "AndroidKeyStore",
        )
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setKeySize(2048)
            .setUserAuthenticationRequired(false)
        try {
            builder.setInvalidatedByBiometricEnrollment(true)
        } catch (_: NoSuchMethodError) {
            // Older Android; skip invalidation flag.
        }
        generator.initialize(builder.build())
        generator.generateKeyPair()
    }

    private fun exportPublicKeyPem(): String {
        ensureKey()
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val cert = keyStore.getCertificate(keyAlias)
        val encoded = Base64.encodeToString(cert.publicKey.encoded, Base64.NO_WRAP)
        val chunks = encoded.chunked(64).joinToString("\n")
        return "-----BEGIN PUBLIC KEY-----\n$chunks\n-----END PUBLIC KEY-----"
    }

    private fun signNonce(nonce: String): String {
        ensureKey()
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val entry = keyStore.getEntry(keyAlias, null) as KeyStore.PrivateKeyEntry
        val signature = Signature.getInstance("SHA256withRSA")
        signature.initSign(entry.privateKey)
        signature.update(nonce.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(signature.sign(), Base64.NO_WRAP)
    }
}
