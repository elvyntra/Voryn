import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VorynThemeController extends ChangeNotifier {
  VorynThemeController();
  static VorynThemeController? current;
  static const _key = 'voryn_theme_mode';
  SharedPreferences? _preferences;
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    current = this;
    _mode = switch (preferences.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await _preferences?.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
