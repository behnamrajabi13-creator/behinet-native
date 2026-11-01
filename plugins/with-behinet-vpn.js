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
