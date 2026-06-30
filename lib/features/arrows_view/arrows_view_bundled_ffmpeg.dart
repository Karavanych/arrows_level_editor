import 'dart:io';

import 'package:path/path.dart' as p;

class BundledFfmpegInfo {
  const BundledFfmpegInfo({
    required this.executablePath,
    required this.platformLabel,
  });

  final String executablePath;
  final String platformLabel;
}

class BundledFfmpegNotFoundException implements Exception {
  const BundledFfmpegNotFoundException({
    required this.expectedPath,
    required this.platformLabel,
  });

  final String expectedPath;
  final String platformLabel;

  @override
  String toString() {
    return 'Bundled ffmpeg not found for $platformLabel: $expectedPath';
  }
}

BundledFfmpegInfo resolveBundledFfmpeg() {
  if (!Platform.isMacOS && !Platform.isWindows) {
    throw UnsupportedError(
      'MP4 export with bundled ffmpeg is only supported on macOS and Windows.',
    );
  }

  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final ffmpegPath = Platform.isWindows
      ? p.join(executableDirectory, 'ffmpeg.exe')
      : p.join(executableDirectory, 'ffmpeg');
  final ffmpegFile = File(ffmpegPath);
  if (!ffmpegFile.existsSync()) {
    throw BundledFfmpegNotFoundException(
      expectedPath: ffmpegPath,
      platformLabel: Platform.isWindows ? 'Windows' : 'macOS',
    );
  }

  return BundledFfmpegInfo(
    executablePath: ffmpegPath,
    platformLabel: Platform.isWindows ? 'Windows' : 'macOS',
  );
}
