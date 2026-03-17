import React from 'react';
import { View, StyleSheet, TouchableOpacity, Text } from 'react-native';
import WebView from 'react-native-webview';
import { useAppRevealScreen } from 'react-native-appreveal';

export function WebViewScreen() {
  useAppRevealScreen('web.view.demo', 'Web View');

  const webViewRef = React.useRef<WebView>(null);

  return (
    <View style={styles.container}>
      <View style={styles.toolbar}>
        <TouchableOpacity
          testID="webdemo.back"
          style={styles.toolButton}
          onPress={() => webViewRef.current?.goBack()}
          activeOpacity={0.7}>
          <Text style={styles.toolButtonText}>‹ Back</Text>
        </TouchableOpacity>
        <TouchableOpacity
          testID="webdemo.forward"
          style={styles.toolButton}
          onPress={() => webViewRef.current?.goForward()}
          activeOpacity={0.7}>
          <Text style={styles.toolButtonText}>Forward ›</Text>
        </TouchableOpacity>
        <TouchableOpacity
          testID="webdemo.refresh"
          style={styles.toolButton}
          onPress={() => webViewRef.current?.reload()}
          activeOpacity={0.7}>
          <Text style={styles.toolButtonText}>⟳ Reload</Text>
        </TouchableOpacity>
      </View>

      <WebView
        ref={webViewRef}
        testID="webdemo.webview"
        source={{ uri: 'https://example.com' }}
        style={styles.webview}
        javaScriptEnabled
        domStorageEnabled
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  toolbar: {
    flexDirection: 'row',
    backgroundColor: '#fff',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
    paddingHorizontal: 8,
    paddingVertical: 6,
    gap: 4,
  },
  toolButton: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 6,
    backgroundColor: '#f0f0f0',
  },
  toolButtonText: {
    fontSize: 13,
    color: '#007AFF',
    fontWeight: '500',
  },
  webview: {
    flex: 1,
  },
});
