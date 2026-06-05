import 'package:flutter/material.dart';

class ALevelPackManifest {
  const ALevelPackManifest({
    required this.format,
    required this.version,
    required this.name,
    required this.levels,
    this.lastOpenedLevelId,
  });

  final String format;
  final int version;
  final String name;
  final List<ALevelManifestEntry> levels;
  final String? lastOpenedLevelId;

  Map<String, Object?> toJson() {
    return {
      'format': format,
      'version': version,
      'name': name,
      'levels': levels.map((entry) => entry.toJson()).toList(),
      if (lastOpenedLevelId != null) 'lastOpenedLevelId': lastOpenedLevelId,
    };
  }

  factory ALevelPackManifest.fromJson(Map<String, dynamic> json) {
    final levelsJson = (json['levels'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();

    return ALevelPackManifest(
      format: json['format'] as String? ?? '',
      version: json['version'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      levels: levelsJson.map(ALevelManifestEntry.fromJson).toList(),
      lastOpenedLevelId: json['lastOpenedLevelId'] as String?,
    );
  }

  ALevelPackManifest copyWith({
    String? format,
    int? version,
    String? name,
    List<ALevelManifestEntry>? levels,
    String? lastOpenedLevelId,
    bool clearLastOpenedLevelId = false,
  }) {
    return ALevelPackManifest(
      format: format ?? this.format,
      version: version ?? this.version,
      name: name ?? this.name,
      levels: levels ?? this.levels,
      lastOpenedLevelId: clearLastOpenedLevelId
          ? null
          : (lastOpenedLevelId ?? this.lastOpenedLevelId),
    );
  }
}

class ALevelManifestEntry {
  const ALevelManifestEntry({required this.id, required this.path});

  final String id;
  final String path;

  Map<String, Object?> toJson() {
    return {'id': id, 'path': path};
  }

  factory ALevelManifestEntry.fromJson(Map<String, dynamic> json) {
    return ALevelManifestEntry(
      id: json['id'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class ALevelPackPalette {
  const ALevelPackPalette({required this.inactiveColor, required this.colors});

  final Color inactiveColor;
  final List<Color> colors;

  Map<String, Object?> toJson() {
    return {
      'inactiveColor': _colorToRgbHex(inactiveColor),
      'colors': colors.map(_colorToRgbHex).toList(),
    };
  }

  factory ALevelPackPalette.fromJson(Map<String, dynamic> json) {
    final colors = (json['colors'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map(_colorFromHex)
        .toList();

    return ALevelPackPalette(
      inactiveColor: _colorFromHex(
        json['inactiveColor'] as String? ?? '#FFFFFF',
      ),
      colors: colors,
    );
  }
}

class ALevelStartPoint {
  const ALevelStartPoint({required this.x, required this.y});

  final int x;
  final int y;

  Map<String, Object?> toJson() {
    return {'x': x, 'y': y};
  }

  factory ALevelStartPoint.fromJson(Map<String, dynamic> json) {
    return ALevelStartPoint(
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
    );
  }
}

class ALevelLevelMeta {
  const ALevelLevelMeta({required this.startPoints});

  final List<ALevelStartPoint> startPoints;

  Map<String, Object?> toJson() {
    return {'startPoints': startPoints.map((point) => point.toJson()).toList()};
  }

  factory ALevelLevelMeta.fromJson(Map<String, dynamic> json) {
    final startPoints = (json['startPoints'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ALevelStartPoint.fromJson)
        .toList();

    return ALevelLevelMeta(startPoints: startPoints);
  }
}

class ALevelBoardCell {
  const ALevelBoardCell({required this.isInactive, this.color});

  final bool isInactive;
  final Color? color;
}

class ALevelPackLevel {
  const ALevelPackLevel({
    required this.id,
    required this.width,
    required this.height,
    required this.boardCells,
    required this.meta,
  });

  final String id;
  final int width;
  final int height;
  final List<ALevelBoardCell> boardCells;
  final ALevelLevelMeta meta;
}

class ALevelPackDocument {
  const ALevelPackDocument({
    required this.manifest,
    required this.palette,
    required this.levels,
  });

  final ALevelPackManifest manifest;
  final ALevelPackPalette palette;
  final List<ALevelPackLevel> levels;

  ALevelPackDocument upsertLevel(ALevelPackLevel level) {
    final nextLevels = <ALevelPackLevel>[
      ...levels.where((existing) => existing.id != level.id),
      level,
    ];

    final orderedManifestLevels = <ALevelManifestEntry>[
      ...manifest.levels.where((entry) => entry.id != level.id),
      ALevelManifestEntry(id: level.id, path: 'levels/${level.id}'),
    ];

    return ALevelPackDocument(
      manifest: manifest.copyWith(levels: orderedManifestLevels),
      palette: palette,
      levels: nextLevels,
    );
  }

  ALevelPackDocument ensureLevelEntry(String levelId) {
    final hasEntry = manifest.levels.any((entry) => entry.id == levelId);
    if (hasEntry) {
      return this;
    }
    return ALevelPackDocument(
      manifest: manifest.copyWith(
        levels: [
          ...manifest.levels,
          ALevelManifestEntry(id: levelId, path: 'levels/$levelId'),
        ],
      ),
      palette: palette,
      levels: levels,
    );
  }

  ALevelPackDocument removeLevel(String levelId) {
    return ALevelPackDocument(
      manifest: manifest.copyWith(
        levels: manifest.levels.where((entry) => entry.id != levelId).toList(),
      ),
      palette: palette,
      levels: levels.where((level) => level.id != levelId).toList(),
    );
  }
}

String _colorToRgbHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color _colorFromHex(String value) {
  final normalized = value.replaceAll('#', '');
  if (normalized.length == 6) {
    return Color(int.parse('FF$normalized', radix: 16));
  }
  if (normalized.length == 8) {
    return Color(int.parse(normalized, radix: 16));
  }
  throw FormatException('Unsupported color format: $value');
}
