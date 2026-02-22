#define MyAppName "open890"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #error "SourceDir preprocessor variable is required (path to built open890 release folder)."
#endif

#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{A8A4F1A8-A8B0-4F58-9F3F-9F2F31A6F890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=open890 contributors
DefaultDirName={autopf}\open890
DefaultGroupName=open890
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
ArchitecturesInstallIn64BitMode=x64
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"
Name: "diagnostics_issue_draft"; Description: "If startup fails, collect diagnostics and open a pre-filled GitHub issue draft"; GroupDescription: "Troubleshooting:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\open890-diagnostics-optin.txt"

[Icons]
Name: "{autoprograms}\open890"; Filename: "{app}\open890-launcher.bat"; WorkingDir: "{app}"
Name: "{autodesktop}\open890"; Filename: "{app}\open890-launcher.bat"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{cmd}"; Parameters: "/C echo enabled>""{app}\open890-diagnostics-optin.txt"""; Flags: runhidden; Tasks: diagnostics_issue_draft
Filename: "{app}\open890-launcher.bat"; Description: "Launch open890 now"; Flags: postinstall skipifsilent
