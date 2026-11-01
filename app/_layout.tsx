import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { VpnProvider } from "../lib/vpn";

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <VpnProvider>
        <StatusBar style="light" />
        <Stack
          screenOptions={{
            headerShown: false,
            contentStyle: { backgroundColor: "#102D2B" },
          }}
        />
      </VpnProvider>
    </SafeAreaProvider>
  );
}
