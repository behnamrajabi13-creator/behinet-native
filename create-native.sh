#!/usr/bin/env bash
set -e

echo "==> Creating app.config.ts (replaces app.json)"
cat > app.config.ts << 'EOF'
import type { ExpoConfig } from "expo/config";

const config: ExpoConfig = {
  name: "BehiNet VPN",
  slug: "behinet-native",
  version: "1.0.0",
  orientation: "portrait",
  scheme: "behinet",
  userInterfaceStyle: "light",
  android: {
    package: "com.behinet.vpn",
    adaptiveIcon: {
      backgroundColor: "#102D2B",
    },
    permissions: [
      "android.permission.INTERNET",
      "android.permission.FOREGROUND_SERVICE",
      "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
      "android.permission.POST_NOTIFICATIONS",
    ],
  },
  ios: {
    supportsTablet: false,
    bundleIdentifier: "com.behinet.vpn",
  },
  plugins: [
    "expo-router",
    "expo-secure-store",
    "expo-status-bar",
    "./plugins/with-behinet-vpn",
  ],
  experiments: { typedRoutes: false },
};

export default config;
EOF

echo "==> Removing app.json (replaced by app.config.ts)"
rm -f app.json

echo "==> Creating plugins/with-behinet-vpn.js"
cat > plugins/with-behinet-vpn.js << 'EOF'
const { withAndroidManifest, withAppBuildGradle, withDangerousMod, withMainApplication } = require("@expo/config-plugins");
const fs = require("fs");
const path = require("path");

const SERVICE_NAME = ".vpn.BehiNetVpnService";

function withBehiNetVpn(config) {
  config = withAndroidManifest(config, (config) => {
    const manifest = config.modResults.manifest;
    manifest["uses-permission"] = manifest["uses-permission"] || [];
    for (const name of [
      "android.permission.INTERNET",
      "android.permission.FOREGROUND_SERVICE",
      "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
      "android.permission.POST_NOTIFICATIONS",
    ]) {
      if (!manifest["uses-permission"].some((p) => p.$?.["android:name"] === name)) {
        manifest["uses-permission"].push({ $: { "android:name": name } });
      }
    }
    const application = manifest.application?.[0];
    if (!application) throw new Error("BehiNet VPN plugin: Android application node not found");
    application.service = application.service || [];
    if (!application.service.some((s) => s.$?.["android:name"] === SERVICE_NAME)) {
      application.service.push({
        $: {
          "android:name": SERVICE_NAME,
          "android:permission": "android.permission.BIND_VPN_SERVICE",
          "android:exported": "false",
          "android:foregroundServiceType": "specialUse",
        },
        "intent-filter": [{ action: [{ $: { "android:name": "android.net.VpnService" } }] }],
      });
    }
    return config;
  });

  config = withAppBuildGradle(config, (config) => {
    let c = config.modResults.contents;
    if (!c.includes('implementation files("libs/libbox.aar")')) {
      c += `\n// BehiNet VPN native engine\ndependencies {\n    implementation files("libs/libbox.aar")\n    implementation "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"\n    implementation "androidx.core:core-ktx:1.12.0"\n}\n`;
    }
    if (!c.includes('abiFilters "arm64-v8a"')) {
      c += `\nandroid {\n    defaultConfig {\n        ndk { abiFilters "arm64-v8a", "armeabi-v7a", "x86_64" }\n    }\n}\n`;
    }
    config.modResults.contents = c;
    return config;
  });

  config = withMainApplication(config, (config) => {
    const pkg = config.android?.package;
    if (!pkg) throw new Error("android.package required");
    let c = config.modResults.contents;
    const importLine = `import ${pkg}.vpn.BehiNetVpnPackage`;
    if (!c.includes("BehiNetVpnPackage")) {
      const pkgMatch = c.match(/^package\s+[^\r\n]+\r?\n/m);
      if (pkgMatch) c = c.replace(pkgMatch[0], `${pkgMatch[0]}${importLine}\n`);
      else c = `${importLine}\n${c}`;
      const marker = "PackageList(this).packages.apply {";
      if (c.includes(marker)) {
        c = c.replace(marker, `${marker}\n            add(BehiNetVpnPackage())`);
      } else {
        throw new Error("MainApplication getPackages template not supported");
      }
    }
    config.modResults.contents = c;
    return config;
  });

  return withDangerousMod(config, ["android", async (config) => {
    const pkg = config.android?.package;
    if (!pkg) throw new Error("android.package required");

    const aarSrc = path.join(config.modRequest.projectRoot, "native/android/libs/libbox.aar");
    if (!fs.existsSync(aarSrc)) throw new Error("native/android/libs/libbox.aar missing. Run scripts/build-singbox-android.sh first.");
    const aarDir = path.join(config.modRequest.platformProjectRoot, "app/libs");
    fs.mkdirSync(aarDir, { recursive: true });
    fs.copyFileSync(aarSrc, path.join(aarDir, "libbox.aar"));

    const ktSrc = path.join(config.modRequest.projectRoot, "native/android/src");
    if (!fs.existsSync(ktSrc)) throw new Error("native/android/src missing. Add the Kotlin engine sources first.");
    const ktDst = path.join(config.modRequest.platformProjectRoot, "app/src/main/java", ...pkg.split("."), "vpn");
    fs.mkdirSync(ktDst, { recursive: true });
    for (const f of fs.readdirSync(ktSrc)) {
      if (!f.endsWith(".kt")) continue;
      const txt = fs.readFileSync(path.join(ktSrc, f), "utf8").replaceAll("__BEHINET_PACKAGE__", pkg);
      fs.writeFileSync(path.join(ktDst, f), txt);
    }
    return config;
  }]);
}

module.exports = withBehiNetVpn;
EOF

echo "==> Creating native/android/src/BehiNetVpnEngineModule.kt"
cat > native/android/src/BehiNetVpnEngineModule.kt << 'EOF'
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
EOF

echo "==> Creating native/android/src/BehiNetVpnPackage.kt"
cat > native/android/src/BehiNetVpnPackage.kt << 'EOF'
package __BEHINET_PACKAGE__.vpn

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class BehiNetVpnPackage : ReactPackage {
    override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> =
        listOf(BehiNetVpnEngineModule(context))
    override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}
EOF

echo "==> Creating native/android/src/BehiNetVpnService.kt"
cat > native/android/src/BehiNetVpnService.kt << 'EOF'
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
EOF

echo "==> Creating scripts/build-singbox-android.sh"
cat > scripts/build-singbox-android.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SINGBOX_DIR="${SINGBOX_DIR:-$ROOT_DIR/.native/sing-box}"
SINGBOX_REF="${SINGBOX_REF:?Set SINGBOX_REF to an immutable tag, e.g. v1.11.15}"
OUTPUT_DIR="$ROOT_DIR/native/android/libs"

for cmd in git go java make; do command -v $cmd >/dev/null || { echo "$cmd required" >&2; exit 1; }; done
java -version 2>&1 | grep -q 'version "17' || { echo "JDK 17 required" >&2; exit 1; }

if [[ ! -d "$SINGBOX_DIR/.git" ]]; then
  mkdir -p "$(dirname "$SINGBOX_DIR")"
  git clone --depth 1 --branch "$SINGBOX_REF" https://github.com/SagerNet/sing-box.git "$SINGBOX_DIR"
else
  git -C "$SINGBOX_DIR" fetch --depth 1 origin "$SINGBOX_REF"
  git -C "$SINGBOX_DIR" checkout -q FETCH_HEAD
fi
cd "$SINGBOX_DIR"
go mod download
make lib_install
go run ./cmd/internal/build_libbox -target android
mkdir -p "$OUTPUT_DIR"
cp -f libbox.aar "$OUTPUT_DIR/libbox.aar"
cp -f libbox-legacy.aar "$OUTPUT_DIR/libbox-legacy.aar"
echo "Built: $OUTPUT_DIR/libbox.aar"
EOF

echo "==> Creating scripts/setup-android-env-ubuntu.sh"
cat > scripts/setup-android-env-ubuntu.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-27.2.12479018}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-35}"
GO_VERSION="${GO_VERSION:-1.23.1}"

sudo apt-get update
sudo apt-get install -y curl unzip git make build-essential pkg-config ca-certificates openjdk-17-jdk
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in amd64) GO_ARCH=amd64 ;; arm64) GO_ARCH=arm64 ;; *) echo "arch?"; exit 1 ;; esac
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tgz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf /tmp/go.tgz

mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
if [[ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o /tmp/clt.zip
  rm -rf /tmp/clt "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mkdir -p /tmp/clt && unzip -q /tmp/clt.zip -d /tmp/clt
  mv /tmp/clt/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
fi

export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-$(dpkg --print-architecture)"
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="/usr/local/go/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "platforms;android-${ANDROID_PLATFORM}" "build-tools;35.0.0" "ndk;${ANDROID_NDK_VERSION}"
yes | sdkmanager --licenses >/dev/null || true
echo "Done. Add to ~/.bashrc: export JAVA_HOME=$JAVA_HOME; export ANDROID_HOME=$ANDROID_HOME; export PATH=$PATH"
EOF

echo "==> Creating scripts/vendor-singbox-wrappers.sh"
cat > scripts/vendor-singbox-wrappers.sh << 'EOF'
#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-}"
[[ -z "$REF" ]] && { echo "Usage: $0 <tag>"; exit 1; }
SRC="$ROOT_DIR/.native/sing-box-for-android"
DST="$ROOT_DIR/native/android/src"
PROBE="/tmp/sfa-probe-$REF"

rm -rf "$PROBE"
echo "Cloning $REF..."
if ! git clone --depth 1 --branch "$REF" https://github.com/SagerNet/sing-box-for-android.git "$PROBE"; then
  echo "Clone failed for $REF" >&2; exit 1
fi

mkdir -p "$DST"
for f in VPNService.kt BoxService.kt PlatformInterfaceWrapper.kt; do
  src=$(find "$PROBE/app/src/main/java" -name "$f" 2>/dev/null | head -1)
  if [[ -n "$src" ]]; then
    sed 's/^package .*/package __BEHINET_PACKAGE__.vpn/' "$src" > "$DST/$f"
    echo "Copied: $f"
  else
    echo "MISSING: $f (check $REF structure)"
  fi
done
EOF

chmod +x scripts/*.sh
echo ""
echo "✅ Native files, plugin, and scripts created!"
