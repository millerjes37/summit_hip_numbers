; Inno Setup Script for Summit Hip Numbers Media Player
; This creates a Windows installer for the application

#define MyAppName "Summit Hip Numbers Media Player"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Summit Professional Services"
#define MyAppExeName "summit_hip_numbers.exe"
#define MyAppURL "https://github.com/millerjes37/summit_hip_numbers"

[Setup]
; NOTE: The value of AppId uniquely identifies this application
AppId={{E7C5F16A-2B5D-4F6C-9A7E-3D8B1C4E2F0A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Summit Hip Numbers
DefaultGroupName=Summit Hip Numbers
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=summit_hip_numbers_installer
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableStartupPrompt=yes
DisableWelcomePage=no
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "kioskmode"; Description: "Enable auto-start for kiosk mode"; Flags: unchecked

[Files]
; Main executable
Source: "..\dist\full\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Configuration
Source: "..\dist\full\config.toml"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist
; All DLLs
Source: "..\dist\full\*.dll"; DestDir: "{app}"; Flags: ignoreversion
; GStreamer plugins
Source: "..\dist\full\lib\gstreamer-1.0\*"; DestDir: "{app}\lib\gstreamer-1.0"; Flags: ignoreversion recursesubdirs createallsubdirs
; Documentation
Source: "..\dist\full\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\full\VERSION.txt"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\dist\full\BUILD_MANIFEST.txt"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; Launcher script
Source: "..\dist\full\run.bat"; DestDir: "{app}"; Flags: ignoreversion
; Assets (videos, splash, logo)
Source: "..\dist\full\videos\*"; DestDir: "{app}\videos"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\dist\full\splash\*"; DestDir: "{app}\splash"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\dist\full\logo\*"; DestDir: "{app}\logo"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "..\dist\full\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\run.bat"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Configuration"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--config"; Comment: "Open configuration GUI"; WorkingDir: "{app}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\run.bat"; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"

[Registry]
; Create registry entries for GStreamer
Root: HKLM; Subkey: "System\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "GST_PLUGIN_PATH"; ValueData: "{app}\lib\gstreamer-1.0;{olddata}"; Flags: preservestringtype
Root: HKLM; Subkey: "System\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "PATH"; ValueData: "{app};{olddata}"; Flags: preservestringtype
; Application registry entries
Root: HKLM; Subkey: "Software\{#MyAppPublisher}\{#MyAppName}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\{#MyAppPublisher}\{#MyAppName}"; ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletekey

[Run]
; Launch application after install
Filename: "{app}\run.bat"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"
; Create scheduled task for kiosk mode
Filename: "schtasks.exe"; Parameters: "/Create /SC ONLOGON /TN ""Summit Hip Numbers Kiosk"" /TR ""{app}\run.bat"" /RL HIGHEST /F"; Flags: runhidden; Tasks: kioskmode

[UninstallDelete]
Type: filesandordirs; Name: "{app}\videos"
Type: filesandordirs; Name: "{app}\splash"
Type: filesandordirs; Name: "{app}\logo"
Type: files; Name: "{app}\application.log"
Type: files; Name: "{app}\*.log"

[UninstallRun]
; Remove scheduled task on uninstall
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""Summit Hip Numbers Kiosk"" /F"; Flags: runhidden

[Code]
function IsWindows10OrLater: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := (Version.Major >= 10);
end;

function InitializeSetup(): Boolean;
var
  ErrorCode: Integer;
  UninstallString: String;
begin
  Result := True;
  
  // Check for previous installation
  if RegQueryStringValue(HKLM, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{E7C5F16A-2B5D-4F6C-9A7E-3D8B1C4E2F0A}_is1', 'UninstallString', UninstallString) then
  begin
    if MsgBox('A previous version of Summit Hip Numbers is already installed. Do you want to uninstall it first?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      Exec(UninstallString, '/SILENT', '', SW_HIDE, ewWaitUntilTerminated, ErrorCode);
    end;
  end;
  
  // Check for required Windows version (Windows 10 or later)
  if not IsWindows10OrLater then
  begin
    MsgBox('Summit Hip Numbers requires Windows 10 or later.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Create directories if they don't exist
    if not DirExists(ExpandConstant('{app}\videos')) then
      CreateDir(ExpandConstant('{app}\videos'));
    if not DirExists(ExpandConstant('{app}\splash')) then
      CreateDir(ExpandConstant('{app}\splash'));
    if not DirExists(ExpandConstant('{app}\logo')) then
      CreateDir(ExpandConstant('{app}\logo'));
  end;
end;