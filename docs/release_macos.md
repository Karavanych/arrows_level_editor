# macOS Release Notes

## Source binary location (repo)
- Place the bundled ffmpeg source binary at:
  `third_party/ffmpeg/macos/ffmpeg`
- Make sure it is executable:
  `chmod +x third_party/ffmpeg/macos/ffmpeg`

## Build integration
- During macOS build, Xcode now copies ffmpeg automatically from:
  `third_party/ffmpeg/macos/ffmpeg`
- Into the app bundle at:
  `arrows_level_editor.app/Contents/MacOS/ffmpeg`
- If source ffmpeg is missing, build fails with a clear error.

## Final bundled path
For `flutter build macos --release` output:
- `build/macos/Build/Products/Release/arrows_level_editor.app/Contents/MacOS/ffmpeg`
