[Setup]
AppName=Summit Hip Numbers
AppVersion=0.1.0
AppPublisher=Summit Professional Services
AppPublisherURL=https://github.com/millerjes37/summit_hip_numbers
DefaultDirName={autopf}\Summit Hip Numbers
DefaultGroupName=Summit Hip Numbers
OutputDir=dist
OutputBaseFilename=summit_hip_numbers_installer
Compression=lzma/max
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"
Name: kioskmode; Description: "Enable auto-start for NUC kiosk mode"

[Files]
Source: "dist/full/*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Summit Hip Numbers"; Filename: "{app}\run.bat"; WorkingDir: "{app}"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Summit Hip Numbers"; Filename: "{app}\run.bat"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\run.bat"; Description: "Launch kiosk"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"
Filename: "schtasks.exe"; Parameters: "/Create /SC ONLOGON /TN SummitKiosk /TR ""{app}\run.bat"" /RL HIGHEST /F"; Flags: runhidden; Tasks: kioskmode

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "GST_PLUGIN_PATH"; ValueData: "{app}\lib\gstreamer-1.0;{olddata}"; Flags: preservestringtype
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "PATH"; ValueData: "{app};{olddata}"; Flags: preservestringtype

[Code]
function InitializeSetup: Boolean;
begin
  CreateDir(ExpandConstant('{app}\videos'));
  CreateDir(ExpandConstant('{app}\splash'));
  CreateDir(ExpandConstant('{app}\logo'));
  Result := True;
end;
  Result := True;
end;