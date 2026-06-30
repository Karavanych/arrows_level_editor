Place desktop ffmpeg binaries here before packaging builds.

Required source paths:
- macOS: `third_party/ffmpeg/macos/ffmpeg`
- Windows: `third_party/ffmpeg/windows/ffmpeg.exe`

Runtime/bundled destinations:
- macOS app bundle: `arrows_level_editor.app/Contents/MacOS/ffmpeg`
- Windows release output: next to `arrows_level_editor.exe` as `ffmpeg.exe`

Builds fail with clear errors if required source binaries are missing.
