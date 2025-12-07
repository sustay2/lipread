package my.edu.tarumt.flutter_app

import android.content.pm.PackageManager
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

        // Check if biometrics can work generally (Strong or Weak/Class 2 for Face)
        val canAuthenticate = biometricManager.canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK)
        
        if (canAuthenticate == BiometricManager.BIOMETRIC_SUCCESS) {
            // Hardware is present and enrolled.
            availableFeatures.add("strong")
            availableFeatures.add("weak")
            
            // OPTIMISTIC FALLBACK:
            // Custom ROMs (like HyperOS) often don't declare PackageManager.FEATURE_FACE correctly.
            // If BiometricManager says SUCCESS, we add both 'fingerprint' and 'face' to the list.
            // This enables the UI toggles. If the specific hardware is actually missing, 
            // the authentication call itself will handle the failure/fallback gracefully.
            availableFeatures.add("fingerprint")
            availableFeatures.add("face")
        }

        return availableFeatures
    }
}