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
