import 'package:shared_preferences/shared_preferences.dart';

class PrefsUtils {
  static Future<int?> getPrevLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('prevLevel');
  }

  static Future<void> setPrevLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prevLevel', level);
  }
}