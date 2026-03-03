import { View, StyleSheet } from "react-native";
import { Stack } from "expo-router";
import { TelegramProvider } from "./components/Telegram";
import { GlobalLogoBarWithFallback } from "./components/GlobalLogoBarWithFallback";

export default function RootLayout() {
  return (
    <TelegramProvider>
      <View style={styles.root}>
        <GlobalLogoBarWithFallback />
        <View style={styles.content}>
          <Stack screenOptions={{ headerShown: false }} />
        </View>
      </View>
    </TelegramProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { flex: 1 },
});
