# One-click rollback: puts the PC's Wi-Fi back the way Windows had it, whatever
# state nekodrop left it in (service running or crashed, card held by the
# register proxy or by the shelved kernel driver). Needs nothing from nekodrop
# itself, so it also works when nekodrop's own files are broken or deleted.
#   1. stops nekodrop and turns its service off (it would take the card again)
#   2. binds the card vendor's driver again (the package Windows used before)
#   3. removes nekodrop's driver packages from the driver store
#   4. adds back saved Wi-Fi networks Windows lost (from nekodrop's backup)
#   5. turns the "nekodrop" TAP adapter off and makes sure WLAN AutoConfig runs
# nekodrop stays installed; run the installer again to use it, or
# -Uninstall to remove it completely afterwards.
# -SelfTest checks target card resolution and vendor driver-package selection
# against made-up devices and exits 0 (all pass) or 1; it needs no
# administrator rights and no card, and changes and writes nothing.
#
# Needs administrator rights. There is no "#Requires -RunAsAdministrator": it
# is checked while the script is parsed, before param(), so -SelfTest could not
# run on a build machine without them. The same check is made below instead,
# before anything is written.
# Log: %ProgramData%\nekodrop\restore.log
param([switch]$Uninstall, [switch]$SelfTest)
$ErrorActionPreference = 'Continue'

# ------------------------------------------------ standalone vendor rollback data
# Self-contained (never reads %ProgramFiles%\nekodrop). Keep $SupportedIntelIds
# in step with iwxradio/src/cards.h, app/service/CardCatalog.cs,
# driver/regproxy/winawdl_regproxy.inf, installer/report.ps1 and install.ps1.
$SupportedIntelIds = @('43F0', 'A0F0', '02F0', '06F0', '34F0', '3DF0', '4DF0', '2723', '2725', '7A70', '7AF0', '51F0', '51F1', '54F0', '7F70')
$KnownCatalogIds = @($SupportedIntelIds | ForEach-Object { "8086:$_" }) + @('8086:272B', '10EC:C852', '0BDA:C820', '0BDA:C821')
$ProxyInfNames = @('winawdl_regproxy.inf', 'nekodrop-wlan.inf', 'nekodrop_winusb.inf')
$ProxyServices = @('WUDFRd', 'nekodrop-wlan', 'WINUSB')
$ProxyProvider = 'winairdrop project'
$VendorProfiles = @{
  '8086' = @{ Name = 'Intel';            ProviderPatterns = @('Intel', 'Killer', 'Rivet Networks'); DownloadHint = 'intel.com or Windows Update' }
  '10EC' = @{ Name = 'Realtek';          ProviderPatterns = @('Realtek');                           DownloadHint = 'your PC maker or Windows Update' }
  # A USB dongle's vendor id (Realtek's USB side), whose driver names the same
  # provider as the PCI half: the RTL8821CU is bound back to it.
  '0BDA' = @{ Name = 'Realtek';          ProviderPatterns = @('Realtek');                           DownloadHint = 'your PC maker or Windows Update' }
  '14C3' = @{ Name = 'MediaTek';         ProviderPatterns = @('MediaTek', 'AMD');                   DownloadHint = 'your PC maker or Windows Update' }
  '17CB' = @{ Name = 'Qualcomm';         ProviderPatterns = @('Qualcomm');                          DownloadHint = 'your PC maker or Windows Update' }
  '168C' = @{ Name = 'Qualcomm Atheros'; ProviderPatterns = @('Qualcomm', 'Atheros');               DownloadHint = 'your PC maker or Windows Update' }
  '14E4' = @{ Name = 'Broadcom';         ProviderPatterns = @('Broadcom');                          DownloadHint = 'your PC maker or Windows Update' }
}

function Get-PciVendorDevice([string]$InstanceId) {
  $id = "$InstanceId".Trim().ToUpper()
  if ($id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})(?:&|\\|$)') {
    $v = $Matches[1]; $d = $Matches[2]
    return [pscustomobject]@{
      VendorId   = $v
      DeviceId   = $d
      Key        = ($v + ':' + $d)
      HardwareId = "PCI\VEN_$v&DEV_$d"
    }
  }
  return $null
}

function Get-UsbVendorDevice([string]$InstanceId) {
  $id = "$InstanceId".Trim().ToUpper()
  if ($id -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})(?:&|\\|$)') {
    $v = $Matches[1]; $d = $Matches[2]
    return [pscustomobject]@{
      Bus        = 'USB'
      VendorId   = $v
      DeviceId   = $d
      Key        = ($v + ':' + $d)
      HardwareId = "USB\VID_$v&PID_$d"
    }
  }
  return $null
}

# The PCIe or USB identity of a device, whichever its instance ID names.
function Get-DeviceVendor([string]$InstanceId) {
  $pci = Get-PciVendorDevice $InstanceId
  if ($pci) { return $pci }
  return Get-UsbVendorDevice $InstanceId
}

function Get-VendorProfile([string]$VendorId) {
  $v = "$VendorId".Trim().ToUpper()
  if ($v -and $VendorProfiles.ContainsKey($v)) {
    $p = $VendorProfiles[$v]
    return [pscustomobject]@{
      VendorId         = $v
      Name             = $p.Name
      ProviderPatterns = @($p.ProviderPatterns)
      DownloadHint     = $p.DownloadHint
      Known            = $true
    }
  }
  return [pscustomobject]@{
    VendorId         = $v
    Name             = $(if ($v) { "vendor $v" } else { 'the vendor' })
    ProviderPatterns = @()
    DownloadHint     = 'your PC maker or Windows Update'
    Known            = $false
  }
}

function Get-NekodropPublishedInfs($StoreDrivers) {
  $seen = @{}
  $out = @()
  foreach ($d in @($StoreDrivers | Where-Object { $_ })) {
    $orig = [IO.Path]::GetFileName("$($d.OriginalName)".Trim())
    $pub = [IO.Path]::GetFileName("$($d.DriverName)".Trim())
    if ($orig -and $pub -and ($ProxyInfNames -contains $orig)) {
      $k = $pub.ToLower()
      if (-not $seen.ContainsKey($k)) {
        $seen[$k] = $true
        $out += $pub
      }
    }
  }
  return @($out)
}

function Test-NekodropInfContent([string]$Content) {
  if (-not $Content) { return $false }
  return ($Content -match '(?i)winawdl_regproxy|nekodrop-wlan|nekodrop_winusb|winairdrop project')
}

function Test-DeviceBoundToNekodrop($Device, [string[]]$NekodropPublishedInfs) {
  if (-not $Device) { return $false }
  $svc = "$($Device.Service)".Trim()
  if ($svc -and ($ProxyServices -notcontains $svc)) { return $false }
  $inf = [IO.Path]::GetFileName("$($Device.DriverInfPath)".Trim())
  $prov = "$($Device.DriverProvider)".Trim()
  $isOurInf = $false
  if ($inf) {
    if ($ProxyInfNames -contains $inf) { $isOurInf = $true }
    elseif ($NekodropPublishedInfs -and ($NekodropPublishedInfs -contains $inf)) { $isOurInf = $true }
  }
  $isOurProvider = ($prov -and ($prov -eq $ProxyProvider))
  return ($isOurInf -or $isOurProvider)
}

# Picks the Wi-Fi card to restore (PCIe or USB):
#   1. any present device currently bound to nekodrop's proxy, kernel driver or
#      WinUSB package (WUDFRd / nekodrop-wlan / WINUSB AND our published INF or
#      provider, never unrelated UMDF devices such as sensors or HID);
#   2. else any of the 15 supported Intel PCI IDs (identical to earlier builds);
#   3. else any other known catalog ID (Realtek 10EC:C852, the RTL8821CU USB
#      dongle 0BDA:C820/C821).
# A composite USB dongle's function nodes (MI_xx) are skipped: the driver
# package is bound to the device, so that node's ID is the one to name.
function Resolve-RestoreTargetDevice($Devices, [string[]]$NekodropPublishedInfs = @()) {
  $anyDevs = @($Devices | Where-Object {
      if (-not $_) { return $false }
      $id = Get-DeviceVendor $_.InstanceId
      if (-not $id) { return $false }
      return ($id.Bus -ne 'USB' -or "$($_.InstanceId)" -notmatch '&MI_')
    })
  foreach ($d in $anyDevs) {
    if (Test-DeviceBoundToNekodrop $d $NekodropPublishedInfs) { return $d }
  }
  foreach ($d in $anyDevs) {
    $id = Get-DeviceVendor $d.InstanceId
    if ($id.Bus -ne 'USB' -and $id.VendorId -eq '8086' -and ($SupportedIntelIds -contains $id.DeviceId)) { return $d }
  }
  foreach ($d in $anyDevs) {
    $id = Get-DeviceVendor $d.InstanceId
    if ($KnownCatalogIds -contains $id.Key) { return $d }
  }
  return $null
}

function Test-TrustedInfPath([string]$CandidatePath, [string]$Windir) {
  if (-not $CandidatePath -or -not $Windir) { return $false }
  $raw = $CandidatePath.Trim()
  if ($raw -notmatch '(?i)\.inf$') { return $false }
  # Normalize slash direction and reject relative traversal outside %windir%\INF.
  $normCand = $raw -replace '/', '\'
  $normWin = ($Windir.Trim() -replace '/', '\').TrimEnd('\')
  $infRoot = ($normWin + '\INF\').ToLower()
  try {
    $full = ([IO.Path]::GetFullPath($normCand) -replace '/', '\')
  } catch { return $false }
  # On non-Windows hosts GetFullPath would prepend '/', so handle Windows drive
  # paths directly when $normCand looks like a Windows absolute path.
  if ($normCand -match '^[A-Za-z]:\\') {
    if ($normCand -match '(^|\\)\.\.(\\|$)') { return $false }
    $full = $normCand
  }
  if (-not $full.ToLower().StartsWith($infRoot)) { return $false }
  $rel = $full.Substring($infRoot.Length)
  if (-not $rel -or $rel.Contains('\')) { return $false }
  return $true
}

function Parse-DriverVersion([string]$VersionText) {
  $token = ("$VersionText".Trim() -split '\s+')[-1]
  try {
    if ($token) { return ([version]$token) }
  } catch { }
  return ([version]'0.0.0.0')
}

# Picks the vendor INF to bind back:
#   1. recorded path (vendor-inf.txt, then service.json's VendorInf), provided
#      it is under %windir%\INF, exists, and is not nekodrop's own INF (#12);
#   2. else the newest Net package in the driver store matching this PCI
#      vendor's provider patterns (never nekodrop's own INF or provider).
function Select-VendorInfPackage(
  $RecordedInfCandidates,
  $StoreDrivers,
  [string]$VendorId,
  [string]$Windir = $env:windir,
  [scriptblock]$PathExists = $null,
  [scriptblock]$ReadInfText = $null
) {
  if (-not $PathExists) {
    $PathExists = {
      param($p)
      if (-not (Test-Path -LiteralPath $p)) { return $false }
      $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
      if (-not $item) { return $false }
      return (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
    }
  }
  if (-not $ReadInfText) {
    $ReadInfText = { param($p) Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue }
  }
  $nekodropInfs = @(Get-NekodropPublishedInfs $StoreDrivers)
  $winRoot = if ($Windir) { ($Windir.Trim() -replace '/', '\').TrimEnd('\') } else { '' }
  foreach ($cand in @($RecordedInfCandidates | Where-Object { $_ })) {
    $path = "$cand".Trim()
    if (-not $path) { continue }
    # kdriver-install.ps1 records DEVPKEY_Device_DriverInfPath as a bare leaf name (e.g. oem12.inf).
    if ($winRoot -and ($path -match '^(?i)[A-Za-z0-9][A-Za-z0-9._-]*\.inf$') -and (-not $path.Contains('..'))) {
      $path = "$winRoot\INF\$path"
    }
    if (-not (Test-TrustedInfPath $path $Windir)) { continue }
    $leaf = [IO.Path]::GetFileName($path)
    if (($ProxyInfNames -contains $leaf) -or ($nekodropInfs -contains $leaf)) { continue }
    if (-not (& $PathExists $path)) { continue }
    $txt = & $ReadInfText $path
    if (Test-NekodropInfContent "$txt") { continue }
    return $path
  }

  $profile = Get-VendorProfile $VendorId
  if (-not $profile.ProviderPatterns.Count) { return $null }
  $pattern = ($profile.ProviderPatterns | ForEach-Object { [regex]::Escape($_) }) -join '|'
  $pkg = @($StoreDrivers | Where-Object {
    if (-not $_) { return $false }
    if ("$($_.ClassName)".Trim() -ne 'Net') { return $false }
    $orig = [IO.Path]::GetFileName("$($_.OriginalName)".Trim())
    $pub = [IO.Path]::GetFileName("$($_.DriverName)".Trim())
    $prov = "$($_.ProviderName)".Trim()
    if (($ProxyInfNames -contains $orig) -or ($nekodropInfs -contains $pub)) { return $false }
    if ($prov -eq $ProxyProvider) { return $false }
    return ($prov -match $pattern)
  }) | Sort-Object { Parse-DriverVersion $_.DriverVersion } -Descending | Select-Object -First 1
  if ($pkg -and $pkg.DriverName -and $winRoot) {
    $pubName = [IO.Path]::GetFileName("$($pkg.DriverName)".Trim())
    if ($pubName) { return "$winRoot\INF\$pubName" }
  }
  return $null
}

if ($SelfTest) {
  $fail = @()
  function Dev([string]$id, [string]$svc = '', [string]$inf = '', [string]$prov = '', [string]$name = '') {
    [pscustomobject]@{ InstanceId = $id; Service = $svc; DriverInfPath = $inf; DriverProvider = $prov; FriendlyName = $name }
  }
  function Drv([string]$pub, [string]$orig, [string]$prov, [string]$cls, [string]$ver) {
    [pscustomobject]@{ DriverName = $pub; OriginalName = $orig; ProviderName = $prov; ClassName = $cls; DriverVersion = $ver }
  }

  # 1. Supported Intel IDs and strict 4-hex boundary check.
  if ($SupportedIntelIds.Count -ne 15) { $fail += "expected 15 Intel IDs, got $($SupportedIntelIds.Count)" }
  foreach ($d in $SupportedIntelIds) {
    $id = "PCI\VEN_8086&DEV_$d&SUBSYS_00748086&REV_00\3&11583659&0&A3"
    $pci = Get-PciVendorDevice $id
    if (-not $pci -or $pci.Key -ne "8086:$d" -or $pci.HardwareId -ne "PCI\VEN_8086&DEV_$d") { $fail += "8086:$d did not parse" }
    $picked = Resolve-RestoreTargetDevice @((Dev $id 'Netwtw10' 'oem10.inf' 'Intel')) @()
    if (-not $picked -or $picked.InstanceId -ne $id) { $fail += "8086:$d not selected for restore" }
  }
  if ($null -ne (Get-PciVendorDevice 'PCI\VEN_8086&DEV_43F01&SUBSYS_00748086')) { $fail += '5-digit device ID DEV_43F01 parsed' }
  if ($null -ne (Get-PciVendorDevice 'USB\VID_0BDA&PID_8812\1')) { $fail += 'USB ID parsed as PCI' }

  # Shared mock driver store.
  $store = @(
    (Drv 'oem10.inf' 'netwtw10.inf'        'Intel'                       'Net'          '01/10/2024 22.190.0.4'),
    (Drv 'oem11.inf' 'netwtw14.inf'        'Intel Corporation'           'Net'          '08/15/2024 23.80.0.7'),
    (Drv 'oem12.inf' 'netwtw12.inf'        'Killer'                      'Net'          '05/01/2024 23.50.0.6'),
    (Drv 'oem20.inf' 'rtwlane601.inf'      'Realtek Semiconductor Corp.' 'Net'          '04/01/2024 6001.16.126.300'),
    (Drv 'oem21.inf' 'rtwlane602.inf'      'Realtek Semiconductor Corp.' 'Net'          '09/01/2024 6001.16.150.100'),
    (Drv 'oem30.inf' 'mtkwl6ex.inf'        'MediaTek, Inc.'              'Net'          '06/01/2024 3.3.0.900'),
    (Drv 'oem31.inf' 'qcwlan64.inf'        'Qualcomm Technologies, Inc.' 'Net'          '06/01/2024 2.0.0.1000'),
    (Drv 'oem32.inf' 'bcmwl63a.inf'        'Broadcom'                    'Net'          '06/01/2024 7.77.119.0'),
    (Drv 'oem40.inf' 'ibtusb.inf'          'Intel Corporation'           'Bluetooth'    '09/01/2025 99.0.0.1'),
    (Drv 'oem42.inf' 'winawdl_regproxy.inf' 'winairdrop project'         'WinAwdlRadio' '03/01/2026 0.1.0.1'),
    (Drv 'oem44.inf' 'nekodrop_winusb.inf'   'winairdrop project'         'USBDevice'    '03/01/2026 0.1.0.1'),
    (Drv 'oem43.inf' 'nekodrop-wlan.inf'   'winairdrop project'          'Net'          '03/01/2026 99.9.9.9'),
    (Drv 'oem5.inf'  'sensors.inf'         'Microsoft'                   'Sensor'       '01/01/2024 10.0.19041.1')
  )
  $pubProxy = @(Get-NekodropPublishedInfs $store)
  if ($pubProxy.Count -ne 3 -or $pubProxy -notcontains 'oem42.inf' -or $pubProxy -notcontains 'oem44.inf' -or $pubProxy -notcontains 'oem43.inf') {
    $fail += "nekodrop published INFs wrong: $($pubProxy -join ', ')"
  }

  # 2. Intel driver-store selection (newest version, Killer supported, Bluetooth and nekodrop ignored).
  $intelPkg = Select-VendorInfPackage @() $store '8086' 'C:\Windows' { param($p) $false } { param($p) '' }
  if ($intelPkg -ne 'C:\Windows\INF\oem11.inf') { $fail += "Intel store fallback picked '$intelPkg', want oem11.inf" }
  $killerOnly = @(
    (Drv 'oem12.inf' 'netwtw12.inf' 'Killer' 'Net' '05/01/2024 23.50.0.6'),
    (Drv 'oem21.inf' 'rtwlane602.inf' 'Realtek Semiconductor Corp.' 'Net' '09/01/2024 6001.16.150.100')
  )
  $killerPkg = Select-VendorInfPackage @() $killerOnly '8086' 'C:\Windows' { param($p) $false } { param($p) '' }
  if ($killerPkg -ne 'C:\Windows\INF\oem12.inf') { $fail += "Killer OEM Intel fallback picked '$killerPkg', want oem12.inf" }
  $rivetOnly = @((Drv 'oem13.inf' 'netwtw10.inf' 'Rivet Networks' 'Net' '05/01/2024 22.90.0.1'))
  $rivetPkg = Select-VendorInfPackage @() $rivetOnly '8086' 'C:\Windows' { param($p) $false } { param($p) '' }
  if ($rivetPkg -ne 'C:\Windows\INF\oem13.inf') { $fail += "Rivet Networks Intel fallback picked '$rivetPkg', want oem13.inf" }

  # 3. Realtek 10EC:C852 selection and driver-store fallback (never picks Intel's package).
  $rtlDevs = @(
    (Dev 'PCI\VEN_10EC&DEV_8168&SUBSYS_86771043\4&1' 'rt640x64' 'oem9.inf' 'Realtek'),
    (Dev 'PCI\VEN_10EC&DEV_C852&SUBSYS_C85210EC\4&2' 'rtwlane602' 'oem21.inf' 'Realtek Semiconductor Corp.')
  )
  $pickedRtl = Resolve-RestoreTargetDevice $rtlDevs $pubProxy
  if (-not $pickedRtl -or $pickedRtl.InstanceId -notmatch 'DEV_C852') { $fail += 'Realtek 10EC:C852 not selected' }
  $rtlPkg = Select-VendorInfPackage @() $store '10EC' 'C:\Windows' { param($p) $false } { param($p) '' }
  if ($rtlPkg -ne 'C:\Windows\INF\oem21.inf') { $fail += "Realtek store fallback picked '$rtlPkg', want oem21.inf" }
  $intelOnlyStore = @((Drv 'oem11.inf' 'netwtw14.inf' 'Intel Corporation' 'Net' '08/15/2024 23.80.0.7'))
  if ($null -ne (Select-VendorInfPackage @() $intelOnlyStore '10EC' 'C:\Windows' { param($p) $false } { param($p) '' })) {
    $fail += 'Realtek fallback selected an Intel driver package'
  }

  # 3b. The RTL8821CU USB dongle (0BDA:C820): selected while bound to nekodrop's
  # WinUSB package, selected by its catalog ID once Realtek's driver is on it,
  # its MI_02 function node never picked, and its vendor package found under 0BDA.
  $usbBound = @((Dev 'USB\VID_0BDA&PID_C820\123456' 'WINUSB' 'oem44.inf' 'winairdrop project'))
  if ($null -eq (Resolve-RestoreTargetDevice $usbBound $pubProxy)) { $fail += 'USB dongle bound to WINUSB was not selected' }
  $usbVendor = @((Dev 'USB\VID_0BDA&PID_C820\123456' 'rtwlanu' 'oem20.inf' 'Realtek Semiconductor Corp.'))
  if ($null -eq (Resolve-RestoreTargetDevice $usbVendor $pubProxy)) { $fail += 'USB dongle on Realtek''s driver was not selected' }
  $usbFunction = @(
    (Dev 'USB\VID_0BDA&PID_C820&REV_0200&MI_02\B&1' 'rtwlanu' 'oem20.inf' 'Realtek Semiconductor Corp.'),
    (Dev 'USB\VID_0BDA&PID_8812\1' '' '' '')
  )
  if ($null -ne (Resolve-RestoreTargetDevice $usbFunction $pubProxy)) { $fail += 'a USB function node or an unsupported USB ID was selected' }
  $usbPkg = Select-VendorInfPackage @() $store '0BDA' 'C:\Windows' { param($p) $false } { param($p) '' }
  if ($usbPkg -ne 'C:\Windows\INF\oem21.inf') { $fail += "USB Realtek store fallback picked '$usbPkg', want oem21.inf" }
  if ((Get-DeviceVendor 'USB\VID_0BDA&PID_C820&REV_0200&MI_02\B&1').HardwareId -ne 'USB\VID_0BDA&PID_C820') { $fail += 'USB hardware ID wrong' }

  # 4. Other known vendor profiles (MediaTek, Qualcomm, Broadcom) and unknown vendor -> $null.
  if ((Select-VendorInfPackage @() $store '14C3' 'C:\Windows' { param($p) $false } { param($p) '' }) -ne 'C:\Windows\INF\oem30.inf') { $fail += 'MediaTek fallback failed' }
  if ((Select-VendorInfPackage @() $store '17CB' 'C:\Windows' { param($p) $false } { param($p) '' }) -ne 'C:\Windows\INF\oem31.inf') { $fail += 'Qualcomm fallback failed' }
  if ((Select-VendorInfPackage @() $store '14E4' 'C:\Windows' { param($p) $false } { param($p) '' }) -ne 'C:\Windows\INF\oem32.inf') { $fail += 'Broadcom fallback failed' }
  if ($null -ne (Select-VendorInfPackage @() $store '1AE0' 'C:\Windows' { param($p) $false } { param($p) '' })) { $fail += 'unknown vendor selected a driver package' }

  # 5. Unknown PCI device bound to WUDFRd + nekodrop's INF IS selected, while
  # unrelated WUDFRd PCI device (sensors.inf) is strictly ignored.
  $mixedDevs = @(
    (Dev 'PCI\VEN_8086&DEV_9D3A&SUBSYS_00008086\3&1' 'WUDFRd' 'oem5.inf' 'Microsoft' 'PCI Sensor'),
    (Dev 'PCI\VEN_14C3&DEV_7922&SUBSYS_7922103C\4&1' 'WUDFRd' 'oem42.inf' 'winairdrop project' 'WinAwdl Radio')
  )
  $pickedBound = Resolve-RestoreTargetDevice $mixedDevs $pubProxy
  if (-not $pickedBound -or $pickedBound.InstanceId -notmatch 'DEV_7922') { $fail += 'device bound to nekodrop proxy was not selected' }
  $sensorOnly = @((Dev 'PCI\VEN_8086&DEV_9D3A&SUBSYS_00008086\3&1' 'WUDFRd' 'oem5.inf' 'Microsoft' 'PCI Sensor'))
  if ($null -ne (Resolve-RestoreTargetDevice $sensorOnly $pubProxy)) { $fail += 'unrelated WUDFRd sensor device was wrongly selected' }
  $kdrvOnly = @((Dev 'PCI\VEN_1234&DEV_5678&SUBSYS_00001234\4&1' 'nekodrop-wlan' 'oem43.inf' 'winairdrop project' 'nekodrop WLAN'))
  if ($null -eq (Resolve-RestoreTargetDevice $kdrvOnly $pubProxy)) { $fail += 'device bound to nekodrop-wlan was not selected' }
  $provOnly = @((Dev 'PCI\VEN_1234&DEV_5679&SUBSYS_00001234\4&1' 'WUDFRd' 'oem99.inf' 'winairdrop project' 'WinAwdl Radio'))
  if ($null -eq (Resolve-RestoreTargetDevice $provOnly @())) { $fail += 'device with winairdrop project provider was not selected' }
  $failedBind = @((Dev 'PCI\VEN_1234&DEV_567A&SUBSYS_00001234\4&1' '' 'oem42.inf' 'winairdrop project' 'WinAwdl Radio'))
  if ($null -eq (Resolve-RestoreTargetDevice $failedBind $pubProxy)) { $fail += 'device with failed proxy bind (empty service, our INF/provider) was not selected' }
  $vendorBound = @((Dev 'PCI\VEN_1234&DEV_567B&SUBSYS_00001234\4&1' 'VendorWlan' 'oem42.inf' 'winairdrop project' 'Vendor WLAN'))
  if ($null -ne (Resolve-RestoreTargetDevice $vendorBound $pubProxy)) { $fail += 'device running an unrelated vendor service was wrongly selected' }

  # 6. Precedence: vendor-inf.txt > service.json > driver store, plus poisoned
  # VendorInf (#12) and untrusted path rejection.
  $mockFiles = @{
    'C:\Windows\INF\oem77.inf' = '[Version] Provider = %INTEL%'
    'C:\Windows\INF\oem78.inf' = '[Version] Provider = %INTEL%'
    'C:\Windows\INF\oem79.inf' = '[Version] Provider = "winairdrop project" ; winawdl_regproxy'
    'C:\Windows\INF\oem80.inf' = '[Strings] ServiceDesc = "nekodrop-wlan driver"'
    'C:\Windows\INF\oem42.inf' = '[Version] Provider = %BENIGN%'
    'C:\Temp\evil.inf'         = '[Version] Provider = %INTEL%'
  }
  $existsFn = { param($p) $mockFiles.ContainsKey($p) }
  $readFn   = { param($p) if ($mockFiles.ContainsKey($p)) { $mockFiles[$p] } else { '' } }
  $p1 = Select-VendorInfPackage @('C:\Windows\INF\oem77.inf', 'C:\Windows\INF\oem78.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p1 -ne 'C:\Windows\INF\oem77.inf') { $fail += "vendor-inf.txt did not win over service.json: got '$p1'" }
  $p2 = Select-VendorInfPackage @('C:\Windows\INF\oem79.inf', 'C:\Windows\INF\oem78.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p2 -ne 'C:\Windows\INF\oem78.inf') { $fail += "poisoned winawdl_regproxy INF was not rejected: got '$p2'" }
  $p3 = Select-VendorInfPackage @('C:\Windows\INF\oem79.inf', 'C:\Windows\INF\oem80.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p3 -ne 'C:\Windows\INF\oem11.inf') { $fail += "all-poisoned recorded INFs did not fall back to store: got '$p3'" }
  $p4 = Select-VendorInfPackage @('C:\Windows\INF\oem42.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p4 -ne 'C:\Windows\INF\oem11.inf') { $fail += "published proxy oem42.inf was not rejected: got '$p4'" }
  $p5 = Select-VendorInfPackage @('C:\Temp\evil.inf', 'C:\Windows\INF\..\Temp\evil.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p5 -ne 'C:\Windows\INF\oem11.inf') { $fail += "untrusted VendorInf path outside %windir%\INF was not rejected: got '$p5'" }
  $p6 = Select-VendorInfPackage @('oem77.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p6 -ne 'C:\Windows\INF\oem77.inf') { $fail += "bare leaf vendor-inf.txt entry did not resolve: got '$p6'" }
  $p7 = Select-VendorInfPackage @('oem42.inf', 'oem79.inf') $store '8086' 'C:\Windows' $existsFn $readFn
  if ($p7 -ne 'C:\Windows\INF\oem11.inf') { $fail += "bare leaf poisoned proxy INF was not rejected: got '$p7'" }

  if ($fail) { $fail | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
  Write-Host 'restore.ps1 self-test: target resolution, multi-vendor driver selection and poisoned-INF guards passed'
  exit 0
}

# --------------------------------------------------------------- elevation
# What "#Requires -RunAsAdministrator" did, before anything is written.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'restore.ps1 needs administrator rights: run it from an administrator PowerShell, or double-click restore.cmd.'
  exit 1
}

$state = Join-Path $env:ProgramData 'nekodrop'
New-Item -ItemType Directory -Force $state | Out-Null
Start-Transcript (Join-Path $state 'restore.log') -Force | Out-Null

'1. Stopping nekodrop'
$svc = Get-Service NekoDropService -ErrorAction SilentlyContinue
if ($svc) {
  Stop-Service NekoDropService -Force -ErrorAction SilentlyContinue
  Set-Service NekoDropService -StartupType Disabled
  '   service stopped and disabled'
}
Get-Process nekodrop-radio, nekodrop-radio-rtl, nekodrop-radio-mt, nekodrop-radio-mtk, awdld -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*airdrop*engine.py*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

'2. Giving the Wi-Fi card back to its vendor driver'
$storeDrivers = @()
try {
  $storeXml = [xml](pnputil /enum-drivers /format xml | Out-String)
  if ($storeXml -and $storeXml.PnpUtil -and $storeXml.PnpUtil.Driver) {
    $storeDrivers = @($storeXml.PnpUtil.Driver)
  }
} catch { }
$nekodropInfs = @(Get-NekodropPublishedInfs $storeDrivers)

$presentCandidates = @(Get-PnpDevice -PresentOnly | Where-Object { $_ -and (Get-DeviceVendor $_.InstanceId) })
$pciCandidates = foreach ($p in $presentCandidates) {
  $pciInfo = Get-DeviceVendor $p.InstanceId
  $svcName = "$($p.Service)".Trim()
  $needProps = ($ProxyServices -contains $svcName) -or ($KnownCatalogIds -contains $pciInfo.Key) -or
               ("$($p.Class)" -in 'WinAwdlRadio', 'Net', 'Unknown', '')
  if (-not $needProps) { continue }
  $propSvc = (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
  $propInf = (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_DriverInfPath -ErrorAction SilentlyContinue).Data
  $propProv = (Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName DEVPKEY_Device_DriverProvider -ErrorAction SilentlyContinue).Data
  [pscustomobject]@{
    InstanceId     = $p.InstanceId
    FriendlyName   = $p.FriendlyName
    Status         = $p.Status
    Service        = $(if ($propSvc) { "$propSvc" } else { $svcName })
    DriverInfPath  = $(if ($propInf) { "$propInf" } else { '' })
    DriverProvider = $(if ($propProv) { "$propProv" } else { '' })
  }
}
$dev = Resolve-RestoreTargetDevice $pciCandidates $nekodropInfs
if (-not $dev) {
  '   no Wi-Fi card nekodrop knows or holds is present; nothing to give back'
} else {
  $pci = Get-DeviceVendor $dev.InstanceId
  $profile = Get-VendorProfile $pci.VendorId
  "   card: $($dev.InstanceId), now $($dev.FriendlyName) ($($dev.Status))"
  # Vendor package: the one nekodrop recorded before taking the card (validated
  # so a poisoned proxy INF is never reused), else the newest matching Net
  # package in the driver store for this PCI vendor.
  $recorded = @()
  foreach ($f in (Join-Path $state 'vendor-inf.txt'), (Join-Path $state 'service.json')) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $text = Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue
    if ($f -like '*.json') { try { $text = ($text | ConvertFrom-Json).VendorInf } catch { $text = $null } }
    if ($text) { $recorded += $text.Trim() }
  }
  $vendor = Select-VendorInfPackage $recorded $storeDrivers $pci.VendorId $env:windir
  $bound = $false
  if ($pci.Bus -eq 'USB') {
    # A WinUSB-bound USB dongle cannot be handed to the vendor's INF in place:
    # that package matches the composite's Wi-Fi function (MI_02), which only
    # exists once Windows' own composite driver is back. Removing nekodrop's
    # package and re-detecting below is what does it (verified on hardware).
    "   USB dongle: removing nekodrop's WinUSB package and re-detecting it"
  } elseif ($vendor) {
    "   binding $vendor"
    $hwid = $pci.HardwareId
    # INSTALLFLAG_FORCE: the vendor's INF ranks higher anyway, but the proxy is bound now.
    $job = Start-Job -ScriptBlock {
      param($h, $v)
      Add-Type -Namespace NekoRestore -Name NewDev -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("newdev.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool UpdateDriverForPlugAndPlayDevicesW(System.IntPtr hwnd, string hardwareId, string infPath, uint flags, out bool reboot);
'@
      $r = $false
      [NekoRestore.NewDev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $h, $v, 1, [ref]$r)
    } -ArgumentList $hwid, $vendor
    # The call has been seen to block for minutes: wait at most 90 s, then check.
    if (Wait-Job $job -Timeout 90) { $bound = [bool](Receive-Job $job | Select-Object -Last 1) }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
  } else {
    "   $($profile.Name)'s driver package was not found in the driver store"
  }

  '3. Removing nekodrop''s driver packages'
  try {
    $store = [xml](pnputil /enum-drivers /format xml | Out-String)
    if ($store -and $store.PnpUtil -and $store.PnpUtil.Driver) {
      $store.PnpUtil.Driver |
        Where-Object { [IO.Path]::GetFileName("$($_.OriginalName)".Trim()) -in $ProxyInfNames } |
        ForEach-Object { pnputil /delete-driver $_.DriverName /uninstall /force | Out-Null; "   removed $($_.OriginalName) ($($_.DriverName))" }
    }
  } catch { }

  # If the bind did not take, let Plug and Play choose again: with nekodrop's
  # packages gone, the vendor's is the best match left.
  $now = Get-PnpDevice -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue
  $service = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
  if (-not $bound -or $service -in $ProxyServices) {
    '   re-detecting the card'
    pnputil /remove-device $dev.InstanceId | Out-Null
    pnputil /scan-devices | Out-Null
    Start-Sleep 5
  }
}

'4. Saved Wi-Fi networks'
# The service backs up Windows' saved networks before taking the card; add
# back any the Wi-Fi interface lacks now (it can come back under a new GUID).
$backup = Join-Path $state 'wlan-backup'
if (Test-Path $backup) {
  Start-Service WlanSvc -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 30 -and -not ((netsh wlan show interfaces | Out-String) -match 'GUID'); $i++) { Start-Sleep 1 }
  # The interface's own profiles, read back through netsh (its text output is localized).
  $tmp = Join-Path $state 'wlan-current'
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $tmp | Out-Null
  netsh wlan export profile folder="$tmp" | Out-Null
  $have = @(Get-ChildItem $tmp -Filter *.xml | ForEach-Object { try { ([xml](Get-Content $_.FullName -Raw)).WLANProfile.name } catch { } })
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  $added = 0
  foreach ($f in Get-ChildItem $backup -Filter *.xml) {
    try { $name = ([xml](Get-Content $f.FullName -Raw)).WLANProfile.name } catch { continue }
    if ($have -contains $name) { continue }
    netsh wlan add profile filename="$($f.FullName)" user=all | Out-Null
    if ($LASTEXITCODE -eq 0) { $added++ }
  }
  "   restored $added saved network(s)"
} else {
  '   no backup (nekodrop before 0.1.9 kept none)'
}

'5. Network'
Get-NetAdapter -Name nekodrop -ErrorAction SilentlyContinue | Disable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service WlanSvc -ErrorAction SilentlyContinue

''
$after = if ($dev) {
  Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -eq $dev.InstanceId } | Select-Object -First 1
}
if (-not $after -and $dev) {
  $after = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
    (Get-DeviceVendor $_.InstanceId) -and (Get-DeviceVendor $_.InstanceId).Key -eq $pci.Key
  } | Select-Object -First 1
}
if ($after) {
  $afterPci = Get-DeviceVendor $after.InstanceId
  $afterProfile = Get-VendorProfile $(if ($afterPci) { $afterPci.VendorId } else { '' })
  $service = (Get-PnpDeviceProperty -InstanceId $after.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
  "Wi-Fi card: $($after.FriendlyName), driver service $service, status $($after.Status)"
  if ($service -in $ProxyServices) {
    if ($afterProfile.VendorId -eq '8086') {
      'The card is still not on Intel''s driver. Restart the PC; if Wi-Fi is still missing, install Intel''s Wi-Fi driver from intel.com or Windows Update.'
    } else {
      "The card is still not on $($afterProfile.Name)'s driver. Restart the PC; if Wi-Fi is still missing, install $($afterProfile.Name)'s Wi-Fi driver from $($afterProfile.DownloadHint)."
    }
  } else {
    'Done: Windows Wi-Fi is back. A restart is not needed, but does no harm.'
  }
}
if ($Uninstall) {
  $un = Join-Path $env:ProgramFiles 'nekodrop\uninstall.ps1'
  if (Test-Path $un) { 'Uninstalling nekodrop'; & $un }
}
Stop-Transcript | Out-Null
