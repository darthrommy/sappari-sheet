; Inno Setup script for negadice (Windows desktop).
;
; Not meant to be compiled by hand — run installer\build-installer.ps1, which
; parses the version out of pubspec.yaml, stages the Visual C++ runtime DLLs
; beside the executable, and passes the defines below to ISCC.
;
; Per-user install by design: PrivilegesRequired=lowest means no UAC prompt and
; no administrator rights, and {autopf} then resolves to
; %LOCALAPPDATA%\Programs rather than C:\Program Files.

#define AppName "negadice"
#define AppPublisher "negadice"
#define AppExeName "negadice.exe"

; Supplied by build-installer.ps1; the fallbacks only exist so opening this
; file in the Inno IDE does not error out.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId — it is how Windows recognises an existing install and
; upgrades it in place instead of stacking a second copy.
AppId={{22523090-59D6-48B9-A1D5-9D8C11F26A02}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName} {#AppVersion}
OutputDir=Output
OutputBaseFilename=negadice-setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app is x64-only, matching `flutter build windows --release`.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
; One program group is pointless for a single-app install.
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release tree: negadice.exe, flutter_windows.dll, the plugin
; DLLs, and data\ (app.so, icudtl.dat, flutter_assets\). The layout must be
; preserved — the engine resolves data\ relative to the executable.
;
; build-installer.ps1 has already copied msvcp140.dll, vcruntime140.dll and
; vcruntime140_1.dll into this directory, so they are picked up by the wildcard.
; Shipping them app-local means the end user needs no VC++ redistributable.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
