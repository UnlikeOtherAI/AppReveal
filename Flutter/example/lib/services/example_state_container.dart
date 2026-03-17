import 'package:appreveal/appreveal.dart';

class ExampleStateContainer implements StateProviding {
  static final instance = ExampleStateContainer._();
  ExampleStateContainer._();

  bool isLoggedIn = false;
  String userEmail = '';
  String userName = '';
  String selectedTab = 'catalog';
  int cartItemCount = 0;
  DateTime? lastSyncDate;

  @override
  Map<String, dynamic> snapshot() => {
    'isLoggedIn': isLoggedIn,
    'userEmail': userEmail,
    'userName': userName,
    'selectedTab': selectedTab,
    'cartItemCount': cartItemCount,
    'lastSyncDate': lastSyncDate?.toIso8601String(),
  };
}
