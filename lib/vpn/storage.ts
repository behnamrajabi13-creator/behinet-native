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
