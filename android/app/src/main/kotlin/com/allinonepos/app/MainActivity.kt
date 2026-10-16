package com.allinonepos.app

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Facts for lib/core/integrity/app_integrity.dart, which decides
        // whether this APK is one we signed. Kept here, not in a plugin, so a
        // repackager has one more place to find and patch.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.allinonepos.app/integrity")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "facts" -> try {
                        result.success(
                            mapOf(
                                "signers" to signingCertSha256(),
                                "debuggable" to
                                    ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("integrity_unavailable", e.javaClass.simpleName, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Uppercase hex SHA-256 of every certificate currently signing this APK. */
    private fun signingCertSha256(): List<String> {
        val certs: Array<android.content.pm.Signature> =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = packageManager
                    .getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo ?: return emptyList()
                if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
                    ?: return emptyList()
            }
        val sha = MessageDigest.getInstance("SHA-256")
        return certs.map { sig ->
            sha.digest(sig.toByteArray()).joinToString("") { "%02X".format(it) }
        }
    }
}
