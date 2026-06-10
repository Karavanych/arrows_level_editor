## Inno Setup Installer

This folder contains the Inno Setup script used to build the Windows installer.

- `installer.iss` - installer definition. Expects the release build output as `SourceDir` and writes installer binaries to `OutputDir`.

You normally do not run `ISCC.exe` manually; use `tools/build_windows_installer.ps1` from the repo root, which:
1) Builds a Flutter Windows release.
2) Locates the release output folder.
3) Calls Inno Setup to produce `dist/windows/<AppName>-<Version>-setup.exe`.

If you must call `ISCC.exe` manually:
```
iscc.exe /DAppVersion=1.0.0 /DSourceDir="C:\path\to\build\windows\x64\runner\Release" /DOutputDir="C:\path\to\dist\windows" installer.iss
```
