#!/usr/bin/env bash
set -e

echo "==> Creating app/_layout.tsx"
cat > app/_layout.tsx << 'EOF'
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
EOF

echo "==> Creating app/index.tsx"
cat > app/index.tsx << 'EOF'
import { Link } from "expo-router";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { NativeVpnEngine } from "../lib/vpn";
import { useVpn } from "../lib/vpn/provider";

const C = {
  ink: "#102D2B", teal: "#256A68", mint: "#80C6A4",
  paper: "#F6F5EF", card: "#FFFFFF", muted: "#71817B",
  line: "#E4E8DF", lime: "#D8F56B", danger: "#BC5149", pale: "#ECF2E9",
};

export default function HomeScreen() {
  const { state, ready, connect, disconnect } = useVpn();
  const selected = state.configs.find((c) => c.id === state.selectedConfigId);
  const status = state.connection.status;
  const nativeAvailable = NativeVpnEngine.available();

  const onToggle = async () => {
    try {
      if (status === "connected") await disconnect();
      else await connect();
    } catch (e) {
      // error already stored in state.connection.message
    }
  };

  if (!ready) {
    return (
      <SafeAreaView style={styles.center}>
        <ActivityIndicator size="large" color={C.mint} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      <ScrollView contentContainerStyle={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>BehiNet</Text>
          <Text style={styles.subtitle}>اتصال خصوصی با وضعیت شفاف</Text>
        </View>

        <View style={styles.statusCard}>
          <View style={[styles.statusDot, { backgroundColor: statusColor(status) }]} />
          <Text style={styles.statusLabel}>{statusLabel(status)}</Text>
          {state.connection.message ? (
            <Text style={styles.statusMessage}>{state.connection.message}</Text>
          ) : null}
        </View>

        <View style={styles.selectedCard}>
          <Text style={styles.sectionLabel}>سرور انتخاب‌شده</Text>
          {selected ? (
            <>
              <Text style={styles.serverName}>{selected.name}</Text>
              <Text style={styles.serverMeta}>
                {selected.protocol.toUpperCase()}
                {selected.server ? ` · ${selected.server}` : ""}
                {selected.port ? `:${selected.port}` : ""}
              </Text>
            </>
          ) : (
            <Text style={styles.emptyText}>هنوز سروری اضافه نشده است</Text>
          )}
        </View>

        {!nativeAvailable && (
          <View style={styles.warnBox}>
            <Text style={styles.warnTitle}>موتور VPN نصب نشده</Text>
            <Text style={styles.warnText}>
              این APK بدون libbox.aar ساخته شده. برای اتصال واقعی، باید build native با AAR انجام شود.
            </Text>
          </View>
        )}

        <Pressable
          onPress={onToggle}
          disabled={!selected || status === "connecting" || !nativeAvailable}
          style={[styles.mainButton, { opacity: (!selected || !nativeAvailable) ? 0.5 : 1 }]}
        >
          <Text style={styles.mainButtonText}>
            {status === "connecting" ? "در حال اتصال…" :
             status === "connected" ? "قطع اتصال" :
             "اتصال"}
          </Text>
        </Pressable>

        <View style={styles.navRow}>
          <Link href="/servers" asChild>
            <Pressable style={styles.navButton}>
              <Text style={styles.navText}>سرورها ({state.configs.length})</Text>
            </Pressable>
          </Link>
          <Link href="/add" asChild>
            <Pressable style={styles.navButton}>
              <Text style={styles.navText}>افزودن</Text>
            </Pressable>
          </Link>
          <Link href="/settings" asChild>
            <Pressable style={styles.navButton}>
              <Text style={styles.navText}>تنظیمات</Text>
            </Pressable>
          </Link>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const statusColor = (s: string) =>
  s === "connected" ? C.mint : s === "connecting" ? C.lime : s === "needs-native" ? C.danger : C.muted;

const statusLabel = (s: string) =>
  s === "connected" ? "متصل" : s === "connecting" ? "در حال اتصال" :
  s === "needs-native" ? "موتور native نیست" : "قطع";

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.ink },
  center: { flex: 1, backgroundColor: C.ink, alignItems: "center", justifyContent: "center" },
  container: { padding: 20, gap: 16 },
  header: { marginBottom: 8 },
  title: { color: C.paper, fontSize: 32, fontWeight: "700", textAlign: "right" },
  subtitle: { color: C.muted, fontSize: 14, textAlign: "right", marginTop: 4 },
  statusCard: { backgroundColor: C.teal, borderRadius: 16, padding: 20, alignItems: "center", gap: 8 },
  statusDot: { width: 14, height: 14, borderRadius: 7 },
  statusLabel: { color: C.paper, fontSize: 18, fontWeight: "600" },
  statusMessage: { color: C.lime, fontSize: 12, textAlign: "center", marginTop: 4 },
  selectedCard: { backgroundColor: C.card, borderRadius: 16, padding: 16, gap: 4 },
  sectionLabel: { color: C.muted, fontSize: 12, textAlign: "right" },
  serverName: { color: C.ink, fontSize: 16, fontWeight: "600", textAlign: "right" },
  serverMeta: { color: C.muted, fontSize: 12, textAlign: "right", fontFamily: "monospace" },
  emptyText: { color: C.muted, fontSize: 14, textAlign: "right", paddingVertical: 8 },
  warnBox: { backgroundColor: "#FBE9E7", borderRadius: 12, padding: 12, gap: 4 },
  warnTitle: { color: C.danger, fontSize: 13, fontWeight: "700", textAlign: "right" },
  warnText: { color: C.danger, fontSize: 12, textAlign: "right", lineHeight: 18 },
  mainButton: { backgroundColor: C.mint, borderRadius: 999, paddingVertical: 18, alignItems: "center", marginTop: 8 },
  mainButtonText: { color: C.ink, fontSize: 18, fontWeight: "700" },
  navRow: { flexDirection: "row-reverse", gap: 8, marginTop: 8 },
  navButton: { flex: 1, backgroundColor: C.pale, borderRadius: 12, padding: 12, alignItems: "center" },
  navText: { color: C.ink, fontSize: 13, fontWeight: "600" },
});
EOF

echo "==> Creating app/servers.tsx"
cat > app/servers.tsx << 'EOF'
import { Link, router } from "expo-router";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useVpn } from "../lib/vpn/provider";

const C = {
  ink: "#102D2B", teal: "#256A68", mint: "#80C6A4",
  paper: "#F6F5EF", card: "#FFFFFF", muted: "#71817B",
  line: "#E4E8DF", lime: "#D8F56B", danger: "#BC5149", pale: "#ECF2E9",
};

export default function ServersScreen() {
  const { state, selectConfig, removeConfig, pingConfig } = useVpn();

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()}>
          <Text style={styles.back}>→</Text>
        </Pressable>
        <Text style={styles.title}>سرورها</Text>
        <Link href="/add" asChild>
          <Pressable style={styles.addBtn}><Text style={styles.addText}>+</Text></Pressable>
        </Link>
      </View>
      <ScrollView contentContainerStyle={styles.container}>
        {state.configs.length === 0 ? (
          <Text style={styles.empty}>هنوز سروری اضافه نشده است</Text>
        ) : state.configs.map((c) => {
          const selected = c.id === state.selectedConfigId;
          return (
            <View key={c.id} style={[styles.item, selected && styles.itemSelected]}>
              <Pressable onPress={() => selectConfig(c.id)} style={{ flex: 1 }}>
                <Text style={styles.name}>{c.name}</Text>
                <Text style={styles.meta}>
                  {c.protocol.toUpperCase()} · {c.server || "—"}{c.port ? `:${c.port}` : ""}
                </Text>
                <Text style={styles.ping}>
                  {c.pingStatus === "checking" ? "در حال ping…" :
                   c.pingStatus === "available" && c.lastPingMs ? `ping: ${c.lastPingMs}ms` :
                   c.pingStatus === "unavailable" ? "ping ناموفق" : "ping نشده"}
                </Text>
              </Pressable>
              <View style={{ gap: 6 }}>
                <Pressable onPress={() => pingConfig(c.id)} style={styles.smallBtn}>
                  <Text style={styles.smallText}>ping</Text>
                </Pressable>
                <Pressable onPress={() => removeConfig(c.id)} style={[styles.smallBtn, { backgroundColor: "#FBE9E7" }]}>
                  <Text style={[styles.smallText, { color: C.danger }]}>حذف</Text>
                </Pressable>
              </View>
            </View>
          );
        })}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.ink },
  header: { flexDirection: "row-reverse", alignItems: "center", padding: 16, gap: 12 },
  back: { color: C.paper, fontSize: 24 },
  title: { flex: 1, color: C.paper, fontSize: 20, fontWeight: "700", textAlign: "right" },
  addBtn: { backgroundColor: C.mint, width: 36, height: 36, borderRadius: 18, alignItems: "center", justifyContent: "center" },
  addText: { color: C.ink, fontSize: 22, fontWeight: "700", marginTop: -2 },
  container: { padding: 16, gap: 8 },
  empty: { color: C.muted, textAlign: "center", paddingVertical: 40 },
  item: { backgroundColor: C.card, borderRadius: 12, padding: 14, flexDirection: "row-reverse", alignItems: "center", gap: 12, borderWidth: 2, borderColor: "transparent" },
  itemSelected: { borderColor: C.mint },
  name: { color: C.ink, fontSize: 15, fontWeight: "600", textAlign: "right" },
  meta: { color: C.muted, fontSize: 12, textAlign: "right", fontFamily: "monospace", marginTop: 2 },
  ping: { color: C.teal, fontSize: 11, textAlign: "right", marginTop: 4 },
  smallBtn: { backgroundColor: C.pale, borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6 },
  smallText: { color: C.ink, fontSize: 11, fontWeight: "600" },
});
EOF

echo "==> Creating app/add.tsx"
cat > app/add.tsx << 'EOF'
import { router } from "expo-router";
import { useState } from "react";
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useVpn } from "../lib/vpn/provider";

const C = {
  ink: "#102D2B", teal: "#256A68", mint: "#80C6A4",
  paper: "#F6F5EF", card: "#FFFFFF", muted: "#71817B",
  line: "#E4E8DF", lime: "#D8F56B", danger: "#BC5149", pale: "#ECF2E9",
};

export default function AddScreen() {
  const { addConfigText, addSubscriptionUrl } = useVpn();
  const [mode, setMode] = useState<"config" | "sub">("config");
  const [text, setText] = useState("");
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);

  const onSave = async () => {
    if (!text.trim()) return;
    setBusy(true);
    try {
      if (mode === "config") {
        const r = await addConfigText(text, "manual", name.trim() || undefined);
        Alert.alert("موفق", `${r.count} کانفیگ اضافه شد`);
      } else {
        const r = await addSubscriptionUrl(text.trim(), name.trim() || undefined);
        Alert.alert("موفق", `${r.count} کانفیگ از اشتراک خوانده شد`);
      }
      router.back();
    } catch (e) {
      Alert.alert("خطا", e instanceof Error ? e.message : "خطای نامشخص");
    } finally { setBusy(false); }
  };

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()}><Text style={styles.back}>→</Text></Pressable>
        <Text style={styles.title}>افزودن</Text>
      </View>
      <ScrollView contentContainerStyle={styles.container}>
        <View style={styles.tabRow}>
          <Pressable onPress={() => setMode("config")} style={[styles.tab, mode === "config" && styles.tabActive]}>
            <Text style={[styles.tabText, mode === "config" && styles.tabTextActive]}>کانفیگ</Text>
          </Pressable>
          <Pressable onPress={() => setMode("sub")} style={[styles.tab, mode === "sub" && styles.tabActive]}>
            <Text style={[styles.tabText, mode === "sub" && styles.tabTextActive]}>اشتراک</Text>
          </Pressable>
        </View>

        <Text style={styles.label}>نام (اختیاری)</Text>
        <TextInput value={name} onChangeText={setName} style={styles.input} placeholder="مثلاً سرور آلمان" placeholderTextColor={C.muted} />

        <Text style={styles.label}>{mode === "config" ? "لینک کانفیگ" : "URL اشتراک"}</Text>
        <TextInput
          value={text}
          onChangeText={setText}
          style={[styles.input, styles.textArea]}
          placeholder={mode === "config" ? "vless://... یا vmess://... یا [Interface]..." : "https://..."}
          placeholderTextColor={C.muted}
          multiline
          autoCapitalize="none"
          autoCorrect={false}
        />

        <Pressable onPress={onSave} disabled={busy || !text.trim()} style={[styles.saveBtn, { opacity: busy || !text.trim() ? 0.5 : 1 }]}>
          <Text style={styles.saveText}>{busy ? "در حال ذخیره…" : "ذخیره"}</Text>
        </Pressable>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.ink },
  header: { flexDirection: "row-reverse", alignItems: "center", padding: 16, gap: 12 },
  back: { color: C.paper, fontSize: 24 },
  title: { flex: 1, color: C.paper, fontSize: 20, fontWeight: "700", textAlign: "right" },
  container: { padding: 16, gap: 10 },
  tabRow: { flexDirection: "row-reverse", gap: 8, marginBottom: 8 },
  tab: { flex: 1, paddingVertical: 10, borderRadius: 10, backgroundColor: C.card, alignItems: "center" },
  tabActive: { backgroundColor: C.mint },
  tabText: { color: C.ink, fontSize: 14, fontWeight: "600" },
  tabTextActive: { color: C.ink, fontWeight: "700" },
  label: { color: C.muted, fontSize: 12, textAlign: "right", marginTop: 8 },
  input: { backgroundColor: C.card, borderRadius: 10, padding: 12, color: C.ink, fontSize: 14, textAlign: "right" },
  textArea: { minHeight: 140, textAlignVertical: "top", fontFamily: "monospace" },
  saveBtn: { backgroundColor: C.mint, borderRadius: 999, paddingVertical: 16, alignItems: "center", marginTop: 16 },
  saveText: { color: C.ink, fontSize: 16, fontWeight: "700" },
});
EOF

echo "==> Creating app/settings.tsx"
cat > app/settings.tsx << 'EOF'
import { router } from "expo-router";
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useVpn } from "../lib/vpn/provider";

const C = {
  ink: "#102D2B", teal: "#256A68", mint: "#80C6A4",
  paper: "#F6F5EF", card: "#FFFFFF", muted: "#71817B",
  line: "#E4E8DF", lime: "#D8F56B", danger: "#BC5149", pale: "#ECF2E9",
};

export default function SettingsScreen() {
  const { state, updatePreferences } = useVpn();
  const p = state.preferences;

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()}><Text style={styles.back}>→</Text></Pressable>
        <Text style={styles.title}>تنظیمات</Text>
      </View>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.section}>DNS</Text>
        <Text style={styles.label}>DNS IPv4</Text>
        <TextInput value={p.dns4} onChangeText={(v) => updatePreferences({ dns4: v })} style={styles.input} />
        <Text style={styles.label}>DNS IPv6</Text>
        <TextInput value={p.dns6} onChangeText={(v) => updatePreferences({ dns6: v })} style={styles.input} />

        <Text style={styles.section}>TUN</Text>
        <Text style={styles.label}>MTU (1280 پیشنهادی)</Text>
        <TextInput
          value={String(p.mtu)}
          onChangeText={(v) => {
            const n = Number(v);
            if (Number.isFinite(n) && n >= 1280 && n <= 9000) updatePreferences({ mtu: n });
          }}
          keyboardType="number-pad"
          style={styles.input}
        />

        <Text style={styles.section}>اشتراک‌ها ({state.subscriptions.length})</Text>
        {state.subscriptions.length === 0 ? (
          <Text style={styles.muted}>اشتراکی ثبت نشده</Text>
        ) : state.subscriptions.map((s) => (
          <View key={s.id} style={styles.subItem}>
            <Text style={styles.subName}>{s.name}</Text>
            <Text style={styles.subMeta}>{s.configCount} کانفیگ{s.lastError ? ` · خطا: ${s.lastError}` : ""}</Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: C.ink },
  header: { flexDirection: "row-reverse", alignItems: "center", padding: 16, gap: 12 },
  back: { color: C.paper, fontSize: 24 },
  title: { flex: 1, color: C.paper, fontSize: 20, fontWeight: "700", textAlign: "right" },
  container: { padding: 16, gap: 8 },
  section: { color: C.mint, fontSize: 14, fontWeight: "700", textAlign: "right", marginTop: 16 },
  label: { color: C.muted, fontSize: 12, textAlign: "right", marginTop: 6 },
  input: { backgroundColor: C.card, borderRadius: 10, padding: 12, color: C.ink, fontSize: 14, textAlign: "right", fontFamily: "monospace" },
  muted: { color: C.muted, textAlign: "right", paddingVertical: 8 },
  subItem: { backgroundColor: C.card, borderRadius: 10, padding: 12, gap: 2 },
  subName: { color: C.ink, fontSize: 14, fontWeight: "600", textAlign: "right" },
  subMeta: { color: C.muted, fontSize: 11, textAlign: "right" },
});
EOF

echo ""
echo "✅ All 4 app files created!"
