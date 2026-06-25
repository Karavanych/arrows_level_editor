import 'package:shared_preferences/shared_preferences.dart';

class ActivePackSettingsService {
  ActivePackSettingsService({SharedPreferences? preferences})
    : _preferencesFuture = preferences == null
          ? SharedPreferences.getInstance()
          : Future<SharedPreferences>.value(preferences);

  static const String _activePackPathKey = 'editor.active.pack.path';

  final Future<SharedPreferences> _preferencesFuture;

  Future<String?> loadLastOpenedPackFilePath() async {
    final preferences = await _preferencesFuture;
    return preferences.getString(_activePackPathKey);
  }

  Future<void> saveLastOpenedPackFilePath(String path) async {
    final preferences = await _preferencesFuture;
    await preferences.setString(_activePackPathKey, path);
  }

  Future<void> clearLastOpenedPackFilePath() async {
    final preferences = await _preferencesFuture;
    await preferences.remove(_activePackPathKey);
  }
}
