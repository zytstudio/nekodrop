; nekodrop setup (Inno Setup 6). Built by scripts\build-installer.ps1 from build\stage.
; One exe installs everything: the client and service (self-contained, no .NET
; needed), the user-mode radio, awdld + Wintun, the AirDrop engine with its own
; Python, the register-proxy driver, TAP-Windows, firewall rules and the service.
#define AppVersion "2.2.13"

[Setup]
AppId={{6C1F2E7A-4B8E-4E57-9C61-5E2B1D0A9F31}
AppName=nekodrop
AppVersion={#AppVersion}
AppPublisher=nekodrop project
DefaultDirName={autopf}\nekodrop
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputBaseFilename=nekodrop-{#AppVersion}-setup
OutputDir=..\build
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=../app/assets/nekodrop.ico
UninstallDisplayIcon={app}\nekodrop.exe
CloseApplications=yes
; [Run] starts the new version in the chosen mode; do not let Setup restart
; the old copy separately (it would not know the chosen mode).
RestartApplications=no

[Languages]
Name: "zh"; MessagesFile: "ChineseSimplified.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
zh.Installing=正在安装驱动、TAP 网卡、防火墙规则和 nekodrop 服务（约需 1 分钟）…
en.Installing=Installing the driver, TAP adapter, firewall rules and the nekodrop service (about a minute)…
zh.Failed=nekodrop 的系统组件没有装好：%n%n%1%n%n完整日志：%2
en.Failed=nekodrop's system parts did not install:%n%n%1%n%nFull log: %2
zh.StartNow=启动 nekodrop
en.StartNow=Start nekodrop
zh.Desktop=创建桌面快捷方式
en.Desktop=Create a desktop shortcut

[Tasks]
Name: "desktop"; Description: "{cm:Desktop}"; Flags: unchecked

[Files]
Source: "..\build\stage\*"; DestDir: "{tmp}\nekodrop-stage"; Flags: recursesubdirs ignoreversion deleteafterinstall

[Icons]
; The AppUserModelID lets Windows show nekodrop's notifications under its own name.
Name: "{autoprograms}\nekodrop"; Filename: "{app}\nekodrop.exe"; AppUserModelID: "nekodrop.app"
Name: "{autodesktop}\nekodrop"; Filename: "{app}\nekodrop.exe"; AppUserModelID: "nekodrop.app"; Tasks: desktop
; One-click rollback: gives the Wi-Fi card back to Intel's driver (restore.ps1).
Name: "{autoprograms}\nekodrop - restore Windows Wi-Fi"; Filename: "{app}\restore.cmd"; IconFilename: "{sys}\netshell.dll"; IconIndex: 0
; Diagnostic report for bug reports: logs and system details, redacted (report.ps1).
Name: "{autoprograms}\nekodrop - diagnostic report"; Filename: "{app}\report.cmd"; IconFilename: "{sys}\imageres.dll"; IconIndex: 76

[Run]
; Started as the signed-in user: the first start registers the Explorer
; "用 nekodrop 发送" menu, Send To and the notification protocol for that user.
Filename: "{app}\nekodrop.exe"; Description: "{cm:StartNow}"; Flags: postinstall nowait skipifsilent runasoriginaluser
; A silent install (/VERYSILENT) starts the new version once setup is done: in the
; background, or with its main panel when /SHOWAPP is passed. nekodrop itself has
; no updater, so this only matters for scripted installs.
Filename: "{app}\nekodrop.exe"; Flags: nowait runasoriginaluser; Check: ShouldLaunchWindow
Filename: "{app}\nekodrop.exe"; Parameters: "--background"; Flags: nowait runasoriginaluser; Check: ShouldLaunchBackground

[UninstallRun]
Filename: "{app}\nekodrop.exe"; Parameters: "--unregister"; Flags: waituntilterminated skipifdoesntexist runhidden; RunOnceId: "nekodrop-unregister"
; -Inno keeps the running uninstaller alive and lets Setup remove the shortcuts,
; the Add/Remove Programs entry and its own files after uninstall.ps1 returns.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"" -Target ""{app}"" -Inno"; \
  Flags: runhidden waituntilterminated; RunOnceId: "nekodrop-uninstall"

[Code]
var
  InstallFailed: Boolean;

function CommandLineHas(const Switch: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Switch) = 0 then
      Result := True;
end;

function ShouldLaunchWindow: Boolean;
begin
  Result := WizardSilent and CommandLineHas('/SHOWAPP');
end;

function ShouldLaunchBackground: Boolean;
begin
  Result := WizardSilent and not CommandLineHas('/SHOWAPP');
end;

function GetCustomSetupExitCode: Integer;
begin
  if InstallFailed then
    Result := 1
  else
    Result := 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
  Lines: TArrayOfString;
  Err: String;
  Log: String;
  I: Integer;
begin
  if CurStep <> ssPostInstall then Exit;
  WizardForm.StatusLabel.Caption := CustomMessage('Installing');
  Log := ExpandConstant('{commonappdata}\nekodrop\install.log');
  // The files are copied by now, so the bar stood full and still for the half
  // minute or more the driver, TAP and service take, and looked stuck (#45):
  // let it run while install.ps1 works.
  WizardForm.ProgressGauge.Style := npbstMarquee;
  try
    if not Exec('powershell.exe',
        '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\nekodrop-stage\install.ps1') +
        '" -Target "' + ExpandConstant('{app}') + '"',
        '', SW_HIDE, ewWaitUntilTerminated, Code) then
      Code := -1;
  finally
    WizardForm.ProgressGauge.Style := npbstNormal;
  end;
  if Code <> 0 then
  begin
    InstallFailed := True;
    // install.ps1 writes UTF-8 (with a BOM); LoadStringFromFile read it as ANSI,
    // which garbled Windows' own Chinese error text and showed the BOM as a stray character.
    Err := '';
    if LoadStringsFromFile(ExpandConstant('{commonappdata}\nekodrop\install-error.txt'), Lines) then
      for I := 0 to GetArrayLength(Lines) - 1 do
        Err := Err + Lines[I] + #13#10;
    Err := Trim(Err);
    if Err = '' then
      Err := 'install.ps1 exit code ' + IntToStr(Code);
    SuppressibleMsgBox(FmtMessage(CustomMessage('Failed'), [Err, Log]), mbError, MB_OK, IDOK);
  end;
end;
