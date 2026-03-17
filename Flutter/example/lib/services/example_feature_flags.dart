import 'package:appreveal/appreveal.dart';

class ExampleFeatureFlags implements FeatureFlagProviding {
  static final instance = ExampleFeatureFlags._();
  ExampleFeatureFlags._();

  @override
  Map<String, dynamic> allFlags() => {
    'newCheckoutFlow': true,
    'recommendationsEnabled': true,
    'darkModeSupport': false,
    'pushNotifications': true,
    'analyticsV2': false,
    'inAppReview': true,
    'betaFeatures': false,
    'maintenanceMode': false,
  };
}
