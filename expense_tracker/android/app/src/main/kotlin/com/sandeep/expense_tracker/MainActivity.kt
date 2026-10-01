package com.sandeep.expense_tracker

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    /**
     * Registers `expense_tracker/signing` so the Google setup screen can show
     * the SHA-1 fingerprint the Cloud Console asks for, without the user
     * running keytool. Never throws: failures answer `null` in Dart.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_GET_SHA1 -> result.success(signingCertificateSha1())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Colon-separated uppercase SHA-1 of the certificate that signed this
     * install, for example
     * `FA:A5:B3:31:B7:CA:FD:6E:FD:1D:71:96:20:B8:9C:DB:32:4F:FE:A1`.
     *
     * Returns `null` instead of throwing on any failure so the Dart caller can
     * fall back to a documented placeholder.
     */
    private fun signingCertificateSha1(): String? {
        return try {
            val signature = signingCertificate() ?: return null
            val digest = MessageDigest.getInstance("SHA-1").digest(signature.toByteArray())
            digest.joinToString(separator = ":") { byte ->
                "%02X".format(byte.toInt() and 0xFF)
            }
        } catch (error: Exception) {
            null
        }
    }

    /**
     * The signing certificate itself. `GET_SIGNING_CERTIFICATES` and
     * `apkContentsSigners` are the modern accessors (API 28+); older devices
     * fall back to the deprecated `GET_SIGNATURES`, since minSdk is below 28.
     */
    @Suppress("DEPRECATION")
    private fun signingCertificate(): Signature? {
        val packageManager = packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            info.signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            info.signatures?.firstOrNull()
        }
    }

    private companion object {
        const val CHANNEL_NAME = "expense_tracker/signing"
        const val METHOD_GET_SHA1 = "getSha1"
    }
}
