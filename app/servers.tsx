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
