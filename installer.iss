[Setup]
AppName=Summit Hip Numbers Media Player
AppVersion=0.1.0
DefaultDirName={pf}\Summit Hip Numbers
DefaultGroupName=Summit Hip Numbers
OutputDir=dist
OutputBaseFilename=summit_hip_numbers_installer
Compression=lzma
SolidCompression=yes

[Files]
Source: "dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Summit Hip Numbers"; Filename: "{app}\summit_hip_numbers.exe"
Name: "{group}\Uninstall Summit Hip Numbers"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\summit_hip_numbers.exe"; Description: "Launch Summit Hip Numbers"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // Set environment variables for GStreamer
    RegWriteStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'GSTREAMER_ROOT', ExpandConstant('{app}\gstreamer'));
    RegWriteStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'GST_PLUGIN_PATH', ExpandConstant('{app}\gstreamer\lib\gstreamer-1.0'));
  end;
end;