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
