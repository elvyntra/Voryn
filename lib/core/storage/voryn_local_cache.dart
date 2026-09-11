import 'package:shared_preferences/shared_preferences.dart';

class VorynLocalCache {
  VorynLocalCache(this._preferences);

  final SharedPreferences _preferences;

  static Future<VorynLocalCache> create() async {
    return VorynLocalCache(await SharedPreferences.getInstance());
  }

  String? readString(String key) => _preferences.getString(key);

  Future<bool> writeString(String key, String value) =>
      _preferences.setString(key, value);

  bool contains(String key) => _preferences.containsKey(key);

  Future<bool> remove(String key) => _preferences.remove(key);
}
