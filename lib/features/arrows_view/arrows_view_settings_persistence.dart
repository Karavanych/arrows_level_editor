import 'package:shared_preferences/shared_preferences.dart';

class ArrowsViewPersistedSettings {
  const ArrowsViewPersistedSettings({
    required this.isColoredMode,
    required this.thicknessScale,
    required this.backgroundColorHexArgb,
    required this.exportWidthText,
    required this.exportHeightText,
    required this.animationIntervalText,
    required this.flightSpeedText,
  });

  final bool isColoredMode;
  final double thicknessScale;
  final String backgroundColorHexArgb;
  final String exportWidthText;
  final String exportHeightText;
  final String animationIntervalText;
  final String flightSpeedText;
}

class ArrowsViewSettingsPersistence {
  ArrowsViewSettingsPersistence({SharedPreferences? preferences})
    : _preferencesFuture = preferences == null
          ? SharedPreferences.getInstance()
          : Future<SharedPreferences>.value(preferences);

  static const String _isColoredModeKey = 'arrows_view.settings.is_colored_mode';
  static const String _thicknessScaleKey = 'arrows_view.settings.thickness_scale';
  static const String _backgroundColorHexKey =
      'arrows_view.settings.background_color_hex_argb';
  static const String _exportWidthTextKey = 'arrows_view.settings.export_width';
  static const String _exportHeightTextKey = 'arrows_view.settings.export_height';
  static const String _animationIntervalTextKey =
      'arrows_view.settings.animation_interval';
  static const String _flightSpeedTextKey = 'arrows_view.settings.flight_speed';

  final Future<SharedPreferences> _preferencesFuture;

  Future<ArrowsViewPersistedSettings> load({
    required bool defaultIsColoredMode,
    required double defaultThicknessScale,
    required double minThicknessScale,
    required double maxThicknessScale,
    required String defaultBackgroundColorHexArgb,
    required String defaultExportWidthText,
    required String defaultExportHeightText,
    required String defaultAnimationIntervalText,
    required String defaultFlightSpeedText,
  }) async {
    final preferences = await _preferencesFuture;
    final storedThickness = preferences.getDouble(_thicknessScaleKey);
    final thicknessScale =
        (storedThickness ?? defaultThicknessScale)
            .clamp(minThicknessScale, maxThicknessScale)
            .toDouble();

    final colorHex = _isValidHexArgb(preferences.getString(_backgroundColorHexKey))
        ? preferences.getString(_backgroundColorHexKey)!
        : defaultBackgroundColorHexArgb;

    final widthText = _isValidPositiveInt(preferences.getString(_exportWidthTextKey))
        ? preferences.getString(_exportWidthTextKey)!
        : defaultExportWidthText;
    final heightText =
        _isValidPositiveInt(preferences.getString(_exportHeightTextKey))
        ? preferences.getString(_exportHeightTextKey)!
        : defaultExportHeightText;
    final intervalText =
        _isValidPositiveDouble(preferences.getString(_animationIntervalTextKey))
        ? preferences.getString(_animationIntervalTextKey)!
        : defaultAnimationIntervalText;
    final speedText =
        _isValidPositiveDouble(preferences.getString(_flightSpeedTextKey))
        ? preferences.getString(_flightSpeedTextKey)!
        : defaultFlightSpeedText;

    return ArrowsViewPersistedSettings(
      isColoredMode:
          preferences.getBool(_isColoredModeKey) ?? defaultIsColoredMode,
      thicknessScale: thicknessScale,
      backgroundColorHexArgb: colorHex,
      exportWidthText: widthText,
      exportHeightText: heightText,
      animationIntervalText: intervalText,
      flightSpeedText: speedText,
    );
  }

  Future<void> save(ArrowsViewPersistedSettings settings) async {
    final preferences = await _preferencesFuture;
    await preferences.setBool(_isColoredModeKey, settings.isColoredMode);
    await preferences.setDouble(_thicknessScaleKey, settings.thicknessScale);
    await preferences.setString(
      _backgroundColorHexKey,
      settings.backgroundColorHexArgb,
    );
    await preferences.setString(_exportWidthTextKey, settings.exportWidthText);
    await preferences.setString(_exportHeightTextKey, settings.exportHeightText);
    await preferences.setString(
      _animationIntervalTextKey,
      settings.animationIntervalText,
    );
    await preferences.setString(_flightSpeedTextKey, settings.flightSpeedText);
  }

  bool _isValidPositiveInt(String? raw) {
    final parsed = int.tryParse(raw ?? '');
    return parsed != null && parsed > 0;
  }

  bool _isValidPositiveDouble(String? raw) {
    final parsed = double.tryParse(raw ?? '');
    return parsed != null && parsed > 0;
  }

  bool _isValidHexArgb(String? raw) {
    if (raw == null || raw.length != 8) {
      return false;
    }
    return int.tryParse(raw, radix: 16) != null;
  }
}
