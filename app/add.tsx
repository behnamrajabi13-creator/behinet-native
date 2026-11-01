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
