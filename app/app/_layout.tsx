import "../global.css";
import { View, StyleSheet, Platform, KeyboardAvoidingView } from "react-native";
import { Stack } from "expo-router";
import { TelegramProvider } from "./components/Telegram";
import { GlobalLogoBarWithFallback } from "./components/GlobalLogoBarWithFallback";
import { GlobalBottomBar } from "./components/GlobalBottomBar";
import { GlobalBottomBarWeb } from "./components/GlobalBottomBarWeb";
import { useColors } from "./theme";
import { useTelegram } from "./components/Telegram";

/**
 * Three-block column layout (same as Flutter):
 * 1. Logo bar (optional in TMA when not fullscreen)
 * 2. Main area (flex, scrollable per screen) – Stack updates on route change
 * 3. [Web only] Raw HTML textarea test (compare with GlobalBottomBar in TMA)
 * 4. AI & Search bar (fixed at bottom)
 */
export default function RootLayout() {
  return (
    <TelegramProvider>
      {Platform.OS === "ios" ? (
        <KeyboardAvoidingView
          style={styles.keyboardAvoid}
          behavior="padding"
          keyboardVerticalOffset={0}
        >
          <RootContent />
        </KeyboardAvoidingView>
      ) : (
        <RootContent />
      )}
    </TelegramProvider>
  );
}

function RootContent() {
  const colors = useColors();
  const { themeBgReady } = useTelegram();
  const backgroundColor = themeBgReady ? colors.background : "transparent";

  return (
    <View
      style={[
        styles.root,
        {
          backgroundColor,
          opacity: themeBgReady ? 1 : 0,
          // Prevent dark-theme flicker from being interactable before Telegram theme arrives.
          pointerEvents: themeBgReady ? "auto" : "none",
        },
      ]}
    >
      <GlobalLogoBarWithFallback />
      <View style={styles.main}>
        <Stack screenOptions={{ headerShown: false }} />
      </View>
      {Platform.OS === "web" ? <GlobalBottomBarWeb /> : <GlobalBottomBar />}
    </View>
  );
}

const styles = StyleSheet.create({
  keyboardAvoid: {
    flex: 1,
  },
  root: {
    flex: 1,
    flexDirection: "column",
    overflow: "hidden",
  },
  main: {
    flex: 1,
    minHeight: 0,
  },
});
