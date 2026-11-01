package __BEHINET_PACKAGE__.vpn

import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import io.nekohasekai.libbox.Libbox
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class BehiNetVpnEngineModule(
    private val context: ReactApplicationContext,
) : ReactContextBaseJavaModule(context) {

    override fun getName() = "BehiNetVpnEngine"

    private val scope = CoroutineScope(Dispatchers.IO)

    @ReactMethod
    fun prepare(promise: Promise) {
        try { promise.resolve(VpnService.prepare(context) == null) }
        catch (e: Throwable) { promise.reject("VPN_PREPARE_FAILED", e.message, e) }
    }

    @ReactMethod
    fun start(payload: String, promise: Promise) {
        try {
            if (VpnService.prepare(context) != null) {
                promise.reject("VPN_PERMISSION_REQUIRED", "VPN permission not granted")
                return
            }
            val intent = Intent(context, BehiNetVpnService::class.java)
                .putExtra(BehiNetVpnService.EXTRA_CONFIG, payload)
            ContextCompat.startForegroundService(context, intent)
            promise.resolve(null)
        } catch (e: Throwable) { promise.reject("VPN_START_FAILED", e.message, e) }
    }

    @ReactMethod
    fun stop(promise: Promise) {
        try {
            context.stopService(Intent(context, BehiNetVpnService::class.java))
            promise.resolve(null)
        } catch (e: Throwable) { promise.reject("VPN_STOP_FAILED", e.message, e) }
    }

    @ReactMethod
    fun version(promise: Promise) {
        try { promise.resolve(Libbox.version()) }
        catch (e: Throwable) { promise.reject("VPN_VERSION_FAILED", e.message, e) }
    }

    @ReactMethod
    fun ping(payload: String, promise: Promise) {
        scope.launch {
            try {
                val ms = Libbox.urlTest(payload)
                promise.resolve(ms)
            } catch (e: Throwable) { promise.reject("VPN_PING_FAILED", e.message, e) }
        }
    }
}
