import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  ScrollView,
  Modal,
} from 'react-native';
import { CommonActions, useNavigation } from '@react-navigation/native';
import { useAppRevealScreen } from 'react-native-appreveal';
import { ExampleState } from '../services/ExampleState';
import { EditProfileModal } from './EditProfileModal';
import type { ProfileScreenProps } from '../navigation/types';

export function ProfileScreen(_props: ProfileScreenProps) {
  useAppRevealScreen('profile', 'Profile');

  const navigation = useNavigation();
  const state = ExampleState.instance;
  const [editVisible, setEditVisible] = useState(false);
  const [, forceUpdate] = useState(0);

  const handleLogout = () => {
    ExampleState.instance.isLoggedIn = false;
    navigation.dispatch(
      CommonActions.reset({ index: 0, routes: [{ name: 'Auth' }] }),
    );
  };

  const handleSave = () => {
    setEditVisible(false);
    forceUpdate(n => n + 1);
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {/* Avatar */}
      <View testID="profile.avatar" style={styles.avatar}>
        <Text style={styles.avatarEmoji}>👤</Text>
      </View>

      <Text testID="profile.name" style={styles.name}>
        {state.userName.length > 0 ? state.userName : 'Demo User'}
      </Text>

      <Text testID="profile.email" style={styles.email}>
        {state.userEmail.length > 0 ? state.userEmail : 'demo@example.com'}
      </Text>

      <Text style={styles.memberSince}>Member since January 2024</Text>

      <View style={styles.actions}>
        <TouchableOpacity
          testID="profile.edit"
          style={styles.button}
          onPress={() => setEditVisible(true)}
          activeOpacity={0.8}>
          <Text style={styles.buttonText}>Edit Profile</Text>
        </TouchableOpacity>

        <TouchableOpacity
          testID="profile.logout"
          style={[styles.button, styles.buttonDanger]}
          onPress={handleLogout}
          activeOpacity={0.8}>
          <Text style={styles.buttonTextDanger}>Log Out</Text>
        </TouchableOpacity>
      </View>

      <Modal
        visible={editVisible}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setEditVisible(false)}>
        <EditProfileModal
          onSave={handleSave}
          onCancel={() => setEditVisible(false)}
        />
      </Modal>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  content: {
    alignItems: 'center',
    padding: 24,
    paddingBottom: 40,
  },
  avatar: {
    width: 96,
    height: 96,
    borderRadius: 48,
    backgroundColor: '#e8f0fe',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 16,
  },
  avatarEmoji: {
    fontSize: 48,
  },
  name: {
    fontSize: 22,
    fontWeight: '700',
    color: '#333',
    marginBottom: 4,
  },
  email: {
    fontSize: 15,
    color: '#888',
    marginBottom: 4,
  },
  memberSince: {
    fontSize: 13,
    color: '#aaa',
    marginBottom: 32,
  },
  actions: {
    width: '100%',
  },
  button: {
    backgroundColor: '#007AFF',
    borderRadius: 10,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: 12,
  },
  buttonDanger: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#e53e3e',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  buttonTextDanger: {
    color: '#e53e3e',
    fontSize: 16,
    fontWeight: '600',
  },
});
