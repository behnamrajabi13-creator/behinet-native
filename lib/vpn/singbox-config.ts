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
