import 'package:shared_preferences/shared_preferences.dart';

abstract class SpUtils {
  static late SharedPreferences preferences;
  static Future<void> init() async {
    preferences = await SharedPreferences.getInstance();
  }

  static Set<String> get keys {
    return preferences.getKeys();
  }

  static Future<bool> remove(String key) => preferences.remove(key);

  static Future<bool> setString(String key, String value) => preferences.setString(key, value);
  static Future<bool> setBool(String key, bool value) => preferences.setBool(key, value);
  static Future<bool> setInt(String key, int value) => preferences.setInt(key, value);
  static Future<bool> setDouble(String key, double value) => preferences.setDouble(key, value);

  static String getString(String key) => preferences.getString(key) ?? "";
  static bool getBool(String key) => preferences.getBool(key) ?? false;
  static int getInt(String key) => preferences.getInt(key) ?? 0;
  static double getDouble(String key) => preferences.getDouble(key) ?? 0.0;
}
