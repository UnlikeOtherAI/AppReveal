import 'package:appreveal/appreveal.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/example_state_container.dart';
import 'services/example_router.dart';
import 'services/example_feature_flags.dart';
import 'services/example_network_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Start AppReveal — no-ops in release builds
  AppReveal.start();

  // Register optional providers
  AppReveal.registerStateProvider(ExampleStateContainer.instance);
  AppReveal.registerNavigationProvider(ExampleRouter.instance);
  AppReveal.registerFeatureFlagProvider(ExampleFeatureFlags.instance);
  AppReveal.registerNetworkObservable(ExampleNetworkClient.instance);

  // Simulate some network activity on launch
  ExampleNetworkClient.instance.simulateLaunchCalls();

  runApp(AppReveal.wrap(const ExampleApp()));
}
