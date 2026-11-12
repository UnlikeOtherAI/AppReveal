import React, { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useAppRevealScreen } from 'react-native-appreveal';

export function TapCalibrationScreen() {
  useAppRevealScreen('calibration', 'Tap Calibration');
  const [count, setCount] = useState(0);
  return (
    <View style={styles.container}>
      <Text>Tap the red target to verify MCP tap_point accuracy</Text>
      <Pressable
        testID="calibration.target"
        accessibilityRole="button"
        accessibilityLabel="Calibration target"
        onPress={() => setCount(value => value + 1)}
        style={styles.target}
      />
      <Text testID="calibration.result">{`Target taps: ${count}`}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', padding: 24, gap: 24 },
  target: { width: 120, height: 120, borderRadius: 8, backgroundColor: '#d32f2f' },
});
