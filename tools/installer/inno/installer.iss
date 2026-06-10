#define AppName "arrows_level_editor"
#define AppExeName "arrows_level_editor.exe"

#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

#ifndef SourceDir
#error SourceDir must be defined, e.g. /DSourceDir="C:\path\to\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
#define OutputDir "dist\\windows"
#endif

#define OutputBaseName "arrows_level_editor-" + AppVersion + "-setup"

[Setup]
AppId={{1CB3B233-83B2-4E82-B80E-4B546AA6C9D5}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=no
DisableDirPage=no
UninstallDisplayIcon={app}\{#AppExeName}
UsePreviousAppDir=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"
Name: "{commondesktop}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent unchecked
