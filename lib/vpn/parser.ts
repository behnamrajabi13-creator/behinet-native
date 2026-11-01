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

type Endpoint = { server?: string; port?: string };

const extractEndpoint = (raw: string): Endpoint => {
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
  const endpointParts: Endpoint = endpoint ? extractEndpoint(`wireguard://${endpoint}`) : {};
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
