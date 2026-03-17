import React from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import { useAppRevealScreen } from 'react-native-appreveal';
import type { OrderDetailScreenProps } from '../navigation/types';

export function OrderDetailScreen({ route }: OrderDetailScreenProps) {
  const { order } = route.params;
  useAppRevealScreen('order.detail', `Order ${order.id}`);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.card}>
        <Row label="Order ID" value={order.id} testID="order.id" />
        <Row label="Date" value={order.date} testID="order.date" />
        <Row label="Status" value={order.status} testID="order.status" />
        <Row label="Total" value={`$${order.total.toFixed(2)}`} testID="order.total" />
      </View>

      <Text style={styles.sectionTitle}>Items</Text>
      <View style={styles.card}>
        {order.items.map((item, i) => (
          <View key={i} style={[styles.itemRow, i > 0 && styles.itemBorder]}>
            <Text style={styles.itemName} testID={`order.item_${i}`}>
              {item.name}
            </Text>
            <Text style={styles.itemMeta}>
              {item.qty} × ${item.price.toFixed(2)}
            </Text>
          </View>
        ))}
      </View>

      <TouchableOpacity
        testID="order.track"
        style={styles.button}
        activeOpacity={0.8}
        onPress={() => {}}>
        <Text style={styles.buttonText}>Track Package</Text>
      </TouchableOpacity>

      <TouchableOpacity
        testID="order.reorder"
        style={[styles.button, styles.buttonSecondary]}
        activeOpacity={0.8}
        onPress={() => {}}>
        <Text style={styles.buttonTextSecondary}>Reorder</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

function Row({
  label,
  value,
  testID,
}: {
  label: string;
  value: string;
  testID: string;
}) {
  return (
    <View style={styles.row} testID={testID}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
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
  card: {
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 16,
    marginBottom: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#e0e0e0',
  },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#888',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
    marginLeft: 4,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#f0f0f0',
  },
  rowLabel: {
    fontSize: 15,
    color: '#666',
  },
  rowValue: {
    fontSize: 15,
    fontWeight: '500',
    color: '#333',
  },
  itemRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 10,
  },
  itemBorder: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#f0f0f0',
  },
  itemName: {
    fontSize: 15,
    color: '#333',
    flex: 1,
  },
  itemMeta: {
    fontSize: 14,
    color: '#888',
  },
  button: {
    backgroundColor: '#007AFF',
    borderRadius: 10,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: 12,
  },
  buttonSecondary: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#007AFF',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  buttonTextSecondary: {
    color: '#007AFF',
    fontSize: 16,
    fontWeight: '600',
  },
});
