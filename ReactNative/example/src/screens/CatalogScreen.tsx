import React, { useState } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ListRenderItem,
  Alert,
} from 'react-native';
import { useAppRevealScreen } from 'react-native-appreveal';
import { ExampleState } from '../services/ExampleState';

type Product = {
  id: string;
  name: string;
  price: number;
  category: string;
};

const PRODUCTS: Product[] = [
  { id: 'p1', name: 'Wireless Headphones', price: 99.99, category: 'Electronics' },
  { id: 'p2', name: 'Running Shoes', price: 149.0, category: 'Sports' },
  { id: 'p3', name: 'Coffee Maker', price: 79.95, category: 'Kitchen' },
  { id: 'p4', name: 'Yoga Mat', price: 34.99, category: 'Sports' },
  { id: 'p5', name: 'Desk Lamp', price: 45.0, category: 'Home' },
  { id: 'p6', name: 'Water Bottle', price: 24.99, category: 'Sports' },
];

export function CatalogScreen() {
  useAppRevealScreen('catalog', 'Catalog');

  const [addedIds, setAddedIds] = useState<Set<string>>(new Set());

  const addToCart = (product: Product, index: number) => {
    ExampleState.instance.cartItemCount += 1;
    ExampleState.instance.cartItems.push({
      id: product.id,
      name: product.name,
      price: product.price,
      qty: 1,
    });
    setAddedIds(prev => new Set(prev).add(product.id));
    Alert.alert('Added to Cart', `${product.name} added to your cart.`);
  };

  const renderItem: ListRenderItem<Product> = ({ item, index }) => {
    const added = addedIds.has(item.id);
    return (
      <View
        testID={`catalog.product_${index}`}
        style={styles.card}>
        <View style={styles.cardBody}>
          <Text style={styles.productName}>{item.name}</Text>
          <Text style={styles.productCategory}>{item.category}</Text>
          <Text style={styles.productPrice}>${item.price.toFixed(2)}</Text>
        </View>
        <TouchableOpacity
          testID={`catalog.add_to_cart_${index}`}
          style={[styles.addButton, added && styles.addButtonAdded]}
          onPress={() => addToCart(item, index)}
          activeOpacity={0.7}>
          <Text style={styles.addButtonText}>
            {added ? 'Added' : 'Add to Cart'}
          </Text>
        </TouchableOpacity>
      </View>
    );
  };

  return (
    <FlatList
      testID="catalog.grid"
      data={PRODUCTS}
      keyExtractor={item => item.id}
      renderItem={renderItem}
      numColumns={2}
      contentContainerStyle={styles.list}
      columnWrapperStyle={styles.column}
    />
  );
}

const styles = StyleSheet.create({
  list: {
    padding: 12,
    paddingBottom: 40,
    backgroundColor: '#f5f5f5',
  },
  column: {
    justifyContent: 'space-between',
    marginBottom: 12,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 14,
    width: '48.5%',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: '#e0e0e0',
  },
  cardBody: {
    marginBottom: 10,
  },
  productName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    marginBottom: 4,
  },
  productCategory: {
    fontSize: 12,
    color: '#888',
    marginBottom: 6,
  },
  productPrice: {
    fontSize: 16,
    fontWeight: '700',
    color: '#007AFF',
  },
  addButton: {
    backgroundColor: '#007AFF',
    borderRadius: 6,
    paddingVertical: 8,
    alignItems: 'center',
  },
  addButtonAdded: {
    backgroundColor: '#38a169',
  },
  addButtonText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
  },
});
