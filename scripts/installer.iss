[Setup]
AppName=Summit Hip Numbers
AppVersion=0.1.0
AppPublisher=Summit Professional Services
AppPublisherURL=https://github.com/millerjes37/summit_hip_numbers
DefaultDirName={pf}\Summit Hip Numbers
DefaultGroupName=Summit Hip Numbers
OutputDir=dist
OutputBaseFilename=summit_hip_numbers_installer
Compression=lzma/max
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autolaunch"; Description: "Launch the app automatically on startup (for kiosk mode)"; GroupDescription: "Additional options:"

[Components]
Name: "main"; Description: "Core application files (required)"; Flags: fixed
Name: "gstreamer"; Description: "GStreamer dependencies (DLLs and plugins)"; Flags: fixed

[Files]
Source: "dist/full/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Summit Hip Numbers"; Filename: "{app}\run.bat"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,Summit Hip Numbers}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Summit Hip Numbers"; Filename: "{app}\run.bat"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\run.bat"; Description: "{cm:LaunchProgram,Summit Hip Numbers}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"
Filename: "{app}\run.bat"; Description: "Launch kiosk on startup"; Flags: shellexec; Tasks: autolaunch

[UninstallDelete]
Type: filesandordirs; Name: "{app}\videos"
Type: filesandordirs; Name: "{app}\splash"
Type: filesandordirs; Name: "{app}\logo"
Type: files; Name: "{app}\config.toml"

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "GST_PLUGIN_PATH"; ValueData: "{app}\lib\gstreamer-1.0;{olddata}"; Flags: preservestringtype
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "GST_PLUGIN_SYSTEM_PATH_1_0"; ValueData: "{app}\lib\gstreamer-1.0;{olddata}"; Flags: preservestringtype
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "PATH"; ValueData: "{app};{olddata}"; Flags: preservestringtype

[Code]
function InitializeSetup(): Boolean;
begin
  if not DirExists(ExpandConstant('{app}')) then begin
    CreateDir(ExpandConstant('{app}\videos'));
    CreateDir(ExpandConstant('{app}\splash'));
    CreateDir(ExpandConstant('{app}\logo'));
  end;
  Result := True;
end;