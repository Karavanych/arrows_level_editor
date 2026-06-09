import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaletteSettingsService {
  PaletteSettingsService({SharedPreferences? preferences})
    : _preferencesFuture = preferences == null
          ? SharedPreferences.getInstance()
          : Future<SharedPreferences>.value(preferences);

  static const String _paletteKey = 'editor.palette.colors';

  final Future<SharedPreferences> _preferencesFuture;

  Future<List<Color>?> loadPaletteColors({required int expectedLength}) async {
    final preferences = await _preferencesFuture;
    final raw = preferences.getStringList(_paletteKey);
    if (raw == null || raw.length != expectedLength) {
      return null;
    }

    final colors = <Color>[];
    for (final entry in raw) {
      final parsed = int.tryParse(entry);
      if (parsed == null) {
        return null;
      }
      colors.add(Color(parsed));
    }
    return colors;
  }

  Future<void> savePaletteColors(List<Color> colors) async {
    final preferences = await _preferencesFuture;
    final encoded = colors
        .map((color) => color.toARGB32().toString())
        .toList(growable: false);
    await preferences.setStringList(_paletteKey, encoded);
  }
}
