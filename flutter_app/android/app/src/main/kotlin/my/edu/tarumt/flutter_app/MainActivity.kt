package my.edu.tarumt.flutter_app

import android.os.Build
import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "local_auth_plugin"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAvailableBiometricTypes") {
                result.success(getAvailableBiometrics())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getAvailableBiometrics(): List<String> {
        val biometricManager = BiometricManager.from(this)
        val availableFeatures = mutableListOf<String>()

        // Check if biometrics can work generally
        val canAuthenticate = biometricManager.canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK)
        
        if (canAuthenticate == BiometricManager.BIOMETRIC_SUCCESS) {
            // Since Android 10+ (API 29), we can't easily distinguish face vs fingerprint 
            // programmatically without checking specific hardware features, 
            // but the BiometricManager confirms *something* is enrolled.
            
            // We return generic types that the Dart side maps to Enums.
            // BiometricService.dart maps "strong" -> BiometricType.strong
            availableFeatures.add("strong") 
            
            // If the device has a fingerprint sensor, we assume it's one of the active ones.
            if (packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_FINGERPRINT)) {
                availableFeatures.add("fingerprint")
            }

            // If the device has face features (generic check)
            if (packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_FACE)) {
                availableFeatures.add("face")
            }
        }

        return availableFeatures
    }
}