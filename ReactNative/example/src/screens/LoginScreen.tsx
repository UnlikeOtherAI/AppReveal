import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  ActivityIndicator,
  StyleSheet,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { CommonActions } from '@react-navigation/native';
import { useAppRevealScreen } from 'react-native-appreveal';
import { ExampleState } from '../services/ExampleState';
import { ExampleNetworkClient } from '../services/ExampleNetworkClient';
import type { RootStackParamList } from '../navigation/types';

type Props = NativeStackScreenProps<RootStackParamList, 'Auth'>;

export function LoginScreen({ navigation }: Props) {
  useAppRevealScreen('auth.login', 'Login');

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async () => {
    setLoading(true);
    setError(null);

    await ExampleNetworkClient.instance.login(
      email.length > 0 ? email : 'demo@example.com',
    );

    // Simulate a small delay
    await new Promise(r => setTimeout(r, 600));

    ExampleState.instance.isLoggedIn = true;
    ExampleState.instance.userEmail =
      email.length > 0 ? email : 'demo@example.com';
    ExampleState.instance.userName = 'Demo User';

    setLoading(false);
    navigation.dispatch(
      CommonActions.reset({ index: 0, routes: [{ name: 'Main' }] }),
    );
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={styles.inner}>
        <Text style={styles.logo} testID="login.logo">
          AR
        </Text>
        <Text style={styles.title}>AppReveal Example</Text>

        <TextInput
          testID="login.email"
          style={styles.input}
          placeholder="Email"
          placeholderTextColor="#999"
          value={email}
          onChangeText={setEmail}
          keyboardType="email-address"
          autoCapitalize="none"
          autoCorrect={false}
        />

        <TextInput
          testID="login.password"
          style={styles.input}
          placeholder="Password"
          placeholderTextColor="#999"
          value={password}
          onChangeText={setPassword}
          secureTextEntry
        />

        {error != null && (
          <Text testID="login.error" style={styles.error}>
            {error}
          </Text>
        )}

        <TouchableOpacity
          testID="login.submit"
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleLogin}
          disabled={loading}
          activeOpacity={0.8}>
          {loading ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <Text style={styles.buttonText}>Sign In</Text>
          )}
        </TouchableOpacity>

        <TouchableOpacity
          testID="login.forgot_password"
          onPress={() => {}}
          style={styles.link}>
          <Text style={styles.linkText}>Forgot password?</Text>
        </TouchableOpacity>

        <TouchableOpacity
          testID="login.sign_up"
          onPress={() => {}}
          style={styles.link}>
          <Text style={styles.linkText}>Don't have an account? Sign up</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  inner: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  logo: {
    alignSelf: 'center',
    fontSize: 48,
    fontWeight: '700',
    color: '#007AFF',
    marginBottom: 8,
  },
  title: {
    alignSelf: 'center',
    fontSize: 20,
    fontWeight: '600',
    color: '#333',
    marginBottom: 32,
  },
  input: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 16,
    paddingVertical: 12,
    fontSize: 16,
    color: '#333',
    marginBottom: 12,
  },
  error: {
    color: '#e53e3e',
    fontSize: 14,
    marginBottom: 8,
    textAlign: 'center',
  },
  button: {
    backgroundColor: '#007AFF',
    borderRadius: 8,
    paddingVertical: 14,
    alignItems: 'center',
    marginTop: 8,
    marginBottom: 16,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  link: {
    alignItems: 'center',
    paddingVertical: 8,
  },
  linkText: {
    color: '#007AFF',
    fontSize: 14,
  },
});
