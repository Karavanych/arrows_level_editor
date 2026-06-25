import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:arrows_level_editor/features/editor/persistence/model/alevelpack_models.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ALevelPackStorageService {
  ALevelPackStorageService();

  static const String _formatId = 'arrows-level-pack';
  static const int _formatVersion = 1;
  static const String _defaultPackName = 'main-pack';
  static const String _defaultPackFileName = 'main.alevelpack';

  Future<File> getDefaultPackFile() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final packsDir = Directory(p.join(appSupportDir.path, 'packs'));
    if (!await packsDir.exists()) {
      await packsDir.create(recursive: true);
    }
    return File(p.join(packsDir.path, _defaultPackFileName));
  }

  Future<ALevelPackDocument> loadOrCreateDefaultPack({
    required List<Color> paletteColors,
  }) async {
    final file = await getDefaultPackFile();
    return loadOrCreatePack(file: file, paletteColors: paletteColors);
  }

  Future<ALevelPackDocument> loadOrCreatePack({
    required File file,
    required List<Color> paletteColors,
  }) async {
    if (!await file.exists()) {
      return _emptyPackDocument(paletteColors: paletteColors);
    }
    return loadPack(file);
  }

  Future<ALevelPackDocument> loadPack(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Файл пака не существует', file.path);
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestJson = _readRequiredStringFile(archive, 'manifest.json');
    final paletteJson = _readRequiredStringFile(archive, 'palette.json');
    final manifest = ALevelPackManifest.fromJson(
      jsonDecode(manifestJson) as Map<String, dynamic>,
    );
    final palette = ALevelPackPalette.fromJson(
      jsonDecode(paletteJson) as Map<String, dynamic>,
    );
    _validateManifest(manifest);

    final levels = <ALevelPackLevel>[];
    for (final levelEntry in manifest.levels) {
      levels.add(_readLevel(archive, levelEntry));
    }

    return ALevelPackDocument(
      manifest: manifest,
      palette: palette,
      levels: levels,
    );
  }

  Future<void> savePack({
    required File file,
    required ALevelPackDocument pack,
  }) async {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string('manifest.json', jsonEncode(pack.manifest.toJson())),
    );
    archive.addFile(
      ArchiveFile.string('palette.json', jsonEncode(pack.palette.toJson())),
    );

    for (final level in pack.levels) {
      final levelBasePath = 'levels/${level.id}';
      archive.addFile(
        ArchiveFile(
          '$levelBasePath/board.png',
          level.width * level.height * 4,
          _encodeBoardPng(level),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          '$levelBasePath/meta.json',
          jsonEncode(level.meta.toJson()),
        ),
      );
    }

    final encodedBytes = ZipEncoder().encode(archive);

    final parentDir = Directory(p.dirname(file.path));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
    await file.writeAsBytes(encodedBytes, flush: true);
  }

  ALevelPackDocument buildPackWithUpsertedLevel({
    required ALevelPackDocument source,
    required ALevelPackLevel level,
    String? packName,
    String? lastOpenedLevelId,
  }) {
    final updated = source.upsertLevel(level);
    return ALevelPackDocument(
      manifest: updated.manifest.copyWith(
        name: packName ?? updated.manifest.name,
        lastOpenedLevelId:
            lastOpenedLevelId ?? updated.manifest.lastOpenedLevelId,
      ),
      palette: source.palette,
      levels: updated.levels,
    );
  }

  ALevelPackDocument _emptyPackDocument({required List<Color> paletteColors}) {
    return ALevelPackDocument(
      manifest: const ALevelPackManifest(
        format: _formatId,
        version: _formatVersion,
        name: _defaultPackName,
        levels: [],
        lastOpenedLevelId: null,
      ),
      palette: ALevelPackPalette(
        inactiveColor: const Color(0xFFFFFFFF),
        colors: paletteColors,
      ),
      levels: const [],
    );
  }

  void _validateManifest(ALevelPackManifest manifest) {
    if (manifest.format != _formatId) {
      throw FormatException('Неподдерживаемый формат id: ${manifest.format}');
    }
    if (manifest.version != _formatVersion) {
      throw FormatException(
        'Неподдерживаемая версия формата: ${manifest.version}',
      );
    }
  }

  String _readRequiredStringFile(Archive archive, String path) {
    final entry = archive.findFile(path);
    if (entry == null) {
      throw FormatException('В архиве отсутствует обязательная запись: $path');
    }
    final content = entry.readBytes();
    if (content == null) {
      throw FormatException(
        'Не удалось прочитать байты записи архива: $path',
      );
    }
    return utf8.decode(content);
  }

  ALevelPackLevel _readLevel(Archive archive, ALevelManifestEntry entry) {
    final basePath = entry.path;
    final boardPath = '$basePath/board.png';
    final metaPath = '$basePath/meta.json';

    final boardFile = archive.findFile(boardPath);
    final metaFile = archive.findFile(metaPath);
    if (boardFile == null) {
      throw FormatException('Отсутствует файл поля уровня: $boardPath');
    }
    if (metaFile == null) {
      throw FormatException('Отсутствует файл метаданных уровня: $metaPath');
    }

    final metaBytes = metaFile.readBytes();
    if (metaBytes == null) {
      throw FormatException(
        'Не удалось прочитать байты файла метаданных уровня: $metaPath',
      );
    }
    final boardBytes = boardFile.readBytes();
    if (boardBytes == null) {
      throw FormatException(
        'Не удалось прочитать байты файла поля уровня: $boardPath',
      );
    }

    final meta = ALevelLevelMeta.fromJson(
      jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>,
    );
    final boardImage = img.decodePng(boardBytes);
    if (boardImage == null) {
      throw FormatException(
        'Не удалось декодировать board.png для уровня: ${entry.id}',
      );
    }

    final boardCells = <ALevelBoardCell>[];
    for (var y = 0; y < boardImage.height; y += 1) {
      for (var x = 0; x < boardImage.width; x += 1) {
        final pixel = boardImage.getPixel(x, y);
        final color = Color.fromARGB(
          pixel.a.toInt(),
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
        );
      if (pixel.a.toInt() == 0) {
        boardCells.add(const ALevelBoardCell(isInactive: false, isEmpty: true));
        continue;
      }
        final rgb = color.toARGB32() & 0x00FFFFFF;
        if (rgb == 0x00FFFFFF) {
          boardCells.add(const ALevelBoardCell(isInactive: true));
        } else {
          boardCells.add(ALevelBoardCell(isInactive: false, color: color));
        }
      }
    }

    return ALevelPackLevel(
      id: entry.id,
      width: boardImage.width,
      height: boardImage.height,
      boardCells: boardCells,
      meta: meta,
    );
  }

  Uint8List _encodeBoardPng(ALevelPackLevel level) {
    if (level.boardCells.length != level.width * level.height) {
      throw StateError(
        'Некорректное количество клеток поля для ${level.id}: '
        '${level.boardCells.length}, ожидалось ${level.width * level.height}.',
      );
    }

    final image = img.Image(width: level.width, height: level.height);
    for (var index = 0; index < level.boardCells.length; index += 1) {
      final x = index % level.width;
      final y = index ~/ level.width;
      final cell = level.boardCells[index];
      final color = cell.isInactive
          ? const Color(0xFFFFFFFF)
          : (cell.isEmpty ? const Color(0x00000000) : cell.color);
      if (!cell.isInactive && !cell.isEmpty && color == null) {
        throw StateError(
          'У активной клетки ($x,$y) в ${level.id} отсутствует цвет.',
        );
      }

      final argb = color!.toARGB32();
      image.setPixelRgba(
        x,
        y,
        (argb >> 16) & 0xFF,
        (argb >> 8) & 0xFF,
        argb & 0xFF,
        (argb >> 24) & 0xFF,
      );
    }

    return Uint8List.fromList(img.encodePng(image));
  }
}
