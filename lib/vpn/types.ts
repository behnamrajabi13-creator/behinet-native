export type Protocol =
  | "vless" | "vmess" | "trojan" | "shadowsocks"
  | "hysteria2" | "tuic" | "socks" | "http" | "wireguard";

export type PingStatus = "idle" | "checking" | "available" | "unavailable";

export type VpnConfig = {
  id: string;
  name: string;
  protocol: Protocol;
  raw: string;
  server?: string;
  port?: string;
  source: "manual" | "subscription" | "wireguard";
  subscriptionId?: string;
  createdAt: number;
  updatedAt: number;
  pingStatus: PingStatus;
  lastPingMs?: number;
  pingMessage?: string;
};

export type Subscription = {
  id: string;
  url: string;
  name: string;
  createdAt: number;
  updatedAt?: number;
  configCount: number;
  lastError?: string;
};

export type VpnPreferences = { dns4: string; dns6: string; mtu: number };

export type ConnectionState = {
  status: "disconnected" | "connecting" | "connected" | "needs-native";
  configId?: string;
  startedAt?: number;
  message?: string;
};

export type VpnState = {
  configs: VpnConfig[];
  subscriptions: Subscription[];
  selectedConfigId?: string;
  connection: ConnectionState;
  preferences: VpnPreferences;
};

export const DEFAULT_PREFERENCES: VpnPreferences = {
  dns4: "1.1.1.1",
  dns6: "2606:4700:4700::1111",
  mtu: 1280,
};

export const INITIAL_VPN_STATE: VpnState = {
  configs: [],
  subscriptions: [],
  connection: { status: "disconnected" },
  preferences: DEFAULT_PREFERENCES,
};

export type ParsedConfigDraft = {
  name: string;
  protocol: Protocol;
  raw: string;
  server?: string;
  port?: string;
};
