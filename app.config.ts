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
