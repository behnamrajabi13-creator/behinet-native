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
