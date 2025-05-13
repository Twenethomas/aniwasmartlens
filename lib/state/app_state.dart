import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  final SharedPreferences prefs;

  AppState(this.prefs);

  /// Whether onboarding has completed
  bool get onboardingComplete => prefs.getBool('onboardingComplete') ?? false;

  /// Mark onboarding as done
  Future<void> completeOnboarding() async {
    await prefs.setBool('onboardingComplete', true);
    notifyListeners();
  }
}
