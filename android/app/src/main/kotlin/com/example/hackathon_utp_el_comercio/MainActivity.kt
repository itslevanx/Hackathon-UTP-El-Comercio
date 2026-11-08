package com.example.hackathon_utp_el_comercio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pe.vecinos.app/map_identity")
            .setMethodCallHandler { call, result ->
                if (call.method != "headers") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    @Suppress("DEPRECATION")
                    val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                            .signingInfo?.apkContentsSigners
                    } else {
                        packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
                    }
                    val signature = signatures?.singleOrNull()
                    if (signature == null) {
                        result.error("missing_signature", "Firma no disponible", null)
                    } else {
                        val sha1 = MessageDigest.getInstance("SHA-1").digest(signature.toByteArray())
                            .joinToString("") { "%02X".format(it.toInt() and 0xff) }
                        result.success(mapOf("X-Android-Package" to packageName, "X-Android-Cert" to sha1))
                    }
                } catch (_: Exception) {
                    result.error("missing_identity", "Identidad no disponible", null)
                }
            }
    }
}
