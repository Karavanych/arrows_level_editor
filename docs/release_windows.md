# Windows Release & Installer

## Prerequisites
- Flutter installed and on PATH.
- Visual Studio 2022 build tools / Desktop development with C++ workload for Windows builds.
- Inno Setup 6 installed (ISCC.exe available via PATH or default install location).

## Build steps
From the repository root:
```
powershell -ExecutionPolicy Bypass -File tools/build_windows_installer.ps1
```

## Output
- Installer: `dist/windows/arrows_level_editor-<version>-setup.exe`
- Contents packaged from the Flutter Windows Release output (exe, dlls, data/flutter_assets, plugins).
- Installer is unsigned; Windows SmartScreen may warn. Use "More info" -> "Run anyway".

## Notes
- Version is taken from `pubspec.yaml` (`version:`). Bump it before releasing.
- No code signing is configured; add SignTool later if certificates become available.
