import React, { useEffect } from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { AppReveal, AppRevealFetchInterceptor, createNavigationListener } from 'react-native-appreveal';

import { LoginScreen } from './screens/LoginScreen';
import { OrdersScreen } from './screens/OrdersScreen';
import { OrderDetailScreen } from './screens/OrderDetailScreen';
import { CatalogScreen } from './screens/CatalogScreen';
import { ProfileScreen } from './screens/ProfileScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { WebViewScreen } from './screens/WebViewScreen';
import { ExampleNetworkClient } from './services/ExampleNetworkClient';
import { ExampleState } from './services/ExampleState';

import type {
  RootStackParamList,
  OrdersStackParamList,
  CatalogStackParamList,
  ProfileStackParamList,
  TabParamList,
} from './navigation/types';

// ─── Stacks ───────────────────────────────────────────────────────────────────

const RootStack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator<TabParamList>();
const OrdersStack = createNativeStackNavigator<OrdersStackParamList>();
const CatalogStack = createNativeStackNavigator<CatalogStackParamList>();
const ProfileStack = createNativeStackNavigator<ProfileStackParamList>();

function OrdersNavigator() {
  return (
    <OrdersStack.Navigator>
      <OrdersStack.Screen
        name="OrdersList"
        component={OrdersScreen}
        options={{ title: 'Orders' }}
      />
      <OrdersStack.Screen
        name="OrderDetail"
        component={OrderDetailScreen}
        options={({ route }) => ({ title: route.params.order.id })}
      />
    </OrdersStack.Navigator>
  );
}

function CatalogNavigator() {
  return (
    <CatalogStack.Navigator>
      <CatalogStack.Screen
        name="CatalogList"
        component={CatalogScreen}
        options={{ title: 'Catalog' }}
      />
    </CatalogStack.Navigator>
  );
}

function ProfileNavigator() {
  return (
    <ProfileStack.Navigator>
      <ProfileStack.Screen
        name="Profile"
        component={ProfileScreen}
        options={{ title: 'Profile' }}
      />
    </ProfileStack.Navigator>
  );
}

function TabNavigator() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: '#007AFF',
      }}>
      <Tab.Screen
        name="Orders"
        component={OrdersNavigator}
        options={{ tabBarLabel: 'Orders' }}
      />
      <Tab.Screen
        name="Catalog"
        component={CatalogNavigator}
        options={{ tabBarLabel: 'Catalog' }}
      />
      <Tab.Screen
        name="Profile"
        component={ProfileNavigator}
        options={{ tabBarLabel: 'Profile' }}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ tabBarLabel: 'Settings', headerShown: true, title: 'Settings' }}
      />
      <Tab.Screen
        name="Web View"
        component={WebViewScreen}
        options={{ tabBarLabel: 'Web', headerShown: true, title: 'Web View' }}
      />
    </Tab.Navigator>
  );
}

// ─── Root ─────────────────────────────────────────────────────────────────────

export default function App() {
  const navListener = createNavigationListener();

  useEffect(() => {
    if (__DEV__) {
      AppReveal.start();
      AppRevealFetchInterceptor.install();

      // Push feature flags on startup
      AppReveal.setFeatureFlags(ExampleState.instance.featureFlags());

      // Simulate launch API calls
      ExampleNetworkClient.instance.simulateLaunchCalls();
    }
  }, []);

  return (
    <SafeAreaProvider>
      <NavigationContainer
        ref={navListener.ref}
        onStateChange={navListener.onStateChange}>
        <RootStack.Navigator screenOptions={{ headerShown: false }}>
          <RootStack.Screen name="Auth" component={LoginScreen} />
          <RootStack.Screen name="Main" component={TabNavigator} />
        </RootStack.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}
