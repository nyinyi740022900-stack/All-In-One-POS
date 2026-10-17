package com.allinonepos.app

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    // Warmed-up Play Integrity provider, reused across requests (Google's
    // recommended pattern for standard requests).
    private var integrityProvider: StandardIntegrityTokenProvider? = null
    private var integrityProject: Long = 0

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
                    "integrityToken" -> {
                        val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
                        val hash = call.argument<String>("requestHash")
                        if (project == null || hash.isNullOrEmpty()) {
                            result.error("bad_arguments", null, null)
                        } else {
                            integrityToken(project, hash, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** A Play Integrity token bound to [hash]; errors come back as
     *  `PI_<code>` (StandardIntegrityErrorCode) so the server can log why. */
    private fun integrityToken(project: Long, hash: String, result: MethodChannel.Result) {
        fun request(provider: StandardIntegrityTokenProvider) {
            provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                .addOnSuccessListener { result.success(it.token()) }
                .addOnFailureListener { e ->
                    integrityProvider = null
                    result.error(integrityErrorCode(e), e.message, null)
                }
        }
        val cached = integrityProvider
        if (cached != null && integrityProject == project) {
            request(cached)
            return
        }
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build(),
            )
            .addOnSuccessListener { provider ->
                integrityProvider = provider
                integrityProject = project
                request(provider)
            }
            .addOnFailureListener { e -> result.error(integrityErrorCode(e), e.message, null) }
    }

    private fun integrityErrorCode(e: Exception): String =
        if (e is StandardIntegrityException) "PI_${e.errorCode}" else e.javaClass.simpleName

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
