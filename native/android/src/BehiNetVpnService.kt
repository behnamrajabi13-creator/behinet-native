package __BEHINET_PACKAGE__.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.TunOptions
import java.util.concurrent.Executors

class BehiNetVpnService : VpnService(), PlatformInterface {
    private var tunFd: ParcelFileDescriptor? = null
    private var server: CommandServer? = null

    override fun onCreate() { super.onCreate(); createChannel() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val cfg = intent?.getStringExtra(EXTRA_CONFIG)
        if (cfg.isNullOrBlank()) { stopSelf(); return START_NOT_STICKY }
        startForeground(NOTIF_ID, buildNotif("BehiNet VPN"))
        try {
            val s = CommandServer(Executors.newSingleThreadExecutor(), this)
            server = s
            s.start()
            Libbox.startOrReloadService(cfg, s)
        } catch (e: Throwable) { stopSelf() }
        return START_STICKY
    }

    override fun openTun(options: TunOptions): Int {
        val b = Builder().setSession("BehiNet VPN").setMtu(options.mtu)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("2606:4700:4700::1111")
        tunFd?.close()
        tunFd = b.establish() ?: error("VPN_ESTABLISH_FAILED")
        return tunFd!!.fd
    }

    override fun onDestroy() {
        try { Libbox.closeService() } catch (_: Throwable) {}
        try { server?.close() } catch (_: Throwable) {}
        server = null
        tunFd?.close(); tunFd = null
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val m = getSystemService(NotificationManager::class.java)
            m.createNotificationChannel(NotificationChannel(CH_ID, "BehiNet VPN", NotificationManager.IMPORTANCE_LOW))
        }
    }

    private fun buildNotif(text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE) }
        return NotificationCompat.Builder(this, CH_ID)
            .setContentTitle("BehiNet VPN").setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_vpn_ic)
            .setOngoing(true).setContentIntent(pi).build()
    }

    companion object {
        const val EXTRA_CONFIG = "behinet.config"
        const val CH_ID = "behinet-vpn"
        const val NOTIF_ID = 4001
    }
}
