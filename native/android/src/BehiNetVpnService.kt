package __BEHINET_PACKAGE__.vpn

import android.net.VpnService
import android.content.Intent
import android.os.ParcelFileDescriptor

class BehiNetVpnService : VpnService() {
    private var tunFd: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        tunFd?.close()
        tunFd = null
        super.onDestroy()
    }
}
