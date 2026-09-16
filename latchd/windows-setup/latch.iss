; Latch desktop companion installer (Inno Setup 6).
;
; Shows the EULA/Terms/Privacy (windows-setup/license.txt, generated from
; legal/ by build-license.py — same texts, same version, as the Latch Web
; first-run gate) before installing. Installs latchd.exe, adds an optional
; Start-menu entry that serves Latch Web on loopback and opens the browser.
; The server-side legal gate still enforces acceptance on first run, so the
; installer EULA and the web gate agree by construction (both from legal/).
;
; Built by CI (release-latchd.yml) or locally:
;   cd latchd/windows-setup && python3 build-license.py && iscc latch.iss /DMyAppVersion=0.18.0-beta.1
#define MyAppName "Latch"
#ifndef MyAppVersion
  #define MyAppVersion "dev"
#endif
#define MyExe "latchd-windows-amd64.exe"

[Setup]
AppId={{8A3F2B1C-4D5E-4F6A-9B7C-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Latch
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
LicenseFile=license.txt
OutputDir=..\..\dist
OutputBaseFilename=Latch-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Loopback-only web UI: no firewall exception needed, never request one.
CloseApplications=yes

[Files]
Source: "..\..\dist\{#MyExe}"; DestDir: "{app}"; DestName: "latchd.exe"; Flags: ignoreversion

[Icons]
Name: "{group}\Latch Web (start server)"; Filename: "{app}\latchd.exe"; Parameters: "serve"; WorkingDir: "{app}"
Name: "{group}\Uninstall Latch"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Latch Web"; Filename: "{app}\latchd.exe"; Parameters: "serve"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\latchd.exe"; Parameters: "serve"; Description: "Start Latch Web now (http://127.0.0.1:7800)"; Flags: nowait postinstall runasoriginaluser skipifsilent
