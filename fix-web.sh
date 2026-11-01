#!/usr/bin/env bash
set -e

echo "==> Fixing @/ alias in app/servers.tsx"
sed -i 's|from "@/lib/vpn/provider"|from "../lib/vpn/provider"|g' app/servers.tsx
sed -i 's|from "@/lib/vpn/provider"|from "../lib/vpn/provider"|g' app/add.tsx
sed -i 's|from "@/lib/vpn/provider"|from "../lib/vpn/provider"|g' app/settings.tsx

echo "==> Making NativeVpnEngine web-safe"
cat > lib/vpn/native-engine.ts << 'EOF'
import { NativeModules, Platform } from "react-native";
import { DEFAULT_PREFERENCES, type VpnConfig, type VpnPreferences } from "./types";
import { buildSingBoxConfig } from "./singbox-config";

export class NativeCoreUnavailableError extends Error {
  constructor() {
    super("اتصال انجام نشد: این build هستهٔ VPN ندارد. باید APK native با libbox.aar ساخته شود.");
    this.name = "NativeCoreUnavailableError";
  }
}

type NativeVpnBridge = {
  start: (payload: string) => Promise<void>;
  stop: () => Promise<void>;
  ping: (payload: string) => Promise<number>;
  version?: () => Promise<string>;
};

const getBridge = (): NativeVpnBridge | undefined => {
  if (Platform.OS === "web") return undefined;
  const mod = (NativeModules as any)?.BehiNetVpnEngine as NativeVpnBridge | undefined;
  return mod;
};

export const NativeVpnEngine = {
  available: () => Boolean(getBridge()?.start && getBridge()?.stop && getBridge()?.ping),
  async connect(config: VpnConfig, preferences: VpnPreferences) {
    const bridge = getBridge();
    if (!bridge?.start) throw new NativeCoreUnavailableError();
    await bridge.start(JSON.stringify(buildSingBoxConfig(config, preferences)));
  },
  async disconnect() {
    const bridge = getBridge();
    if (!bridge?.stop) throw new NativeCoreUnavailableError();
    await bridge.stop();
  },
  async ping(config: VpnConfig) {
    const bridge = getBridge();
    if (!bridge?.ping) throw new NativeCoreUnavailableError();
    const latency = await bridge.ping(JSON.stringify(buildSingBoxConfig(config, DEFAULT_PREFERENCES)));
    return { latencyMs: latency };
  },
};
EOF

echo "==> Done"
echo ""
echo "Now restart:"
echo "  Ctrl+C in the metro terminal"
echo "  npx expo start --clear"
echo "  press 'w'"
