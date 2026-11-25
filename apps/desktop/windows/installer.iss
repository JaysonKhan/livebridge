; Inno Setup script for the Windows installer (built by .github/workflows/windows.yml).
; Installs per user by default (no administrator rights), adds "JK - LiveBridge" to the Start menu so typing "JK"
; finds it, and registers an uninstaller. The version comes from the LB_VERSION environment variable.

#define AppName "JK - LiveBridge"
#define AppExe "livebridge.exe"
#define AppVersion GetEnv("LB_VERSION")

[Setup]
AppId={{DCB0E309-A5EF-48A5-905F-CB3420920EB1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=JaysonKhan
AppPublisherURL=https://jaysonkhan.com
AppSupportURL=https://github.com/JaysonKhan/livebridge
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\..\dist
OutputBaseFilename=JK-LiveBridge-{#AppVersion}-windows-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
LicenseFile=..\..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
