import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'package:arrows_level_editor/features/arrows_view/arrows_view_level_snapshot.dart';

class ArrowsViewWindowLauncher {
  static Future<void> open(ArrowsViewLevelSnapshot snapshot) async {
    if (!_isDesktop) {
      return;
    }

    final existing = await _findOpenArrowsViewWindow();
    if (existing != null) {
      await existing.show();
      return;
    }

    final payload = jsonEncode(<String, dynamic>{
      'windowType': 'arrows_view',
      'levelSnapshot': snapshot.toJson(),
    });
    await WindowController.create(
      WindowConfiguration(arguments: payload, hiddenAtLaunch: true),
    );
  }

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static Future<WindowController?> _findOpenArrowsViewWindow() async {
    final windows = await WindowController.getAll();
    for (final window in windows) {
      final arguments = window.arguments;
      if (arguments.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(arguments);
        if (decoded is Map<String, dynamic> &&
            decoded['windowType'] == 'arrows_view') {
          return window;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
