import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { BottomTabScreenProps } from '@react-navigation/bottom-tabs';

// ─── Auth stack ───────────────────────────────────────────────────────────────

export type AuthStackParamList = {
  Login: undefined;
};

// ─── Orders stack ─────────────────────────────────────────────────────────────

export type OrdersStackParamList = {
  OrdersList: undefined;
  OrderDetail: { order: OrderItem };
};

export type OrderItem = {
  id: string;
  date: string;
  status: string;
  total: number;
  items: Array<{ name: string; qty: number; price: number }>;
};

// ─── Catalog stack ────────────────────────────────────────────────────────────

export type CatalogStackParamList = {
  CatalogList: undefined;
};

// ─── Profile stack ────────────────────────────────────────────────────────────

export type ProfileStackParamList = {
  Profile: undefined;
  EditProfile: undefined;
};

// ─── Tab navigator ────────────────────────────────────────────────────────────

export type TabParamList = {
  Orders: undefined;
  Catalog: undefined;
  Profile: undefined;
  Settings: undefined;
  'Web View': undefined;
};

// ─── Root ─────────────────────────────────────────────────────────────────────

export type RootStackParamList = {
  Auth: undefined;
  Main: undefined;
};

// ─── Screen props helpers ─────────────────────────────────────────────────────

export type OrdersListScreenProps = NativeStackScreenProps<OrdersStackParamList, 'OrdersList'>;
export type OrderDetailScreenProps = NativeStackScreenProps<OrdersStackParamList, 'OrderDetail'>;
export type CatalogScreenProps = NativeStackScreenProps<CatalogStackParamList, 'CatalogList'>;
export type ProfileScreenProps = NativeStackScreenProps<ProfileStackParamList, 'Profile'>;
export type EditProfileScreenProps = NativeStackScreenProps<ProfileStackParamList, 'EditProfile'>;
