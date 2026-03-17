import React, { useState } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  TextInput,
  StyleSheet,
  ListRenderItem,
} from 'react-native';
import { useAppRevealScreen } from 'react-native-appreveal';
import type { OrdersListScreenProps, OrderItem } from '../navigation/types';

const MOCK_ORDERS: OrderItem[] = [
  {
    id: 'ORD-001',
    date: '2024-03-01',
    status: 'Delivered',
    total: 149.99,
    items: [
      { name: 'Wireless Headphones', qty: 1, price: 99.99 },
      { name: 'Water Bottle', qty: 2, price: 24.99 },
    ],
  },
  {
    id: 'ORD-002',
    date: '2024-03-08',
    status: 'Shipped',
    total: 79.95,
    items: [{ name: 'Running Shoes', qty: 1, price: 79.95 }],
  },
  {
    id: 'ORD-003',
    date: '2024-03-12',
    status: 'Processing',
    total: 299.0,
    items: [{ name: 'Smart Watch', qty: 1, price: 299.0 }],
  },
  {
    id: 'ORD-004',
    date: '2024-03-15',
    status: 'Pending',
    total: 54.98,
    items: [
      { name: 'Desk Lamp', qty: 1, price: 45.0 },
      { name: 'Yoga Mat', qty: 0, price: 34.99 },
    ],
  },
  {
    id: 'ORD-005',
    date: '2024-02-20',
    status: 'Delivered',
    total: 89.0,
    items: [{ name: 'Backpack', qty: 1, price: 89.0 }],
  },
];

function statusColor(status: string): string {
  switch (status) {
    case 'Delivered':
      return '#38a169';
    case 'Shipped':
      return '#007AFF';
    case 'Processing':
      return '#d97706';
    default:
      return '#718096';
  }
}

export function OrdersScreen({ navigation }: OrdersListScreenProps) {
  useAppRevealScreen('orders.list', 'Orders');

  const [search, setSearch] = useState('');

  const filtered = search.trim().length > 0
    ? MOCK_ORDERS.filter(
        o =>
          o.id.toLowerCase().includes(search.toLowerCase()) ||
          o.status.toLowerCase().includes(search.toLowerCase()),
      )
    : MOCK_ORDERS;

  const renderItem: ListRenderItem<OrderItem> = ({ item, index }) => (
    <TouchableOpacity
      testID={`orders.cell_${index}`}
      style={styles.row}
      onPress={() => navigation.navigate('OrderDetail', { order: item })}
      activeOpacity={0.7}>
      <View style={styles.rowLeft}>
        <Text style={styles.orderId}>{item.id}</Text>
        <Text style={styles.orderDate}>{item.date}</Text>
      </View>
      <View style={styles.rowRight}>
        <Text style={styles.orderTotal}>${item.total.toFixed(2)}</Text>
        <Text style={[styles.orderStatus, { color: statusColor(item.status) }]}>
          {item.status}
        </Text>
      </View>
    </TouchableOpacity>
  );

  return (
    <View style={styles.container}>
      <TextInput
        testID="orders.search"
        style={styles.search}
        placeholder="Search orders…"
        placeholderTextColor="#999"
        value={search}
        onChangeText={setSearch}
      />
      <FlatList
        testID="orders.list_table"
        data={filtered}
        keyExtractor={item => item.id}
        renderItem={renderItem}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        contentContainerStyle={styles.list}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  search: {
    margin: 12,
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
    color: '#333',
  },
  list: {
    paddingBottom: 20,
  },
  row: {
    backgroundColor: '#fff',
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  rowLeft: {},
  rowRight: {
    alignItems: 'flex-end',
  },
  orderId: {
    fontSize: 15,
    fontWeight: '600',
    color: '#333',
  },
  orderDate: {
    fontSize: 13,
    color: '#888',
    marginTop: 2,
  },
  orderTotal: {
    fontSize: 15,
    fontWeight: '600',
    color: '#333',
  },
  orderStatus: {
    fontSize: 13,
    marginTop: 2,
    fontWeight: '500',
  },
  separator: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: '#ddd',
    marginLeft: 16,
  },
});
