; ============================================================
;  Signtech File Sharing — Windows Setup (Inno Setup 6)
;  GitHub Actions-e Flutter Windows build er por ei script
;  diye purno installer (Setup.exe) toiri hoy.
;  Version bodlate chaile pubspec.yaml er version bodlao —
;  workflow ISCC-ke /DAPP_VERSION hisebe pathiye dey.
; ============================================================

#define AppName "Signtech File Sharing"
#ifndef APP_VERSION
#define APP_VERSION "1.0.0"
#endif
#define AppVersion APP_VERSION
#define AppPublisher "Signtech Digital"
#define AppExeName "signtech_file_sharing.exe"

[Setup]
AppId={{8F3A21C7-4D5E-4A9B-9C1F-2E6B7A8D5C10}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\installer
OutputBaseFilename=SigntechFileSharing-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=app_icon.ico
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop shortcut toiri koro"; GroupDescription: "Additional icons:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Signtech File Sharing chalao"; Flags: nowait postinstall skipifsilent
