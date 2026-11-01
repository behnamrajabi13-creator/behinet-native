#!/usr/bin/env bash
set -e

echo "==> Creating lib/vpn/types.ts"
cat > lib/vpn/types.ts << 'EOF'
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
EOF

echo "==> Creating lib/vpn/parser.ts"
cat > lib/vpn/parser.ts << 'EOF'
import type { ParsedConfigDraft, Protocol, VpnConfig } from "./types";

export const createId = (prefix: string) =>
  `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 9)}`;

const safeDecode = (value: string) => {
  try { return decodeURIComponent(value.replace(/\+/g, " ")); } catch { return value; }
};

const decodeBase64 = (value: string) => {
  try {
    const normalized = value.trim().replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
    const decoder = (globalThis as any).atob;
    if (!decoder) return "";
    const binary = decoder(padded);
    const textDecoder = (globalThis as any).TextDecoder;
    if (textDecoder) return new textDecoder().decode(Uint8Array.from(binary, (c: string) => c.charCodeAt(0)));
    const bytes = Array.from(binary, (c: any) => `%${c.charCodeAt(0).toString(16).padStart(2, "0")}`).join("");
    return decodeURIComponent(bytes);
  } catch { return ""; }
};

const extractEndpoint = (raw: string) => {
  const withoutScheme = raw.replace(/^[a-z]+:\/\//i, "");
  const afterCredentials = withoutScheme.includes("@")
    ? withoutScheme.slice(withoutScheme.lastIndexOf("@") + 1) : withoutScheme;
  const endpoint = afterCredentials.split(/[/?#]/)[0];
  const lastColon = endpoint.lastIndexOf(":");
  if (lastColon > 0) return { server: endpoint.slice(0, lastColon), port: endpoint.slice(lastColon + 1) };
  return { server: endpoint || undefined, port: undefined };
};

const remarkFromRaw = (raw: string, fallback: string) => {
  const hashIndex = raw.indexOf("#");
  if (hashIndex === -1) return fallback;
  const remark = safeDecode(raw.slice(hashIndex + 1)).trim();
  return remark || fallback;
};

const fromLink = (raw: string, protocol: Protocol): ParsedConfigDraft => {
  const { server, port } = extractEndpoint(raw);
  const fallback = server ? `${protocol.toUpperCase()} · ${server}` : protocol.toUpperCase();
  return { name: remarkFromRaw(raw, fallback), protocol, raw, server, port };
};

const parseVmess = (raw: string): ParsedConfigDraft => {
  const decoded = decodeBase64(raw.slice("vmess://".length));
  try {
    const payload = JSON.parse(decoded) as { ps?: string; add?: string; port?: string | number };
    return {
      name: payload.ps?.trim() || `VMess · ${payload.add || "subscription"}`,
      protocol: "vmess", raw,
      server: payload.add,
      port: payload.port ? String(payload.port) : undefined,
    };
  } catch { return fromLink(raw, "vmess"); }
};

export const parseWireGuard = (contents: string, filename?: string): ParsedConfigDraft | null => {
  if (!/\[Interface\]/i.test(contents) || !/\[Peer\]/i.test(contents)) return null;
  const endpoint = contents.match(/^\s*Endpoint\s*=\s*([^\s#;]+)/im)?.[1];
  const endpointParts = endpoint ? extractEndpoint(`wireguard://${endpoint}`) : {};
  const baseName = filename?.replace(/\.(conf|wg|txt)$/i, "").trim();
  return {
    name: baseName || (endpointParts.server ? `WireGuard · ${endpointParts.server}` : "WireGuard"),
    protocol: "wireguard", raw: contents.trim(),
    server: endpointParts.server, port: endpointParts.port,
  };
};

export const parseConfigLine = (input: string): ParsedConfigDraft | null => {
  const raw = input.trim();
  if (!raw) return null;
  if (/^vless:\/\//i.test(raw)) return fromLink(raw, "vless");
  if (/^vmess:\/\//i.test(raw)) return parseVmess(raw);
  if (/^trojan:\/\//i.test(raw)) return fromLink(raw, "trojan");
  if (/^ss:\/\//i.test(raw)) return fromLink(raw, "shadowsocks");
  if (/^(?:hysteria2|hy2):\/\//i.test(raw)) return fromLink(raw, "hysteria2");
  if (/^tuic:\/\//i.test(raw)) return fromLink(raw, "tuic");
  if (/^(?:socks|socks5):\/\//i.test(raw)) return fromLink(raw, "socks");
  if (/^http:\/\//i.test(raw)) return fromLink(raw, "http");
  if (/^wireguard:\/\//i.test(raw)) return fromLink(raw, "wireguard");
  return null;
};

const distinctLines = (input: string) =>
  [...new Set(input.replace(/\r/g, "")
    .split(/\n|\s+(?=(?:vless|vmess|trojan|ss|hysteria2|hy2|tuic|socks|socks5|http|wireguard):\/\/)/i)
    .map((line) => line.trim()).filter(Boolean))];

const parseLines = (input: string) =>
  distinctLines(input).map(parseConfigLine).filter((x): x is ParsedConfigDraft => Boolean(x));

export const parseConfigs = (input: string, wireGuardFilename?: string): ParsedConfigDraft[] => {
  const wireGuard = parseWireGuard(input, wireGuardFilename);
  if (wireGuard) return [wireGuard];
  const direct = parseLines(input);
  if (direct.length) return direct;
  const decoded = decodeBase64(input);
  if (!decoded || decoded === input) return [];
  return parseLines(decoded);
};

export const makeConfigs = (
  drafts: ParsedConfigDraft[],
  source: VpnConfig["source"],
  subscriptionId?: string,
): VpnConfig[] => {
  const now = Date.now();
  return drafts.map((draft) => ({
    ...draft,
    id: createId("cfg"), source, subscriptionId,
    createdAt: now, updatedAt: now, pingStatus: "idle" as const,
  }));
};

export const isSubscriptionUrl = (value: string) => {
  try {
    const parsed = new URL(value.trim());
    return parsed.protocol === "https:" && Boolean(parsed.hostname);
  } catch { return false; }
};

export const subscriptionNameFromUrl = (url: string) => {
  try { return new URL(url).hostname.replace(/^www\./, "") || "Subscription"; }
  catch { return "Subscription"; }
};
EOF

echo "==> Creating lib/vpn/singbox-config.ts"
cat > lib/vpn/singbox-config.ts << 'EOF'
import type { Protocol, VpnConfig, VpnPreferences } from "./types";

type JsonObject = Record<string, unknown>;

const decode = (v: string) => { try { return decodeURIComponent(v); } catch { return v; } };
const numberOr = (v: string | null | undefined, f: number) => {
  const p = Number(v); return Number.isFinite(p) ? p : f;
};
const queryObject = (url: URL) => Object.fromEntries(url.searchParams.entries());

const tlsOptions = (q: Record<string, string>, host: string): JsonObject | undefined => {
  const sec = q.security ?? q.tls;
  if (!sec || sec === "none") return undefined;
  const tls: JsonObject = { enabled: true, server_name: q.sni || q.peer || host };
  if (q.alpn) tls.alpn = q.alpn.split(",").map((s) => s.trim()).filter(Boolean);
  if (q.allowInsecure === "1" || q.insecure === "1") tls.insecure = true;
  if (sec === "reality" || q.pbk || q.publicKey) {
    tls.reality = { enabled: true, public_key: q.pbk || q.publicKey, short_id: q.sid || q.shortId || "" };
  }
  return tls;
};

const transportOptions = (q: Record<string, string>): JsonObject | undefined => {
  const t = q.type || q.net;
  if (!t || t === "tcp") return undefined;
  if (t === "ws") return { type: "ws", path: q.path || "/", headers: q.host ? { Host: q.host } : undefined };
  if (t === "grpc") return { type: "grpc", service_name: q.serviceName || q.path || "" };
  if (t === "http" || t === "h2") return { type: "http", path: q.path || "/", host: q.host ? [q.host] : undefined };
  return { type: t };
};

const parseVmess = (raw: string): JsonObject => {
  const encoded = raw.slice("vmess://".length);
  const json = typeof (globalThis as any).atob === "function" ? (globalThis as any).atob(encoded) : "";
  const v = JSON.parse(json) as Record<string, unknown>;
  const server = String(v.add || v.host || "");
  const query = {
    security: String(v.tls || "none"), sni: String(v.sni || v.host || ""),
    type: String(v.net || "tcp"), path: String(v.path || "/"),
    host: String(v.host || ""), serviceName: String(v.path || ""),
  };
  return {
    type: "vmess", tag: "proxy", server, server_port: Number(v.port || 443),
    uuid: String(v.id || ""), alter_id: Number(v.aid || 0), security: String(v.scy || "auto"),
    tls: tlsOptions(query, server), transport: transportOptions(query),
  };
};

const parseShadowsocks = (url: URL): JsonObject => {
  const enc = url.username;
  let method = "", password = "";
  try {
    const d = (globalThis as any).atob?.(`${enc}${"=".repeat((4 - (enc.length % 4)) % 4)}`) || "";
    [method, password] = d.split(":", 2);
  } catch { [method, password] = decode(enc).split(":", 2); }
  return { type: "shadowsocks", tag: "proxy", server: url.hostname, server_port: Number(url.port || 443), method, password };
};

const parseWireGuard = (raw: string): JsonObject => {
  const sec = raw.split(/\n\s*\[/).map((p) => p.replace(/^\[/, ""));
  const read = (s: string, k: string) => {
    const b = sec.find((i) => i.toLowerCase().startsWith(s.toLowerCase()));
    return b?.match(new RegExp(`^${k}\\s*=\\s*(.+)$`, "im"))?.[1]?.trim();
  };
  const ep = read("Peer]", "Endpoint") || "";
  const epUrl = ep.includes("://") ? new URL(ep) : new URL(`udp://${ep}`);
  const addrs = (read("Interface]", "Address") || "172.16.0.2/32").split(",").map((s) => s.trim());
  return {
    type: "wireguard", tag: "proxy",
    server: epUrl.hostname, server_port: numberOr(epUrl.port, 51820),
    local_address: addrs,
    private_key: read("Interface]", "PrivateKey") || "",
    peer_public_key: read("Peer]", "PublicKey") || "",
    pre_shared_key: read("Peer]", "PresharedKey"),
    mtu: numberOr(read("Interface]", "MTU"), 1280),
  };
};

export const buildSingBoxOutbound = (config: VpnConfig): JsonObject => {
  if (config.protocol === "wireguard" || config.raw.trimStart().startsWith("[Interface]")) return parseWireGuard(config.raw);
  if (config.protocol === "vmess") return parseVmess(config.raw);
  const url = new URL(config.raw);
  const q = queryObject(url);
  const server = url.hostname;
  const serverPort = numberOr(url.port, 443);
  const tls = tlsOptions(q, server);
  const transport = transportOptions(q);
  const common = { tag: "proxy", server, server_port: serverPort };
  switch (config.protocol as Protocol) {
    case "vless": return { type: "vless", ...common, uuid: decode(url.username), flow: q.flow || undefined, tls, transport };
    case "trojan": return { type: "trojan", ...common, password: decode(url.username), tls, transport };
    case "hysteria2": return { type: "hysteria2", ...common, password: decode(url.username), tls: tls || { enabled: true, server_name: q.sni || server }, obfs: q.obfs ? { type: q.obfs, password: q.obfs_password } : undefined };
    case "tuic": return { type: "tuic", ...common, uuid: decode(url.username), password: decode(url.password), tls: tls || { enabled: true, server_name: q.sni || server }, congestion_control: q.congestion_control || "bbr" };
    case "socks": return { type: "socks", ...common, version: url.protocol.startsWith("socks5") ? "5" : "4", username: decode(url.username) || undefined, password: decode(url.password) || undefined };
    case "http": return { type: "http", ...common, username: decode(url.username) || undefined, password: decode(url.password) || undefined };
    case "shadowsocks": return parseShadowsocks(url);
    default: throw new Error(`Unsupported protocol: ${config.protocol}`);
  }
};

export const buildSingBoxConfig = (config: VpnConfig, prefs: VpnPreferences): JsonObject => {
  const proxy = buildSingBoxOutbound(config);
  return {
    log: { level: "info" },
    dns: {
      servers: [
        { tag: "dns4", address: prefs.dns4 },
        ...(prefs.dns6 ? [{ tag: "dns6", address: prefs.dns6 }] : []),
      ],
    },
    inbounds: [{
      type: "tun", address: ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      mtu: prefs.mtu, auto_route: true, strict_route: true, stack: "system",
    }],
    outbounds: [proxy, { type: "direct", tag: "direct" }, { type: "block", tag: "block" }],
    route: { auto_detect_interface: true, final: "proxy" },
  };
};
EOF

echo "==> Creating lib/vpn/storage.ts"
cat > lib/vpn/storage.ts << 'EOF'
import AsyncStorage from "@react-native-async-storage/async-storage";
import { INITIAL_VPN_STATE, type VpnState } from "./types";

const KEY = "behinet.vpn.state.v1";

export const VpnStorage = {
  async read(): Promise<VpnState> {
    try {
      const raw = await AsyncStorage.getItem(KEY);
      if (!raw) return INITIAL_VPN_STATE;
      const parsed = JSON.parse(raw) as VpnState;
      return { ...INITIAL_VPN_STATE, ...parsed };
    } catch { return INITIAL_VPN_STATE; }
  },
  async write(state: VpnState): Promise<void> {
    try { await AsyncStorage.setItem(KEY, JSON.stringify(state)); } catch {}
  },
};
EOF

echo "==> Creating lib/vpn/native-engine.ts"
cat > lib/vpn/native-engine.ts << 'EOF'
import { NativeModules } from "react-native";
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

const getBridge = () =>
  (NativeModules as Record<string, NativeVpnBridge | undefined>).BehiNetVpnEngine;

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

echo "==> Creating lib/vpn/provider.tsx"
cat > lib/vpn/provider.tsx << 'EOF'
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { NativeCoreUnavailableError, NativeVpnEngine } from "./native-engine";
import { createId, isSubscriptionUrl, makeConfigs, parseConfigs, subscriptionNameFromUrl } from "./parser";
import { VpnStorage } from "./storage";
import { INITIAL_VPN_STATE, type Subscription, type VpnConfig, type VpnPreferences, type VpnState } from "./types";

type AddResult = { count: number; subscription?: Subscription; warning?: string };
type RefreshResult = { success: boolean; count: number; error?: string };

type VpnContextValue = {
  state: VpnState;
  ready: boolean;
  addConfigText: (text: string, source?: VpnConfig["source"], nameHint?: string) => Promise<AddResult>;
  addSubscriptionUrl: (url: string, name?: string) => Promise<AddResult>;
  importWireGuard: (contents: string, filename: string) => Promise<AddResult>;
  refreshSubscription: (subscriptionId: string) => Promise<RefreshResult>;
  selectConfig: (configId: string) => void;
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
  pingConfig: (configId: string) => Promise<void>;
  updatePreferences: (patch: Partial<VpnPreferences>) => void;
  removeConfig: (configId: string) => void;
};

const VpnContext = createContext<VpnContextValue | null>(null);
const SUBSCRIPTION_TIMEOUT_MS = 15_000;
const MAX_SUBSCRIPTION_BYTES = 2 * 1024 * 1024;

const createNameAllocator = (existing: VpnConfig[]) => {
  const names = new Set(existing.map((c) => c.name.trim().toLowerCase()));
  return (base: string) => {
    const clean = base.trim() || "Configuration";
    let candidate = clean;
    let i = 2;
    while (names.has(candidate.toLowerCase())) candidate = `${clean} ${i++}`;
    names.add(candidate.toLowerCase());
    return candidate;
  };
};

export function VpnProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<VpnState>(INITIAL_VPN_STATE);
  const stateRef = useRef(state);
  const [ready, setReady] = useState(false);

  const update = useCallback((mutate: (current: VpnState) => VpnState) => {
    const next = mutate(stateRef.current);
    stateRef.current = next;
    setState(next);
    void VpnStorage.write(next).catch(() => undefined);
    return next;
  }, []);

  useEffect(() => {
    VpnStorage.read().then((loaded) => {
      stateRef.current = loaded;
      setState(loaded);
    }).finally(() => setReady(true));
  }, []);

  const addConfigText = useCallback(async (text: string, source: VpnConfig["source"] = "manual", nameHint?: string): Promise<AddResult> => {
    const drafts = parseConfigs(text, nameHint);
    if (!drafts.length) throw new Error("invalid-config");
    const current = stateRef.current;
    const alloc = createNameAllocator(current.configs);
    const configs = makeConfigs(drafts, source).map((c) => ({
      ...c, name: alloc(nameHint && drafts.length === 1 ? nameHint : c.name),
    }));
    update((prev) => ({
      ...prev,
      configs: [...prev.configs, ...configs],
      selectedConfigId: prev.selectedConfigId ?? configs[0]?.id,
    }));
    return { count: configs.length };
  }, [update]);

  const refreshSubscription = useCallback(async (subscriptionId: string): Promise<RefreshResult> => {
    const sub = stateRef.current.subscriptions.find((s) => s.id === subscriptionId);
    if (!sub) return { success: false, count: 0, error: "Subscription not found" };
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), SUBSCRIPTION_TIMEOUT_MS);
      let response: Response;
      try {
        response = await fetch(sub.url, { headers: { Accept: "text/plain, */*" }, signal: controller.signal, cache: "no-store" });
      } finally { clearTimeout(timeout); }
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const contents = await response.text();
      if (contents.length > MAX_SUBSCRIPTION_BYTES) throw new Error("Payload too large");
      const drafts = parseConfigs(contents);
      if (!drafts.length) throw new Error("No supported configurations");
      const alloc = createNameAllocator(stateRef.current.configs.filter((c) => c.subscriptionId !== sub.id));
      const configs = makeConfigs(drafts, "subscription", sub.id).map((c) => ({ ...c, name: alloc(c.name) }));
      update((prev) => {
        const retained = prev.configs.filter((c) => c.subscriptionId !== sub.id);
        const selRemoved = prev.selectedConfigId
          ? prev.configs.some((c) => c.id === prev.selectedConfigId && c.subscriptionId === sub.id) : false;
        return {
          ...prev,
          configs: [...retained, ...configs],
          selectedConfigId: selRemoved ? configs[0]?.id : prev.selectedConfigId,
          subscriptions: prev.subscriptions.map((s) => s.id === sub.id ? { ...s, updatedAt: Date.now(), configCount: configs.length, lastError: undefined } : s),
        };
      });
      return { success: true, count: configs.length };
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Refresh failed";
      update((prev) => ({
        ...prev,
        subscriptions: prev.subscriptions.map((s) => s.id === sub.id ? { ...s, lastError: msg } : s),
      }));
      return { success: false, count: 0, error: msg };
    }
  }, [update]);

  const addSubscriptionUrl = useCallback(async (url: string, name?: string): Promise<AddResult> => {
    if (!isSubscriptionUrl(url)) throw new Error("invalid-url");
    const normalized = url.trim();
    const existing = stateRef.current.subscriptions.find((s) => s.url === normalized);
    if (existing) {
      const r = await refreshSubscription(existing.id);
      return { count: r.count, subscription: existing, warning: r.success ? undefined : r.error };
    }
    const sub: Subscription = {
      id: createId("sub"), url: normalized, name: name?.trim() || subscriptionNameFromUrl(url),
      createdAt: Date.now(), configCount: 0,
    };
    update((prev) => ({ ...prev, subscriptions: [...prev.subscriptions, sub] }));
    const r = await refreshSubscription(sub.id);
    return { count: r.count, subscription: sub, warning: r.success ? undefined : r.error };
  }, [refreshSubscription, update]);

  const importWireGuard = useCallback(async (contents: string, filename: string) =>
    addConfigText(contents, "wireguard", filename), [addConfigText]);

  const selectConfig = useCallback((configId: string) =>
    update((prev) => ({ ...prev, selectedConfigId: configId })), [update]);

  const connect = useCallback(async () => {
    const { selectedConfigId, configs, preferences } = stateRef.current;
    const config = configs.find((c) => c.id === selectedConfigId);
    if (!config) throw new Error("no-config-selected");
    update((prev) => ({ ...prev, connection: { status: "connecting", configId: config.id, startedAt: Date.now() } }));
    try {
      await NativeVpnEngine.connect(config, preferences);
      update((prev) => ({ ...prev, connection: { status: "connected", configId: config.id, startedAt: Date.now() } }));
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Connection failed";
      update((prev) => ({
        ...prev,
        connection: { status: error instanceof NativeCoreUnavailableError ? "needs-native" : "disconnected", configId: config.id, message: msg },
      }));
      throw error;
    }
  }, [update]);

  const disconnect = useCallback(async () => {
    if (!NativeVpnEngine.available()) {
      update((prev) => ({ ...prev, connection: { status: "disconnected" } }));
      return;
    }
    try {
      await NativeVpnEngine.disconnect();
      update((prev) => ({ ...prev, connection: { status: "disconnected" } }));
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Disconnect failed";
      update((prev) => ({ ...prev, connection: { ...prev.connection, message: msg } }));
      throw error;
    }
  }, [update]);

  const pingConfig = useCallback(async (configId: string) => {
    const config = stateRef.current.configs.find((c) => c.id === configId);
    if (!config) return;
    update((prev) => ({ ...prev, configs: prev.configs.map((c) => c.id === configId ? { ...c, pingStatus: "checking", pingMessage: undefined } : c) }));
    try {
      const r = await NativeVpnEngine.ping(config);
      update((prev) => ({ ...prev, configs: prev.configs.map((c) => c.id === configId ? { ...c, pingStatus: "available", lastPingMs: Math.round(r.latencyMs), pingMessage: undefined } : c) }));
    } catch (error) {
      const msg = error instanceof Error ? error.message : "Ping failed";
      update((prev) => ({ ...prev, configs: prev.configs.map((c) => c.id === configId ? { ...c, pingStatus: "unavailable", lastPingMs: undefined, pingMessage: msg } : c) }));
    }
  }, [update]);

  const updatePreferences = useCallback((patch: Partial<VpnPreferences>) =>
    update((prev) => ({ ...prev, preferences: { ...prev.preferences, ...patch } })), [update]);

  const removeConfig = useCallback((configId: string) =>
    update((prev) => ({
      ...prev,
      configs: prev.configs.filter((c) => c.id !== configId),
      selectedConfigId: prev.selectedConfigId === configId
        ? prev.configs.find((c) => c.id !== configId)?.id : prev.selectedConfigId,
    })), [update]);

  const value = useMemo<VpnContextValue>(() => ({
    state, ready, addConfigText, addSubscriptionUrl, importWireGuard,
    refreshSubscription, selectConfig, connect, disconnect,
    pingConfig, updatePreferences, removeConfig,
  }), [state, ready, addConfigText, addSubscriptionUrl, importWireGuard, refreshSubscription, selectConfig, connect, disconnect, pingConfig, updatePreferences, removeConfig]);

  return <VpnContext.Provider value={value}>{children}</VpnContext.Provider>;
}

export const useVpn = () => {
  const ctx = useContext(VpnContext);
  if (!ctx) throw new Error("useVpn must be used inside VpnProvider");
  return ctx;
};
EOF

echo "==> Creating lib/vpn/index.ts"
cat > lib/vpn/index.ts << 'EOF'
export * from "./types";
export * from "./parser";
export * from "./singbox-config";
export * from "./storage";
export * from "./native-engine";
export { VpnProvider, useVpn } from "./provider";
EOF

echo ""
echo "✅ All 8 lib/vpn files created!"
echo ""
echo "Next: app files (layout, index, servers, add, settings)"
