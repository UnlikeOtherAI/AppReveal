import React, { useState } from 'react';
import {
  View,
  Text,
  Switch,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
} from 'react-native';
import { useAppRevealScreen } from 'react-native-appreveal';
import { ExampleState } from '../services/ExampleState';

export function SettingsScreen() {
  useAppRevealScreen('settings', 'Settings');

  const state = ExampleState.instance;
  const [notifications, setNotifications] = useState(
    state.notificationsEnabled,
  );
  const [darkMode, setDarkMode] = useState(state.darkMode);

  const handleNotifications = (v: boolean) => {
    ExampleState.instance.notificationsEnabled = v;
    setNotifications(v);
  };

  const handleDarkMode = (v: boolean) => {
    ExampleState.instance.darkMode = v;
    setDarkMode(v);
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.sectionHeader}>Preferences</Text>
      <View style={styles.card}>
        <View style={styles.row}>
          <Text testID="settings.notifications" style={styles.rowLabel}>
            Notifications
          </Text>
          <Switch
            testID="settings.notifications_switch"
            value={notifications}
            onValueChange={handleNotifications}
          />
        </View>

        <View style={[styles.row, styles.rowBorder]}>
          <Text testID="settings.darkMode" style={styles.rowLabel}>
            Dark Mode
          </Text>
          <Switch
            testID="settings.dark_mode_switch"
            value={darkMode}
            onValueChange={handleDarkMode}
          />
        </View>

        <View style={[styles.row, styles.rowBorder]}>
          <Text testID="settings.language" style={styles.rowLabel}>
            Language
          </Text>
          <Text style={styles.rowValue}>English</Text>
        </View>
      </View>

      <Text style={styles.sectionHeader}>About</Text>
      <View style={styles.card}>
        <TouchableOpacity style={styles.row} activeOpacity={0.7} onPress={() => {}}>
          <Text style={styles.rowLabel}>Privacy Policy</Text>
          <Text style={styles.chevron}>›</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.row, styles.rowBorder]}
          activeOpacity={0.7}
          onPress={() => {}}>
          <Text style={styles.rowLabel}>Terms of Service</Text>
          <Text style={styles.chevron}>›</Text>
        </TouchableOpacity>

        <View style={[styles.row, styles.rowBorder]}>
          <Text testID="settings.version" style={styles.rowLabel}>
            Version
          </Text>
          <Text style={styles.rowValue}>1.0.0</Text>
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  content: {
    padding: 16,
    paddingBottom: 40,
  },
  sectionHeader: {
    fontSize: 13,
    fontWeight: '600',
    color: '#888',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
    marginLeft: 4,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 10,
    marginBottom: 24,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#e0e0e0',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  rowBorder: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#f0f0f0',
  },
  rowLabel: {
    fontSize: 16,
    color: '#333',
  },
  rowValue: {
    fontSize: 15,
    color: '#888',
  },
  chevron: {
    fontSize: 20,
    color: '#c0c0c0',
  },
});
