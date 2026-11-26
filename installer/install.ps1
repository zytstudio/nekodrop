# Installs nekodrop from the staged folder it sits in. Changes, in order:
#   1. copies the files to %ProgramFiles%\nekodrop
#   2. makes a code-signing certificate on this PC, trusts it, signs the
#      register-proxy driver with it and deletes its private key (nothing else
#      can ever be signed with what this PC now trusts); adds the driver to the
#      driver store, which takes over nothing by itself
#   3. installs TAP-Windows if no tap0901 adapter exists (concurrent mode)
#   4. two inbound firewall rules, link-local addresses only
#   5. the NekoDropService service, started
# The Wi-Fi card is only taken by the service, and given back on uninstall.
# -DryRun says what would happen and changes nothing.
# -SelfTest checks the card classification and the refusal message below
# against made-up devices and exits 0 (all pass) or 1; it needs no
# administrator rights and no card, and changes and writes nothing.
#
# Needs administrator rights. There is no "#Requires -RunAsAdministrator": it
# is checked while the script is parsed, before param(), so -SelfTest could not
# run on a build machine without them. The same check is made below instead,
# before anything is written.
param([switch]$DryRun, [string]$Target = "$env:ProgramFiles\nekodrop", [switch]$SelfTest)
$ErrorActionPreference = 'Stop'

# ------------------------------------------------ Wi-Fi card classification
# Without a supported card the setup said only "no Intel Wi-Fi card nekodrop
# supports", so an RTL8852CE owner did not learn that winawdl runs their card,
# and nobody learned which ID to post (docs/HARDWARE.md, step 4). The setup
# runs this script from its own temporary folder, alone: the tables below match
# installer/report.ps1's, and -SelfTest fails when they drift apart (or from
# restore.ps1's supported IDs).
#
# The supported IDs are iwxradio/src/cards.h's kDeviceIds, the register
# proxy's INF, report.ps1's, restore.ps1's and install.ps1's check: keep them in step.
$SupportedIntelIds = @('43F0', 'A0F0', '02F0', '06F0', '34F0', '3DF0', '4DF0', '2723', '2725', '7A70', '7AF0', '51F0', '51F1', '54F0', '7F70')
# Known Wi-Fi chips, 'vendor:device' -> kind, name. Used to name the chip and to
# find a card that has no driver (it is then no network adapter). Never used to
# call a device wireless by its vendor alone: Intel and Realtek make Ethernet
# chips too (10EC:8168, 8086:15xx), which must not show up here.
$WifiChips = @{
  # Intel cards cards.h knows but cannot run: no firmware upstream.
  '8086:2720' = @('intel-fw', 'Intel QnJ')
  '8086:2726' = @('intel-fw', 'Intel SnJ')
  '8086:2729' = @('intel-fw', 'Intel Ma (Meteor Lake CNVi)')
  '8086:7E40' = @('intel-fw', 'Intel Ma (Meteor Lake CNVi)')
  # Intel Wi-Fi 7 (Linux iwlwifi's Bz/Gl/Sc device IDs): BE200 is experimental
  # (Concurrent and on-demand); CNVi Wi-Fi 7 cards have no driver yet.
  '8086:272B' = @('intel-be-exp', 'Intel BE200 (Wi-Fi 7)')
  '8086:A840' = @('intel-be', 'Intel BE201/BE211 (Wi-Fi 7, CNVi)')
  '8086:7740' = @('intel-be', 'Intel BE201/BE211 (Wi-Fi 7, CNVi)')
  '8086:E440' = @('intel-be', 'Intel Wi-Fi 7 (CNVi)')
  '8086:E340' = @('intel-be', 'Intel Wi-Fi 7 (CNVi)')
  '8086:D340' = @('intel-be', 'Intel Wi-Fi 7 (CNVi)')
  # Realtek (Linux rtw88/rtw89 device IDs). RTL8852CE is natively supported
  # via nekodrop's built-in devourer backend (on-demand AirDrop).
  '10EC:C852' = @('supported-rtl', 'Realtek RTL8852CE')
  # Realtek RTL8821CU: a USB dongle driven over libusb (nekodrop-radio-usb.exe).
  '0BDA:C820' = @('supported-rtl-usb', 'Realtek RTL8821CU (USB)')
  '0BDA:C821' = @('supported-rtl-usb', 'Realtek RTL8821CU (USB)')
  # MediaTek MT7902: built-in mt76 port (nekodrop-radio-mt.exe, 5 GHz Wi-Fi beside AirDrop or on-demand).
  '14C3:7902' = @('supported-mtk', 'MediaTek MT7902')
  '10EC:8852' = @('rtl', 'Realtek RTL8852AE')
  '10EC:A85A' = @('rtl', 'Realtek RTL8852AE')
  '10EC:B852' = @('rtl', 'Realtek RTL8852BE')
  '10EC:B85B' = @('rtl', 'Realtek RTL8852BE')
  '10EC:B851' = @('rtl', 'Realtek RTL8851BE')
  '10EC:8922' = @('rtl', 'Realtek RTL8922AE')
  '10EC:C822' = @('rtl', 'Realtek RTL8822CE')
  '10EC:B822' = @('rtl', 'Realtek RTL8822BE')
  '10EC:C821' = @('rtl', 'Realtek RTL8821CE')
  '10EC:D723' = @('rtl', 'Realtek RTL8723DE')
  '10EC:B723' = @('rtl', 'Realtek RTL8723BE')
  # MediaTek, also sold as AMD RZ6xx/RZ7xx (Linux mt76).
  '14C3:7961' = @('supported-mtk', 'MediaTek MT7921')
  '14C3:0608' = @('supported-mtk', 'MediaTek MT7921 (AMD RZ608)')
  '14C3:7922' = @('supported-mtk', 'MediaTek MT7922')
  '14C3:0616' = @('supported-mtk', 'MediaTek MT7922 (AMD RZ616)')
  '14C3:7925' = @('mtk', 'MediaTek MT7925')
  '14C3:0717' = @('mtk', 'MediaTek MT7925 (AMD RZ717)')
  '14C3:7927' = @('mtk', 'MediaTek MT7927 (Wi-Fi 7)')
  '14C3:7663' = @('mtk', 'MediaTek MT7663')
  '14C3:7615' = @('mtk', 'MediaTek MT7615')
  # Qualcomm (Linux ath11k/ath12k) and Qualcomm Atheros (ath10k/ath9k).
  '17CB:1101' = @('qcom', 'Qualcomm QCA6390')
  '17CB:1103' = @('qcom', 'Qualcomm WCN6855 (FastConnect 6800/6900)')
  '17CB:1107' = @('qcom', 'Qualcomm WCN7850 (FastConnect 7800)')
  '168C:003E' = @('qcom', 'Qualcomm Atheros QCA6174')
  '168C:0042' = @('qcom', 'Qualcomm Atheros QCA9377')
  '168C:0036' = @('qcom', 'Qualcomm Atheros QCA9565')
  '168C:0034' = @('qcom', 'Qualcomm Atheros AR9462')
  '168C:0032' = @('qcom', 'Qualcomm Atheros AR9485')
  # Broadcom (Linux brcmfmac/b43/wl).
  '14E4:43A0' = @('bcm', 'Broadcom BCM4360')
  '14E4:43B1' = @('bcm', 'Broadcom BCM4352')
  '14E4:43A3' = @('bcm', 'Broadcom BCM4350')
  '14E4:43BA' = @('bcm', 'Broadcom BCM43602')
  '14E4:4464' = @('bcm', 'Broadcom BCM4364')
  '14E4:4331' = @('bcm', 'Broadcom BCM4331')
  '14E4:4353' = @('bcm', 'Broadcom BCM43224')
  '14E4:4357' = @('bcm', 'Broadcom BCM43225')
}
# kind -> what the report says, and a hint for the reader (may be empty).
$WifiKinds = @{
  'supported'     = @('supported by nekodrop', '')
  'supported-mtk' = @('supported by nekodrop (5 GHz Wi-Fi beside AirDrop, or on-demand; built-in MediaTek backend)', 'Joins 5 GHz Wi-Fi beside AirDrop, or runs on demand while Windows keeps Wi-Fi.')
  'supported-rtl' = @('supported by nekodrop (on-demand AirDrop, built-in RTL8852CE backend)', 'Windows keeps Wi-Fi normally; nekodrop takes the card only during AirDrop transfers.')
  'supported-rtl-usb' = @('supported by nekodrop (experimental; USB dongle, on-demand AirDrop, built-in RTL8821CU backend)', 'nekodrop keeps this dongle: it is bound to nekodrop''s WinUSB driver, so the dongle has no Wi-Fi of its own from the first AirDrop on. Start menu > nekodrop - restore Windows Wi-Fi gives it back.')
  'intel-fw'      = @('not supported: its firmware is not shipped upstream', 'nekodrop runs the Intel cards whose firmware ForbiddenItlwm ships (API 68); this one has none there.')
  'intel-be-exp'  = @('supported by nekodrop (experimental, Concurrent Wi-Fi beside AirDrop or on-demand, not yet run on a real card)', 'Joins Wi-Fi beside AirDrop or runs on demand while Windows keeps Wi-Fi. Please post a diagnostic report in an issue whether it works or not.')
  'intel-be'      = @('not supported: Intel Wi-Fi 7, no upstream driver', 'ForbiddenItlwm, which nekodrop ports, has no driver for Wi-Fi 7 cards yet.')
  'intel-other'   = @('not supported: an Intel device ID nekodrop does not know', 'Please post this report in an issue: if upstream ships firmware for this card, its ID can be added.')
  'rtl'           = @('not supported: Realtek', 'Among Realtek chips, nekodrop currently has built-in support for RTL8852CE (10EC:C852) only.')
  'mtk'           = @('not supported: MediaTek', 'Among MediaTek chips, nekodrop currently has built-in support for MT7902, MT7921 (RZ608), and MT7922 (RZ616) only.')
  'qcom'          = @('not supported: Qualcomm', 'No user-mode Windows driver exists for Qualcomm Wi-Fi yet.')
  'bcm'           = @('not supported: Broadcom', 'There is no open Windows driver path for Broadcom Wi-Fi.')
  'usb'           = @('not supported: USB adapter', 'nekodrop drives PCIe cards only.')
  'other'         = @('not supported: unrecognized wireless adapter', '')
}
$WifiVendors = @{ '8086' = 'Intel'; '10EC' = 'Realtek'; '14C3' = 'MediaTek'; '17CB' = 'Qualcomm'; '168C' = 'Qualcomm Atheros'; '14E4' = 'Broadcom'
                  '0BDA' = 'Realtek'; '0E8D' = 'MediaTek'; '148F' = 'MediaTek (Ralink)'; '0CF3' = 'Qualcomm Atheros'; '8087' = 'Intel' }

function Classify-WifiCard([string]$InstanceId, [string]$FriendlyName = '') {
  $id = "$InstanceId".ToUpper()
  $parts = $id -split '\\'
  $bus = $parts[0]
  $vendor = ''; $device = ''
  if ($id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})(?:&|\\|$)') { $vendor = $Matches[1]; $device = $Matches[2] }
  elseif ($id -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})(?:&|\\|$)') { $vendor = $Matches[1]; $device = $Matches[2] }
  $kind = 'other'; $chip = ''
  if ($bus -eq 'USB') {
    # A USB dongle nekodrop drives (RTL8821CU) is in the table; every other USB
    # wireless adapter is refused as before.
    $usbKey = $vendor + ':' + $device
    if ($vendor -and $WifiChips.ContainsKey($usbKey)) { $kind = $WifiChips[$usbKey][0]; $chip = $WifiChips[$usbKey][1] }
    else { $kind = 'usb' }
  }
  elseif ($bus -eq 'PCI' -and $vendor) {
    $key = $vendor + ':' + $device
    if ($vendor -eq '8086' -and $SupportedIntelIds -contains $device) { $kind = 'supported'; $chip = 'Intel Wi-Fi 6/6E' }
    elseif ($WifiChips.ContainsKey($key)) { $kind = $WifiChips[$key][0]; $chip = $WifiChips[$key][1] }
    else {
      # Only reached for a device already known to be wireless (by its medium
      # or name), so the vendor is enough to say which family it is.
      $byVendor = @{ '8086' = 'intel-other'; '10EC' = 'rtl'; '14C3' = 'mtk'; '17CB' = 'qcom'; '168C' = 'qcom'; '14E4' = 'bcm' }
      if ($byVendor.ContainsKey($vendor)) { $kind = $byVendor[$vendor] }
    }
  }
  $vendorName = if ($WifiVendors.ContainsKey($vendor)) { $WifiVendors[$vendor] } elseif ($vendor) { "vendor $vendor" } else { 'unknown vendor' }
  if (-not $chip) { $chip = if ($device) { "$vendorName $device (not in nekodrop's table)" } else { "$vendorName (not in nekodrop's table)" } }
  return [pscustomobject]@{
    Bus = $bus; Vendor = $vendorName; VendorId = $vendor; DeviceId = $device
    HardwareId = $(if ($parts.Count -gt 1) { $parts[1] } else { $id })
    Chip = $chip; Family = $chip; Kind = $kind; Status = $WifiKinds[$kind][0]; Note = $WifiKinds[$kind][1]
  }
}
# A known Wi-Fi chip by its PCI or USB ID (supported or not).
function Test-KnownWifiId([string]$InstanceId) {
  $c = Classify-WifiCard $InstanceId
  if (-not $c.VendorId) { return $false }
  return ($c.Kind -eq 'supported' -or $WifiChips.ContainsKey($c.VendorId + ':' + $c.DeviceId))
}

# ------------------------------------------------------ the refusal message
# The supported-card check: exact 15 Intel IDs plus Realtek RTL8852CE
# (10EC:C852), the Realtek RTL8821CU USB dongle (0BDA:C820, C821) and MediaTek
# MT7902/MT7921/MT7922, with a 4-hex boundary so a 5-digit device ID (e.g.
# DEV_43F01 or DEV_C8520) can never match.
$SupportedCardPattern = '^(?:PCI\\(?:VEN_8086&DEV_(' + ($SupportedIntelIds -join '|') + ')|VEN_8086&DEV_272B|VEN_10EC&DEV_C852|VEN_14C3&DEV_(7902|7961|0608|7922|0616))|USB\\VID_0BDA&PID_(C820|C821))(?=&|\\|$)'
$NoSupportedCard = 'This PC has no Wi-Fi card nekodrop supports (Intel AX201, AX200, AX210, AX211, AX411, 9560 on Qu, BE200 (experimental), Realtek RTL8852CE 10EC:C852, Realtek RTL8821CU USB 0BDA:C820, or MediaTek MT7902/MT7921/MT7922); nekodrop cannot run here.'
$ReportUrl = 'https://github.com/zheznanohana/nekodrop/blob/main/installer/report.ps1'
$IssuesUrl = 'https://github.com/zheznanohana/nekodrop/issues'
# Adapter names that say wireless. As report.ps1: not bare "Killer" (its
# Ethernet chips E2600/E3100 use it too). The CJK words are \u escapes so this
# file stays ASCII: Windows PowerShell 5.1 reads a file without a BOM in the
# ANSI code page.
$WifiNamePattern = 'Wi-?Fi|Wireless|802\.11|WLAN|RZ[67]\d\d|FastConnect|Killer.*(?:AX|BE|1[4567]\d\d)|\u65E0\u7EBF|\u7121\u7DDA'

# The wireless cards present, up to 5, PCIe first: report.ps1's three sources
# (adapters whose medium is native 802.11, known Wi-Fi chip IDs, adapter
# names), physical devices only. Takes the device and adapter lists instead of
# reading them, so -SelfTest can feed made-up ones.
function Select-WirelessDevices($Pnp, $Adapters) {
  $candidates = @()
  foreach ($a in @($Adapters | Where-Object { $_ })) {
    if ($a.PnPDeviceID -and ($a.NdisPhysicalMedium -eq 9 -or "$($a.PhysicalMediaType)" -match '802\.11|Wireless')) {
      $candidates += @($Pnp | Where-Object { $_.InstanceId -eq $a.PnPDeviceID })
    }
  }
  $candidates += @($Pnp | Where-Object { $_ -and (Test-KnownWifiId $_.InstanceId) })
  $candidates += @($Pnp | Where-Object { $_ -and $_.Class -eq 'Net' -and "$($_.FriendlyName)" -match $WifiNamePattern })
  $seen = @{}
  $found = foreach ($d in $candidates) {
    if (-not $d -or "$($d.InstanceId)" -notmatch '^(PCI|USB)\\') { continue }
    $k = "$($d.InstanceId)".ToUpper()
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = $true
    $d
  }
  return @($found | Where-Object { $_ } | Sort-Object { if ($_.InstanceId -match '^PCI\\') { 0 } else { 1 } } | Select-Object -First 5)
}

# Text as is if it is printable ASCII, else ''. The setup reads
# install-error.txt as an ANSI string: a device name in Chinese or with a
# trademark sign would come out garbled, so such a name is left out (the chip
# name from the table says what the card is anyway).
function ConvertTo-AsciiText([string]$Text) {
  if ("$Text" -cmatch '^[\x20-\x7E]*$') { return "$Text" }
  return ''
}

# The refusal: which wireless cards are there, their IDs without the instance
# part (a USB adapter's serial is often its MAC address), why nekodrop does not
# run on them, winawdl for an RTL8852CE, and how to get a card supported.
function Format-UnsupportedCardMessage($Devices) {
  $lines = @($NoSupportedCard)
  $devs = @($Devices | Where-Object { $_ })
  if ($devs.Count) {
    $lines += 'Wireless card(s) found on this PC:'
    foreach ($d in $devs) {
      $c = Classify-WifiCard $d.InstanceId
      $id = if (-not $c.VendorId) { $c.Bus }
            elseif ($c.Bus -eq 'USB') { "USB\VID_$($c.VendorId)&PID_$($c.DeviceId)" }
            else { "$($c.VendorId):$($c.DeviceId), PCI\VEN_$($c.VendorId)&DEV_$($c.DeviceId)" }
      $id = ConvertTo-AsciiText $id
      $name = (ConvertTo-AsciiText $d.FriendlyName).Trim()
      if (-not $name) { $name = (ConvertTo-AsciiText $d.Name).Trim() }
      $label = if ($name) { "$name ($id)" } else { $id }
      $lines += "- $($label): $($c.Chip), $($c.Status)."
      if ($c.Note) {
        $lines += "  $($c.Note)"
      }
    }
  } else {
    $lines += 'No wireless card was found on this PC (a card turned off in the BIOS or by a hardware switch does not show up).'
  }
  $lines += 'To get a card supported, run the diagnostic report (it needs no nekodrop install):'
  $lines += '  download:'
  $lines += "  $ReportUrl"
  $lines += '  run: powershell -ExecutionPolicy Bypass -File report.ps1'
  $lines += '  post the report it puts on the Desktop at:'
  $lines += "  $IssuesUrl"
  # Every line is ASCII by construction; this only guards against a future edit.
  return ($lines | ForEach-Object { ConvertTo-AsciiText $_ }) -join "`r`n"
}

if ($SelfTest) {
  $fail = @()
  function Dev([string]$id, [string]$name = '', [string]$class = 'Net') {
    [pscustomobject]@{ InstanceId = $id; FriendlyName = $name; Name = $name; Class = $class }
  }
  function Nic([string]$pnpId, $medium, [string]$mediaType = '') {
    [pscustomobject]@{ PnPDeviceID = $pnpId; NdisPhysicalMedium = $medium; PhysicalMediaType = $mediaType }
  }
  function Ascii([string]$s) { return ("$s" -cmatch '^[\x09\x0A\x0D\x20-\x7E]*$') }

  # The supported-card check: exact 15 Intel IDs + Realtek RTL8852CE + RTL8821CU USB + MediaTek MT7902/MT7921/MT7922 with 4-hex boundary.
  if ($SupportedCardPattern -ne '^(?:PCI\\(?:VEN_8086&DEV_(43F0|A0F0|02F0|06F0|34F0|3DF0|4DF0|2723|2725|7A70|7AF0|51F0|51F1|54F0|7F70)|VEN_8086&DEV_272B|VEN_10EC&DEV_C852|VEN_14C3&DEV_(7902|7961|0608|7922|0616))|USB\\VID_0BDA&PID_(C820|C821))(?=&|\\|$)') {
    $fail += "supported-card pattern changed: $SupportedCardPattern"
  }
  foreach ($mtkDev in '7902', '7961', '0608', '7922', '0616') {
    if ("PCI\VEN_14C3&DEV_$mtkDev&SUBSYS_60401A3B&REV_00\4&1" -notmatch $SupportedCardPattern) { $fail += "14C3:$mtkDev not accepted" }
    if ("PCI\VEN_14C3&DEV_$($mtkDev)1&SUBSYS_60401A3B" -match $SupportedCardPattern) { $fail += "5-digit DEV_$($mtkDev)1 matched as MediaTek" }
    if ((Classify-WifiCard "PCI\VEN_14C3&DEV_$mtkDev&SUBSYS_60401A3B").Kind -ne 'supported-mtk') { $fail += "14C3:$mtkDev not classified as supported-mtk" }
  }
  if ('PCI\VEN_14C3&DEV_7925&SUBSYS_792514C3' -match $SupportedCardPattern) { $fail += '14C3:7925 accepted as supported' }
  foreach ($d in $SupportedIntelIds) {
    if ("PCI\VEN_8086&DEV_$d&SUBSYS_00748086&REV_00\3&11583659&0&A3" -notmatch $SupportedCardPattern) { $fail += "8086:$d not accepted" }
    if ("PCI\VEN_8086&DEV_$d" -notmatch $SupportedCardPattern) { $fail += "8086:$d bare ID not accepted" }
    if ("PCI\VEN_8086&DEV_$d\3&1" -notmatch $SupportedCardPattern) { $fail += "8086:$d backslash ID not accepted" }
    if ("pci\ven_8086&dev_$($d.ToLower())&subsys_00748086" -notmatch $SupportedCardPattern) { $fail += "8086:$d not accepted in lower case" }
    if ((Classify-WifiCard "PCI\VEN_8086&DEV_$d&SUBSYS_00748086").Kind -ne 'supported') { $fail += "8086:$d not classified as supported" }
  }
  # Built-in Realtek RTL8852CE (10EC:C852): accepted in all forms and classified as supported-rtl.
  foreach ($okRtl in 'PCI\VEN_10EC&DEV_C852&SUBSYS_C85210EC&REV_00\4&1&0&00E8', 'PCI\VEN_10EC&DEV_C852', 'PCI\VEN_10EC&DEV_C852\4&1', 'pci\ven_10ec&dev_c852&subsys_c85210ec') {
    if ($okRtl -notmatch $SupportedCardPattern) { $fail += "$okRtl not accepted" }
    $rc = Classify-WifiCard $okRtl
    if ($rc.Kind -ne 'supported-rtl' -or $rc.Chip -ne 'Realtek RTL8852CE') { $fail += "$okRtl classified as $($rc.Kind) / $($rc.Chip)" }
  }
  foreach ($no in 'PCI\VEN_8086&DEV_43F01&SUBSYS_00748086', 'PCI\VEN_8086&DEV_7E40&SUBSYS_00908086', 'PCI\VEN_8086&DEV_272B1&SUBSYS_00F48086', 'PCI\VEN_10EC&DEV_C8520&SUBSYS_C85210EC', 'PCI\VEN_10EC&DEV_B852&SUBSYS_B85217AA', 'PCI\VEN_10EC&DEV_8168&SUBSYS_86771043', 'PCI\VEN_8086&DEV_15F3&SUBSYS_00008086') {
    if ($no -match $SupportedCardPattern) { $fail += "$no accepted as supported" }
  }
  if ((Classify-WifiCard 'PCI\VEN_8086&DEV_43F01&SUBSYS_00748086').Kind -eq 'supported' -or (Test-KnownWifiId 'PCI\VEN_8086&DEV_43F01&SUBSYS_00748086')) {
    $fail += '5-digit device ID DEV_43F01 matched as known/supported'
  }
  if ((Classify-WifiCard 'PCI\VEN_10EC&DEV_C8520&SUBSYS_C85210EC').Kind -eq 'supported-rtl' -or (Test-KnownWifiId 'PCI\VEN_10EC&DEV_C8520&SUBSYS_C85210EC')) {
    $fail += '5-digit device ID DEV_C8520 matched as RTL8852CE'
  }

  # Realtek RTL8821CU USB dongle (0BDA:C820, C821): the Wi-Fi function of a
  # composite device, the whole-device ID, bare and lower case, and never a
  # 5-digit PID or a different Realtek USB ID.
  foreach ($usbPid in 'C820', 'C821') {
    foreach ($okUsb in "USB\VID_0BDA&PID_$usbPid&REV_0200&MI_02\B&1D92DF5B&0&0002", "USB\VID_0BDA&PID_$usbPid\123456", "USB\VID_0BDA&PID_$usbPid", "usb\vid_0bda&pid_$($usbPid.ToLower())&mi_02\B&1") {
      if ($okUsb -notmatch $SupportedCardPattern) { $fail += "$okUsb not accepted" }
      $uc = Classify-WifiCard $okUsb
      if ($uc.Kind -ne 'supported-rtl-usb' -or $uc.Chip -ne 'Realtek RTL8821CU (USB)') { $fail += "$okUsb classified as $($uc.Kind) / $($uc.Chip)" }
      if (-not (Test-KnownWifiId $okUsb)) { $fail += "$okUsb not a known WiFi ID" }
    }
    if ("USB\VID_0BDA&PID_$($usbPid)1\1" -match $SupportedCardPattern) { $fail += "5-digit USB PID $($usbPid)1 accepted" }
  }
  foreach ($noUsb in 'USB\VID_0BDA&PID_C822&REV_0200&MI_02\B&1', 'USB\VID_0BDA&PID_8812\00E04C000001', 'USB\VID_0BDA&PID_C811\1') {
    if ($noUsb -match $SupportedCardPattern) { $fail += "$noUsb accepted as supported" }
    if ((Classify-WifiCard $noUsb).Kind -ne 'usb') { $fail += "$noUsb classified as $((Classify-WifiCard $noUsb).Kind)" }
  }

  # A laptop with an unsupported Realtek RTL8852BE that has no driver yet (so no
  # adapter and no class), its Realtek Ethernet chip, a Wi-Fi Direct virtual adapter and TAP.
  $rtlPnp = @(
    (Dev 'PCI\VEN_10EC&DEV_B852&SUBSYS_B85217AA&REV_00\4&1&0&00E8' '' ''),
    (Dev 'PCI\VEN_10EC&DEV_8168&SUBSYS_86771043&REV_15\4&2&0&00E5' 'Realtek PCIe GbE Family Controller'),
    (Dev 'SWD\MSRRAS\MS_NDISWANIP' 'WAN Miniport (IP)'),
    (Dev 'ROOT\NET\0000' 'Microsoft Wi-Fi Direct Virtual Adapter'),
    (Dev 'ROOT\NET\0001' 'TAP-Windows Adapter V9')
  )
  $rtlNics = @((Nic 'PCI\VEN_10EC&DEV_8168&SUBSYS_86771043&REV_15\4&2&0&00E5' 14 '802.3'), (Nic 'ROOT\NET\0000' 9 'Native 802.11'))
  $sel = @(Select-WirelessDevices $rtlPnp $rtlNics)
  if ($sel.Count -ne 1 -or $sel[0].InstanceId -notmatch 'DEV_B852') { $fail += "RTL8852BE laptop: selected $(@($sel | ForEach-Object { $_.InstanceId }) -join ', ')" }
  $msg = Format-UnsupportedCardMessage $sel
  foreach ($want in $NoSupportedCard, '10EC:B852', 'PCI\VEN_10EC&DEV_B852', 'Realtek RTL8852BE', 'not supported: Realtek', 'RTL8852CE (10EC:C852)', 'report.ps1', $IssuesUrl) {
    if (-not $msg.Contains($want)) { $fail += "RTL8852BE message lacks '$want'" }
  }
  if ($msg.Contains('8168') -or $msg.Contains('SUBSYS') -or $msg.Contains('4&1&0')) { $fail += 'RTL8852BE message shows the Ethernet chip or the instance path' }

  # MediaTek RZ717 found by its medium, a USB stick (serial = MAC address) found
  # by name, Intel Meteor Lake and BE200, an Intel ID nobody knows, Qualcomm,
  # Broadcom and an unknown vendor's wireless adapter: PCIe first, at most 5.
  $manyPnp = @(
    (Dev 'USB\VID_0BDA&PID_8812\00E04C000001' 'Realtek 8812AU Wireless LAN 802.11ac USB NIC'),
    (Dev 'PCI\VEN_14C3&DEV_0717&SUBSYS_E0CD1A3B&REV_00\4&1' 'MediaTek Wi-Fi 7 MT7925 (RZ717) 160MHz PCIe Adapter'),
    (Dev 'PCI\VEN_8086&DEV_7E40&SUBSYS_00908086&REV_20\3&1' 'Intel(R) Wi-Fi 6E AX211 160MHz'),
    (Dev 'PCI\VEN_8086&DEV_272B&SUBSYS_00F48086&REV_1A\4&1' 'Intel(R) Wi-Fi 7 BE200 320MHz'),
    (Dev 'PCI\VEN_8086&DEV_1234&SUBSYS_00008086\4&1' 'Intel(R) Wireless Something'),
    (Dev 'PCI\VEN_17CB&DEV_1103&SUBSYS_010817CB\4&1' 'Qualcomm FastConnect 6900 Wi-Fi 6E Dual Band Simultaneous (DBS) WiFi Network Adapter'),
    (Dev 'PCI\VEN_14E4&DEV_43A0&SUBSYS_0000106B\4&1' 'Broadcom 802.11ac Network Adapter')
  )
  $manyNics = @((Nic 'PCI\VEN_14C3&DEV_0717&SUBSYS_E0CD1A3B&REV_00\4&1' 9))
  $sel = @(Select-WirelessDevices $manyPnp $manyNics)
  if ($sel.Count -ne 5) { $fail += "expected 5 wireless devices, got $($sel.Count)" }
  if (@($sel | Where-Object { $_.InstanceId -match '^USB\\' }).Count) { $fail += 'a USB adapter came before 5 PCIe cards' }
  $all = @(Select-WirelessDevices ($manyPnp | Select-Object -First 3) @())
  if ($all.Count -ne 3 -or $all[-1].InstanceId -notmatch '^USB\\') { $fail += 'the USB adapter is not listed after the PCIe cards' }
  $msg = Format-UnsupportedCardMessage $all
  foreach ($want in 'USB\VID_0BDA&PID_8812', 'not supported: USB adapter', 'MediaTek MT7925 (AMD RZ717)', 'not supported: MediaTek', 'Intel Ma (Meteor Lake CNVi)', 'firmware is not shipped upstream') {
    if (-not $msg.Contains($want)) { $fail += "message lacks '$want'" }
  }
  if ($msg.Contains('00E04C000001')) { $fail += 'message shows the USB serial number' }
  if ($msg.Contains('winawdl')) { $fail += 'winawdl offered for a card it does not drive' }
  $msg = Format-UnsupportedCardMessage ($manyPnp | Select-Object -Skip 3)
  foreach ($want in 'Intel BE200 (Wi-Fi 7)', 'supported by nekodrop (experimental, Concurrent Wi-Fi beside AirDrop or on-demand', 'an Intel device ID nekodrop does not know', 'Qualcomm WCN6855', 'Broadcom BCM4360') {
    if (-not $msg.Contains($want)) { $fail += "message lacks '$want'" }
  }
  if ((Classify-WifiCard 'PCI\VEN_8086&DEV_272B&SUBSYS_00F48086').Kind -ne 'intel-be-exp') {
    $fail += '8086:272B not classified as intel-be-exp'
  }
  # BE200 is taken like the other cards (experimental), with the 4-hex boundary.
  if ('PCI\VEN_8086&DEV_272B&SUBSYS_00F48086&REV_1A\4&1' -notmatch $SupportedCardPattern) { $fail += '8086:272B not accepted' }
  $odd = @(Select-WirelessDevices @((Dev 'PCI\VEN_1AE0&DEV_1234&SUBSYS_00001AE0\4&1' 'Contoso Wireless-AC 9000')) @())
  if ($odd.Count -ne 1 -or -not (Format-UnsupportedCardMessage $odd).Contains('unrecognized wireless adapter')) { $fail += 'unknown vendor wireless adapter not reported' }

  # Ethernet only (Intel and Realtek chips, Killer E3100): no wireless card.
  $ethPnp = @((Dev 'PCI\VEN_8086&DEV_15F3&SUBSYS_00008086\3&1' 'Intel(R) Ethernet Controller I225-V'),
              (Dev 'PCI\VEN_10EC&DEV_8125&SUBSYS_00001043\4&1' 'Killer E3100 2.5 Gigabit Ethernet Controller'),
              (Dev 'PCI\VEN_10EC&DEV_8168&SUBSYS_00001043\4&2' 'Realtek PCIe GbE Family Controller'))
  $ethNics = @((Nic 'PCI\VEN_8086&DEV_15F3&SUBSYS_00008086\3&1' 14 '802.3'))
  if (@(Select-WirelessDevices $ethPnp $ethNics).Count) { $fail += 'an Ethernet chip was taken for Wi-Fi' }
  $msg = Format-UnsupportedCardMessage @()
  if (-not $msg.StartsWith($NoSupportedCard) -or -not $msg.Contains('No wireless card was found') -or -not $msg.Contains($IssuesUrl)) { $fail += 'no-card message incomplete' }
  if (-not (Format-UnsupportedCardMessage $null).Contains('No wireless card was found')) { $fail += 'null device list not handled' }

  # A localized name (Chinese) and a trademark sign: left out, chip still named,
  # and the whole message stays ASCII for the setup's ANSI error box.
  $cjk = Dev 'PCI\VEN_14C3&DEV_7922&SUBSYS_7922103C\4&1' ('MediaTek ' + [char]0x65E0 + [char]0x7EBF + ' Wi-Fi')
  $tm = Dev 'PCI\VEN_10EC&DEV_B852&SUBSYS_1\4&1' ('Realtek' + [char]0x00AE + ' 8852BE WiFi 6 PCI-E NIC')
  if (@(Select-WirelessDevices @((Dev 'PCI\VEN_1AE0&DEV_0001\4&1' ('Contoso ' + [char]0x65E0 + [char]0x7EBF))) @()).Count -ne 1) { $fail += 'a Chinese wireless adapter name was not recognized' }
  $msg = Format-UnsupportedCardMessage @($cjk, $tm)
  if (-not $msg.Contains('MediaTek MT7922') -or -not $msg.Contains('Realtek RTL8852BE') -or -not $msg.Contains('PCI\VEN_10EC&DEV_B852')) { $fail += 'a card with a non-ASCII name lost its chip or ID' }
  foreach ($m in $msg, (Format-UnsupportedCardMessage $manyPnp), (Format-UnsupportedCardMessage $rtlPnp)) {
    if (-not (Ascii $m)) { $fail += 'message is not plain ASCII' }
    foreach ($ln in ($m -split "`r?`n")) {
      if ($ln -match 'https?://' -and $ln.Length -gt 79) { $fail += "URL line exceeds 79 chars: $ln" }
    }
  }
  foreach ($k in $WifiKinds.Keys) {
    if (-not (Ascii ($WifiKinds[$k] -join ' '))) { $fail += "kind $k text is not ASCII" }
  }

  # The tables and functions are a copy of report.ps1's, and the supported IDs
  # are restore.ps1's too: compare them when those files sit beside this one
  # (the build's stage folder and the repository's installer folder).
  function Get-ScriptAst([string]$path) {
    [System.Management.Automation.Language.Token[]]$tokens = $null
    [System.Management.Automation.Language.ParseError[]]$errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count) { return $null }
    return $ast
  }
  # A top-level variable's value, only if it is pure literals (strings, arrays,
  # hashtables): evaluating it then runs no command.
  function Get-LiteralValue($ast, [string]$name) {
    $a = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq "`$$name" }, $false)
    if (-not $a) { return $null }
    $code = $a.Right.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -or
                                      $n -is [System.Management.Automation.Language.VariableExpressionAst] -or
                                      $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -or
                                      $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true)
    if ($code) { return $null }
    return (& ([scriptblock]::Create($a.Right.Extent.Text)))
  }
  function ConvertTo-Comparable($v) {
    if ($v -is [hashtable]) { return (($v.Keys | Sort-Object | ForEach-Object { "$_=" + (@($v[$_]) -join '|') }) -join "`n") }
    return (@($v) -join '|')
  }
  $self = Get-ScriptAst $PSCommandPath
  if (-not $self) { $fail += 'install.ps1 does not parse' }
  $report = Join-Path $PSScriptRoot 'report.ps1'
  if ($self -and (Test-Path -LiteralPath $report)) {
    $other = Get-ScriptAst $report
    if (-not $other) { $fail += 'report.ps1 does not parse' }
    else {
      foreach ($v in 'SupportedIntelIds', 'WifiChips', 'WifiKinds', 'WifiVendors') {
        $mine = Get-LiteralValue $self $v; $theirs = Get-LiteralValue $other $v
        if ($null -eq $theirs -or (ConvertTo-Comparable $mine) -ne (ConvertTo-Comparable $theirs)) { $fail += "`$$v differs from report.ps1's" }
      }
    }
  } else { Write-Host 'install.ps1 self-test: report.ps1 not beside it, table comparison skipped' }
  $restore = Join-Path $PSScriptRoot 'restore.ps1'
  if ($self -and (Test-Path -LiteralPath $restore)) {
    $other = Get-ScriptAst $restore
    $theirs = if ($other) { Get-LiteralValue $other 'SupportedIntelIds' } else { $null }
    if ($null -eq $theirs -or (ConvertTo-Comparable $SupportedIntelIds) -ne (ConvertTo-Comparable $theirs)) { $fail += "restore.ps1's `$SupportedIntelIds differ" }
  } else { Write-Host 'install.ps1 self-test: restore.ps1 not beside it, ID comparison skipped' }

  if ($fail) { $fail | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
  Write-Host 'install.ps1 self-test: card check, wireless selection, refusal message and card tables passed'
  exit 0
}

# --------------------------------------------------------------- elevation
# What "#Requires -RunAsAdministrator" did, before anything is written (the
# log folder below is for administrators only).
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'install.ps1 needs administrator rights: run the nekodrop setup, or this script from an administrator PowerShell.'
  exit 1
}

$Source = $PSScriptRoot
# The setup runs this hidden: keep a log, and say what failed through the exit
# code and install-error.txt, which the setup shows.
$LogDir = Join-Path $env:ProgramData 'nekodrop'
New-Item -ItemType Directory -Force $LogDir | Out-Null
if ((Get-Item -LiteralPath $LogDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
  throw "Refusing reparse point: $LogDir"
}
& icacls.exe $LogDir /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" | Out-Null
Remove-Item (Join-Path $LogDir 'install-error.txt') -ErrorAction SilentlyContinue
if (-not $DryRun) { Start-Transcript (Join-Path $LogDir 'install.log') -Force | Out-Null }
$script:ServiceWasRunning = $false
trap {
  $_ | Out-String | Set-Content (Join-Path $LogDir 'install-error.txt') -Encoding utf8
  # If an upgrade stopped an already-running service and then failed later
  # (e.g. driver signing), restart the service so a working install isn't left dead (#73).
  if (-not $DryRun -and $script:ServiceWasRunning) {
    try {
      $svc = Get-Service $Service -ErrorAction SilentlyContinue
      if ($svc -and $svc.Status -ne 'Running') {
        Start-Service $Service -ErrorAction SilentlyContinue
      }
    } catch { }
  }
  if (-not $DryRun) { Stop-Transcript | Out-Null }
  exit 1
}
$CertSubject = 'CN=nekodrop driver (signed on this PC)'
$TrustStores = 'Root', 'TrustedPublisher'
$FirewallGroup = 'nekodrop AirDrop'
$Service = 'NekoDropService'

function Step($what, [scriptblock]$do) {
  "  $what"
  if (-not $DryRun) { & $do }
}

$pnpAll = @(Get-PnpDevice -PresentOnly)
if (-not ($pnpAll | Where-Object { $_.InstanceId -match $SupportedCardPattern })) {
  # Naming the cards is a courtesy: if reading the adapters or formatting
  # fails, the refusal is still made, with the earlier one-line message.
  $refusal = $null
  try {
    $adapters = @()
    try { $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop) } catch { }
    $refusal = Format-UnsupportedCardMessage (Select-WirelessDevices $pnpAll $adapters)
  } catch { }
  if (-not $refusal) { $refusal = $NoSupportedCard }
  throw $refusal
}

'Files'
# Every process running from the install folder, not only ours by name: the
# AirDrop engine is the bundled python.exe started by nekodrop.exe, and killing
# nekodrop.exe leaves it running with python\libcrypto-3.dll open, so the copy
# below failed with an IOException on that file and left a half-copied folder (#22).
function Stop-FromTarget {
  $root = [IO.Path]::GetFullPath($Target).TrimEnd('\') + '\'
  # Never by path under a drive root or a folder that is not nekodrop's.
  $byPath = $root.Length -gt 4 -and ((Test-Path (Join-Path $root 'NekoDropService.exe')) -or (Test-Path (Join-Path $root 'python\python.exe')))
  $ours = @(Get-Process nekodrop, nekodrop-radio, nekodrop-radio-rtl, nekodrop-radio-usb, nekodrop-radio-mt, nekodrop-radio-mtk, awdld, NekoDropService -ErrorAction SilentlyContinue) +
          @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
              try { $byPath -and $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } catch { $false } })
  # Processes started from elsewhere that name the folder on their command
  # line: airdrop-beacon.ps1's powershell.exe held airdrop\ open (#22).
  $ours += @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $byPath -and $_.ProcessId -ne $PID -and $_.CommandLine -and
      $_.CommandLine.IndexOf($root.TrimEnd(''), [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
    ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
  $ours = @($ours | Sort-Object Id -Unique)
  $ours | Stop-Process -Force -ErrorAction SilentlyContinue
  $ours | ForEach-Object { try { $_.WaitForExit(10000) | Out-Null } catch { } }
  $ours
}
Step 'stop an earlier service' {
  $existingSvc = Get-Service $Service -ErrorAction SilentlyContinue
  if ($existingSvc) {
    if ($existingSvc.Status -eq 'Running') { $script:ServiceWasRunning = $true }
    Stop-Service $Service -Force -ErrorAction SilentlyContinue
    # Stop-Service returns before the process is gone; wait for it.
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Service $Service).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  }
  Stop-FromTarget | Out-Null
}
Step "copy to $Target" {
  New-Item -ItemType Directory -Force $Target | Out-Null
  # The Explorer menu (nekodrop-shell.dll) is loaded by explorer.exe and its
  # COM hosts, which are not ours to stop, so the copy failed on it five times
  # in a row.  A loaded DLL can still be renamed: move it aside, Explorer keeps
  # the old one until it restarts, and the new one is used from then on.
  # Leftovers from earlier updates go now, or at the next restart if still loaded.
  Get-ChildItem -LiteralPath $Target -Filter 'nekodrop-shell.dll.*.old' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
  $shellDll = Join-Path $Target 'nekodrop-shell.dll'
  if (Test-Path -LiteralPath $shellDll) {
    try { [IO.File]::Open($shellDll, 'Open', 'ReadWrite', 'None').Dispose() }
    catch {
      $aside = "$shellDll.$((Get-Date).ToString('yyyyMMddHHmmss')).old"
      try {
        Move-Item -LiteralPath $shellDll $aside -Force -ErrorAction Stop
        "    nekodrop-shell.dll is in use by Explorer: moved aside, replaced after the next sign-in"
        if (-not ('NekoDrop.MoveLater' -as [type])) {
          Add-Type -Namespace NekoDrop -Name MoveLater -MemberDefinition @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool MoveFileEx(string from, string to, int flags);
'@
        }
        [NekoDrop.MoveLater]::MoveFileEx($aside, $null, 4) | Out-Null  # MOVEFILE_DELAY_UNTIL_REBOOT
      } catch { "    nekodrop-shell.dll is in use and could not be moved aside: $($_.Exception.Message)" }
    }
  }
  # A file can stay locked a moment after its process exits (or a process may
  # have been started again meanwhile): retry, and say who holds it.
  for ($try = 1; ; $try++) {
    try {
      Copy-Item "$Source\*" $Target -Recurse -Force -Exclude 'install.ps1', 'tap-windows.exe'
      break
    } catch {
      $held = Stop-FromTarget
      if ($try -ge 5) {
        $who = ($held | ForEach-Object { "$($_.ProcessName) ($($_.Id))" }) -join ', '
        throw "could not copy to $Target after $try tries: $($_.Exception.Message)" +
              $(if ($who) { " Still running from there: $who." } else { '' }) +
              ' Close nekodrop (tray icon -> Quit) and run the setup again.'
      }
      Start-Sleep -Seconds 2
    }
  }
}

'Driver'
$driver = Join-Path $Target 'driver'
Step 'sign the register-proxy and USB-dongle drivers with a certificate made and trusted on this PC' {
  foreach ($store in $TrustStores) {
    Get-ChildItem "Cert:\LocalMachine\$store" | Where-Object { $_.Subject -eq $CertSubject } | Remove-Item
  }
  $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $CertSubject `
            -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable `
            -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(10)
  try {
    $public = Join-Path $driver 'nekodrop-signing.cer'
    Export-Certificate -Cert $cert -FilePath $public | Out-Null
    foreach ($store in $TrustStores) { Import-Certificate -FilePath $public -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null }
    $signtool = Join-Path $Target 'shell\signtool.exe'
    # The PCIe register proxy, and the WinUSB package the RTL8821CU USB dongle
    # needs (same certificate, same trusting steps; only its .cat is signed).
    foreach ($file in 'winawdl_regproxy.cat', 'winawdl_regproxy.dll', 'nekodrop_winusb.cat') {
      $full = Join-Path $driver $file
      if (-not (Test-Path $full)) { continue }
      $r = Set-AuthenticodeSignature -FilePath $full -Certificate $cert -HashAlgorithm SHA256
      if ($r.Status -ne 'Valid') {
        # Windows 11 25H2 (build 26200.9974+) can fail Set-AuthenticodeSignature on
        # .cat files with 0xC0000225 even though signtool.exe signs them cleanly (#73).
        if (Test-Path -LiteralPath $signtool) {
          "    Set-AuthenticodeSignature failed on $file ($($r.Status): $($r.StatusMessage)); retrying with signtool.exe"
          $stOut = & $signtool sign /fd SHA256 /s My /sha1 $cert.Thumbprint $full 2>&1
          $stExit = $LASTEXITCODE
          $v = Get-AuthenticodeSignature -FilePath $full
          $stVerified = $false
          if ($stExit -eq 0) {
            if ($v.Status -eq 'Valid') {
              $stVerified = $true
            } else {
              & $signtool verify /pa /q $full 2>&1 | Out-Null
              if ($LASTEXITCODE -eq 0) { $stVerified = $true }
            }
          }
          if ($stVerified) { continue }
          $stMsg = ($stOut | Out-String).Trim()
          throw "$file could not be signed: Set-AuthenticodeSignature=$($r.StatusMessage); signtool (exit $stExit, verify=$($v.Status)): $stMsg"
        }
        throw "$file could not be signed: $($r.StatusMessage)"
      }
    }
    # The Explorer menu's sparse package (Windows 11 first level), same certificate.
    # Not fatal: the classic menu under "Show more options" works without it.
    $msix = Join-Path $Target 'shell\nekodrop-shell.msix'
    # An earlier registration was signed by the certificate just replaced: drop it,
    # each user's client registers the new one at its next start.
    Get-AppxPackage -AllUsers -Name nekodrop.shell -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    if ((Test-Path $msix) -and (Test-Path $signtool)) {
      & $signtool sign /q /fd SHA256 /s My /sha1 $cert.Thumbprint $msix
      if ($LASTEXITCODE -ne 0) { "    the Explorer menu package could not be signed ($LASTEXITCODE)" }
    }
  } finally {
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey
  }
}
Step 'add them to the driver store (binds nothing)' {
  pnputil /add-driver (Join-Path $driver 'winawdl_regproxy.inf') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "pnputil could not add the driver ($LASTEXITCODE)" }
  # The RTL8821CU dongle's WinUSB package: the service binds it when it first
  # takes the dongle (Card.Bind, like the register proxy), not here.
  $winusb = Join-Path $driver 'nekodrop_winusb.inf'
  if (Test-Path $winusb) {
    pnputil /add-driver $winusb | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pnputil could not add the USB dongle driver ($LASTEXITCODE)" }
  }
}

'Network'
Step "nekodrop's own TAP adapter (DHCP) for Wi-Fi beside AirDrop" {
  try { & "$Source\setup-tap.ps1" -TapSetup "$Source\tap-windows.exe" | Out-Host }
  catch { "    TAP adapter not ready ($($_.Exception.Message)); concurrent mode will fall back to on-demand" }
}
Step 'firewall: AirDrop receiver and discovery, from link-local addresses only' {
  Get-NetFirewallRule -Group $FirewallGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  $common = @{ Group = $FirewallGroup; Direction = 'Inbound'; Action = 'Allow'; Profile = 'Any'; RemoteAddress = 'fe80::/64' }
  # Three separated ranges so a 100-port Hyper-V/WinNAT excluded block (#30) cannot cover all of them.
  New-NetFirewallRule @common -DisplayName 'nekodrop AirDrop receiver' -Protocol TCP -LocalPort '8771-8779', '18771-18779', '28771-28779' | Out-Null
  New-NetFirewallRule @common -DisplayName 'nekodrop AirDrop discovery' -Protocol UDP -LocalPort 5353 | Out-Null
}

'Service'
Step 'install and start NekoDropService (LocalSystem, automatic)' {
  $exe = Join-Path $Target 'NekoDropService.exe'
  if (-not (Get-Service $Service -ErrorAction SilentlyContinue)) {
    New-Service -Name $Service -BinaryPathName "`"$exe`"" -DisplayName 'nekodrop AirDrop' `
      -Description 'AirDrop on the built-in Wi-Fi card: owns the card while AirDrop is on.' -StartupType Automatic | Out-Null
    sc.exe failure $Service reset= 86400 actions= restart/5000/restart/30000/""/0 | Out-Null
  }
  Start-Service $Service
}
if ($DryRun) { 'Dry run: nothing was changed.' } else { 'nekodrop is installed.'; Stop-Transcript | Out-Null }
exit 0
