import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ArrowsViewExportService {
  Future<Directory> getDefaultExportDirectory() async {
    final appSupportDir = await getApplicationSupportDirectory();
    final exportDir = Directory(
      p.join(appSupportDir.path, 'exports', 'arrows_view'),
    );
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  String buildFileName([DateTime? now]) {
    final value = now ?? DateTime.now();
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return 'arrows_view_$yyyy$mm${dd}_$hh$min$ss.png';
  }

  String buildVideoFileName([DateTime? now]) {
    final value = now ?? DateTime.now();
    final yyyy = value.year.toString().padLeft(4, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final ss = value.second.toString().padLeft(2, '0');
    return 'arrows_view_$yyyy$mm${dd}_$hh$min$ss.mp4';
  }

  Future<File> savePng(Uint8List bytes) async {
    final directory = await getDefaultExportDirectory();
    final file = File(p.join(directory.path, buildFileName()));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> createVideoOutputFile() async {
    final directory = await getDefaultExportDirectory();
    return File(p.join(directory.path, buildVideoFileName()));
  }

  Future<void> revealExportFile(File file) async {
    final directory = Directory(file.parent.path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', file.path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [directory.path]);
      return;
    }
    throw UnsupportedError('Reveal is not supported on this platform.');
  }
}
