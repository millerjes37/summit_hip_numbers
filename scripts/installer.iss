[Setup]
AppName=Summit Hip Numbers
AppVersion=0.1.0
AppPublisher=Summit Professional Services
AppPublisherURL=https://github.com/millerjes37/summit_hip_numbers
DefaultDirName={pf}\Summit Hip Numbers
DefaultGroupName=Summit Hip Numbers
OutputDir=..\dist
OutputBaseFilename=summit_hip_numbers_installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\full\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Summit Hip Numbers"; Filename: "{app}\run.bat"
Name: "{group}\{cm:UninstallProgram,Summit Hip Numbers}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Summit Hip Numbers"; Filename: "{app}\run.bat"; Tasks: desktopicon

[Run]
Filename: "{app}\run.bat"; Description: "{cm:LaunchProgram,Summit Hip Numbers}"; Flags: nowait postinstall skipifsilent