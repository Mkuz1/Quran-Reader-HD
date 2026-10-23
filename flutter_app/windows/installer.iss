; Quran Reader HD for Windows: a per-user installer. It installs into %LOCALAPPDATA%\Programs and the user's
; Start menu, so it never asks for administrator rights. Built by .github/workflows/release.yml:
;   iscc /DAppVersion=1.2.0 /DSourceDir=<flutter Release folder> /DOutputDir=<folder> installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

[Setup]
; Keep this AppId: installing a newer version over an older one relies on it.
AppId={{1D0DFDDF-D3A7-4C71-AEE5-CAE45E522384}
AppName=Quran Reader HD
AppVersion={#AppVersion}
AppVerName=Quran Reader HD {#AppVersion}
AppPublisher=Quran Reader HD
AppPublisherURL=https://github.com/Mkuz1/Quran-Reader-HD
AppSupportURL=https://github.com/Mkuz1/Quran-Reader-HD/issues
AppUpdatesURL=https://github.com/Mkuz1/Quran-Reader-HD/releases
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Quran Reader HD
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir={#OutputDir}
OutputBaseFilename=QuranReaderHD-{#AppVersion}-Setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\QuranReaderHD.exe
UninstallDisplayName=Quran Reader HD
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Updating while the app is open: close it, install, then start it again.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Quran Reader HD"; Filename: "{app}\QuranReaderHD.exe"
Name: "{autodesktop}\Quran Reader HD"; Filename: "{app}\QuranReaderHD.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\QuranReaderHD.exe"; Description: "{cm:LaunchProgram,Quran Reader HD}"; Flags: nowait postinstall skipifsilent
