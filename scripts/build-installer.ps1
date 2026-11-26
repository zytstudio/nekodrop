# Builds every part of nekodrop, stages it in build\stage, and makes
# build\nekodrop-<version>-setup.exe with Inno Setup 6 (or a zip without it).
#   radio\    nekodrop-radio.exe (Intel) + Intel firmware, nekodrop-radio-rtl.exe (RTL8852CE),
#             nekodrop-radio-usb.exe (RTL8821CU, USB), nekodrop-radio-mt.exe (MT7902)
#             + nekodrop-radio-mtk.exe (MT7922/MT7921) + MediaTek firmware
#   awdl\     awdld.exe (winawdl's AWDL daemon, OWL) + wintun.dll
#   airdrop\  winawdl's AirDrop engine (Python, MIT)
#   python\   the Python embeddable distribution
#   driver\   the register-proxy UMDF driver package and the USB dongle's WinUSB
#             package (both signed on the target PC)
#   nekodrop.exe (client), NekoDropService.exe (service), install/uninstall scripts
# -Offline skips the downloads (Python embeddable, TAP-Windows) and uses what
# build\downloads already holds.
param([switch]$Offline, [string]$PythonVersion = '3.12.8', [string]$TapVersion = '9.24.7-I601')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain.ps1"
$repo = Split-Path $PSScriptRoot -Parent
$stage = "$repo\build\stage"
$downloads = "$repo\build\downloads"
$tools = Initialize-Toolchain
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage, $downloads | Out-Null

'radio'
& "$PSScriptRoot\build-radio.ps1" | Out-Null
New-Item -ItemType Directory -Force "$stage\radio\firmware" | Out-Null
Copy-Item "$repo\build\iwxradio\winawdl_radio.exe" "$stage\radio\nekodrop-radio.exe"
Copy-Item "$repo\build\iwxradio\firmware\*" "$stage\radio\firmware\"

'radio (Realtek RTL8852CE)'
& "$PSScriptRoot\build-radio-rtl.ps1" | Out-Null
$rtlRadio = "$repo\build\rtlradio\winawdl_radio.exe"
if (-not (Test-Path $rtlRadio)) { throw "RTL radio binary missing: $rtlRadio" }
Copy-Item $rtlRadio "$stage\radio\nekodrop-radio-rtl.exe"

'radio (Realtek RTL8821CU, USB)'
& "$PSScriptRoot\build-radio-usb.ps1" | Out-Null
$usbRadio = "$repo\build\usbradio\nekodrop-radio-usb.exe"
if (-not (Test-Path $usbRadio)) { throw "USB radio binary missing: $usbRadio" }
Copy-Item $usbRadio "$stage\radio\nekodrop-radio-usb.exe"

'radio (MediaTek MT7902)'
& "$PSScriptRoot\build-radio-mt.ps1" | Out-Null
$mtBuild = "$repo\build\mtradio"
Copy-Item "$mtBuild\nekodrop-radio-mt.exe" "$stage\radio\"
Copy-Item "$mtBuild\firmware\WIFI_RAM_CODE_MT7902_1.bin", "$mtBuild\firmware\WIFI_MT7902_patch_mcu_1_1_hdr.bin" "$stage\radio\firmware\"

'radio (MediaTek MT7922/MT7921)'
& "$PSScriptRoot\build-radio-mtk.ps1" | Out-Null
$mtkBuild = "$repo\build\mtkradio"
Copy-Item "$mtkBuild\nekodrop-radio-mtk.exe" "$stage\radio\"
Copy-Item "$mtkBuild\firmware\WIFI_MT7922_patch_mcu_1_1_hdr.bin", "$mtkBuild\firmware\WIFI_RAM_CODE_MT7922_1.bin",
          "$mtkBuild\firmware\WIFI_MT7961_patch_mcu_1_2_hdr.bin", "$mtkBuild\firmware\WIFI_RAM_CODE_MT7961_1.bin" "$stage\radio\firmware\"

'awdl'
& "$PSScriptRoot\build-awdl.ps1" -MinGW "$repo\third_party\winlibs\mingw64\bin" | Out-Null
New-Item -ItemType Directory -Force "$stage\awdl" | Out-Null
Copy-Item "$repo\third_party\winawdl\build\awdl\awdld.exe", "$repo\third_party\winawdl\deps\wintun\wintun.dll" "$stage\awdl\"

'airdrop engine'
New-Item -ItemType Directory -Force "$stage\airdrop" | Out-Null
Copy-Item "$repo\third_party\winawdl\airdrop\*.py", "$repo\third_party\winawdl\airdrop\LICENSE" "$stage\airdrop\"
# nekodrop's Apple ID identity for the engine (Contacts Only), hooked in by patch-engine.py.
Copy-Item "$repo\installer\nekodrop_identity.py" "$stage\airdrop\"
& python -I "$PSScriptRoot\patch-engine.py" "$stage\airdrop"
if ($LASTEXITCODE -ne 0) { throw 'engine patch failed' }
# sender.py looks for the Bluetooth beacon script in ..\scripts beside its own folder.
New-Item -ItemType Directory -Force "$stage\scripts" | Out-Null
# nekodrop's copy (#22): leaves the install folder and exits with the engine.
Copy-Item "$repo\installer\airdrop-beacon.ps1" "$stage\scripts\"

'apple id sign-in (Contacts Only)'
# WirDrop's appleid.exe (64-bit) and appleid-anisette.exe (32-bit, it loads iCloud's
# own AOSKit): the client runs them to sign in to an Apple ID and keep the AirDrop
# certificate fresh. Needs Rust; without it the setting stays off (Everyone only).
$wd = "$repo\third_party\WirDrop"
if ((Get-Command cargo -ErrorAction SilentlyContinue) -and (Test-Path "$wd\Cargo.toml")) {
  & python -I "$PSScriptRoot\patch-appleid.py" $wd
  if ($LASTEXITCODE -ne 0) { throw 'appleid patch failed' }
  Push-Location $wd
  try {
    cargo build --release --locked -q -p wirdrop-appleid
    if ($LASTEXITCODE -ne 0) { throw 'appleid build failed' }
    cargo build --release --locked -q -p wirdrop-appleid-anisette --target i686-pc-windows-msvc
    if ($LASTEXITCODE -ne 0) { throw 'appleid-anisette build failed' }
  } finally { Pop-Location }
  New-Item -ItemType Directory -Force "$stage\appleid" | Out-Null
  Copy-Item "$wd\target\release\appleid.exe", "$wd\target\i686-pc-windows-msvc\release\appleid-anisette.exe", "$wd\LICENSE" "$stage\appleid\"
} else { '  (no Rust or no third_party\WirDrop: Apple ID sign-in left out)' }

'driver'
& "$repo\driver\regproxy\build.ps1" | Out-Null
New-Item -ItemType Directory -Force "$stage\driver" | Out-Null
Copy-Item "$repo\driver\regproxy\build\winawdl_regproxy.inf", "$repo\driver\regproxy\build\winawdl_regproxy.dll" "$stage\driver\"
# The RTL8821CU USB dongle's WinUSB package, catalogued here and signed on the
# target PC with the same certificate as the register proxy (install.ps1).
Copy-Item "$repo\driver\winusb\nekodrop_winusb.inf" "$stage\driver\"
$now = Get-Date
$driverVersion = "0.1.$(($now - [datetime]'2026-01-01').Days).$($now.Hour * 60 + $now.Minute)"
& $tools.StampInf -f "$stage\driver\winawdl_regproxy.inf" -d * -v $driverVersion | Out-Null
& $tools.StampInf -f "$stage\driver\nekodrop_winusb.inf" -d * -v $driverVersion | Out-Null
& $tools.Inf2Cat "/driver:$stage\driver" /os:10_X64 /uselocaltime | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed ($LASTEXITCODE)" }

'Explorer context menu (Windows 11 first level)'
$shellBuild = "$repo\build\shellext"
New-Item -ItemType Directory -Force "$shellBuild\pkg\Assets" | Out-Null
& $tools.Cl /nologo /utf-8 /O2 /EHsc /W4 /WX /LD /MT "$repo\app\shellext\shell.cpp" "/Fo$shellBuild\\" "/Fe$shellBuild\nekodrop-shell.dll" `
  /link /DEF:"$repo\app\shellext\shell.def" shell32.lib ole32.lib shlwapi.lib advapi32.lib user32.lib | Out-Null
if ($LASTEXITCODE -ne 0) { throw "context menu DLL build failed ($LASTEXITCODE)" }
Copy-Item "$shellBuild\nekodrop-shell.dll" $stage
Copy-Item "$repo\installer\sparse\AppxManifest.xml" "$shellBuild\pkg\"
Copy-Item "$repo\app\assets\logo150.png" "$shellBuild\pkg\Assets\logo.png"
$makeAppx = Join-Path (Split-Path $tools.SignTool) 'makeappx.exe'
New-Item -ItemType Directory -Force "$stage\shell" | Out-Null
& $makeAppx pack /o /nv /d "$shellBuild\pkg" /p "$stage\shell\nekodrop-shell.msix" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "makeappx failed ($LASTEXITCODE)" }
# install.ps1 signs the package on the target PC with the certificate it makes there.
# signtool loads its signing and APPX libraries as side-by-side assemblies from its own folder.
$sdkBin = Split-Path $tools.SignTool
foreach ($f in 'signtool.exe', 'signtool.exe.manifest', 'mssign32.dll', 'wintrust.dll', 'wintrust.dll.ini',
               'appxsip.dll', 'appxpackaging.dll', 'opcservices.dll',
               'Microsoft.Windows.Build.Signing.mssign32.dll.manifest', 'Microsoft.Windows.Build.Signing.wintrust.dll.manifest',
               'Microsoft.Windows.Build.Appx.AppxSip.dll.manifest', 'Microsoft.Windows.Build.Appx.AppxPackaging.dll.manifest',
               'Microsoft.Windows.Build.Appx.OpcServices.dll.manifest') {
  Copy-Item "$sdkBin\$f" "$stage\shell\"
}

'kernel Wi-Fi driver (installed separately: needs test signing)'
& "$PSScriptRoot\build-kdriver.ps1" | Out-Host
New-Item -ItemType Directory -Force "$stage\kdriver" | Out-Null
Copy-Item "$repo\build\kdriver\package\*" "$stage\kdriver\"
Copy-Item "$PSScriptRoot\kdriver-install.ps1", "$PSScriptRoot\kdriver-restore.ps1" "$stage\kdriver\"

'service and client'
# Self-contained single files: the target PC needs no .NET runtime, and the two
# apps cannot overwrite each other's runtime libraries in the shared folder.
$single = '--self-contained', 'true', '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true',
          '-p:EnableCompressionInSingleFile=true', '-p:DebugType=none'
dotnet publish "$repo\app\service\NekoDrop.Service.csproj" -c Release -o "$stage" --nologo -v q @single
if ($LASTEXITCODE -ne 0) { throw 'service publish failed' }
# The card catalog's offline checks (app/service/CardCatalog.cs): no card or admin rights needed.
& "$stage\NekoDropService.exe" --selftest
if ($LASTEXITCODE -ne 0) { throw 'service self-test failed' }
dotnet publish "$repo\app\client\NekoDrop.csproj" -c Release -o "$stage" --nologo -v q @single
if ($LASTEXITCODE -ne 0) { throw 'client publish failed' }
Copy-Item "$repo\installer\install.ps1", "$repo\installer\uninstall.ps1", "$repo\installer\setup-tap.ps1",
          "$repo\installer\restore.ps1", "$repo\installer\restore.cmd",
          "$repo\installer\report.ps1", "$repo\installer\report.cmd" $stage
# uninstall.ps1 and setup-tap.ps1 have no self-test: parse them (and the rest)
# under Windows PowerShell 5.1 so a syntax error fails the build (#22).
foreach ($script in 'install.ps1', 'uninstall.ps1', 'setup-tap.ps1', 'restore.ps1', 'report.ps1', 'scripts\airdrop-beacon.ps1') {
  & powershell.exe -NoProfile -Command "`$e = `$null; [void][Management.Automation.Language.Parser]::ParseFile('$stage\$script', [ref]`$null, [ref]`$e); if (`$e) { `$e | ForEach-Object { `$_.ToString() }; exit 1 }"
  if ($LASTEXITCODE -ne 0) { throw "$script does not parse" }
}
# Offline installer/rollback/report/uninstall self-tests under Windows PowerShell 5.1
# (no card or admin rights needed).
foreach ($script in 'install.ps1', 'uninstall.ps1', 'restore.ps1', 'report.ps1') {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$stage\$script" -SelfTest
  if ($LASTEXITCODE -ne 0) { throw "$script self-test failed ($LASTEXITCODE)" }
}

'downloads'
$py = "$downloads\python-$PythonVersion-embed-amd64.zip"
$tap = "$downloads\tap-windows-$TapVersion.exe"
if (-not $Offline) {
  if (-not (Test-Path $py)) {
    Invoke-WebRequest "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip" -OutFile $py -UseBasicParsing
  }
  if (-not (Test-Path $tap)) {
    Invoke-WebRequest "https://build.openvpn.net/downloads/releases/tap-windows-$TapVersion-Win10.exe" -OutFile $tap -UseBasicParsing
  }
}
if (Test-Path $py) {
  Expand-Archive $py "$stage\python" -Force
  # The embeddable distribution's ._pth fixes sys.path: list the engine's folder
  # there, since its modules import each other.
  $pth = Get-ChildItem "$stage\python" -Filter 'python*._pth' | Select-Object -First 1
  Add-Content $pth.FullName '..\airdrop'
} else { '  (no Python embeddable: the client falls back to a Python on PATH)' }
if (Test-Path $tap) {
  $sig = Get-AuthenticodeSignature $tap
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'OpenVPN') {
    throw "tap-windows installer is not validly signed by OpenVPN: $($sig.Status)"
  }
  Copy-Item $tap "$stage\tap-windows.exe"
}

'licenses'
New-Item -ItemType Directory -Force "$stage\licenses" | Out-Null
Copy-Item "$repo\third_party\ForbiddenItlwm\LICENSE" "$stage\licenses\ForbiddenItlwm-GPL-2.0.txt"
Copy-Item "$repo\third_party\ForbiddenItlwm\iwlwifi-firmware-license" "$stage\licenses\iwlwifi-firmware.txt"
Copy-Item "$repo\third_party\winawdl\LICENSE" "$stage\licenses\winawdl-MIT.txt"
Copy-Item "$repo\third_party\winawdl\awdl\LICENSE" "$stage\licenses\awdld-GPL-3.0.txt"
Copy-Item "$repo\third_party\winawdl\airdrop\LICENSE" "$stage\licenses\airdrop-engine-MIT.txt"
Copy-Item "$repo\LICENSE" "$stage\licenses\nekodrop-GPL-2.0.txt"
Copy-Item "$mtBuild\firmware\LICENCE.mediatek" "$stage\licenses\mediatek-firmware.txt"
Copy-Item "$repo\mtradio\LICENSE.mt76" "$stage\licenses\mt76-BSD-3-Clause.txt"
Copy-Item "$repo\third_party\winawdl\deps\wintun\LICENSE.txt" "$stage\licenses\wintun.txt"
$devourerLicense = @("$repo\third_party\winawdl\upstream\devourer\LICENSE", "$repo\third_party\winawdl\radio\LICENSE") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if ($devourerLicense) { Copy-Item $devourerLicense "$stage\licenses\devourer-GPL-2.0.txt" }

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if ($iscc) {
  & $iscc "$repo\installer\nekodrop.iss" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed ($LASTEXITCODE)" }
  Get-ChildItem "$repo\build\nekodrop-*-setup.exe" | Select-Object Name, Length
} else {
  $zip = "$repo\build\nekodrop-2.2.12-windows-x64.zip"
  Compress-Archive "$stage\*" $zip -Force
  "Inno Setup not found: made $zip instead (unzip, then run install.ps1 as administrator)."
}
