# nekodrop diagnostic report: everything a bug report needs, in one file.
# Start menu -> "nekodrop - diagnostic report", the tray menu, or run this.
# Needs administrator rights (the service's logs and the driver state are
# readable by administrators only); it asks for them itself.
#
# Writes two files to the Desktop:
#   nekodrop-report-<time>.md   summary, bring-up checklist, system, card,
#                               network, key log lines (paste into an issue)
#   nekodrop-logs-<time>.txt    the full logs (attach to the issue)
# SSIDs, MAC addresses, private IP addresses, the user name and the computer
# name are replaced by placeholders. Nothing is sent anywhere.
#
# -SelfTest checks the Wi-Fi card classification below against made-up device
# IDs and exits 0 (all pass) or 1; it needs no administrator rights and no card.
param(
  [string]$OutDir = '',
  [string]$UserData = '',
  [string]$UserName = '',
  [switch]$NoOpen,
  [switch]$SelfTest
)
$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ------------------------------------------------ Wi-Fi card classification
# What a wireless card is and why nekodrop does or does not run on it, from its
# PCI (or USB) ID alone. Without this a report from a PC with a Realtek,
# MediaTek or newer Intel card said only "no supported Intel card found", which
# did not tell an unlisted device ID from a broken driver (#16). Pure data, so
# -SelfTest can check it without hardware.
#
# The supported IDs are iwxradio/src/cards.h's kDeviceIds, the register
# proxy's INF and install.ps1's check: keep them in step.
$SupportedIntelIds = @('43F0', 'A0F0', '02F0', '06F0', '34F0', '3DF0', '4DF0', '2723', '2725', '7A70', '7AF0', '51F0', '51F1', '54F0', '7F70')
# The card this report calls supported: the Intel IDs above, Realtek RTL8852CE,
# the Realtek RTL8821CU USB dongle, and MediaTek MT7902/MT7921/MT7922. Defined
# here (not with the collection below) so -SelfTest can check it offline.
$SupportedCardPattern = '^(?:PCI\\(?:VEN_8086&DEV_(' + ($SupportedIntelIds -join '|') + ')|VEN_10EC&DEV_C852|VEN_14C3&DEV_(7902|7961|0608|7922|0616))|USB\\VID_0BDA&PID_(C820|C821))(?=&|\\|$)'
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
  if (-not $chip) { $chip = "$vendorName $device (not in nekodrop's table)" }
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

# ------------------------------------------------------- discovery timing
# How long the last radio start took for each step of discovery (#4: ~99 s
# before the PC saw the iPhone; #11: ch149 passive ~60 s with every AWDL frame
# held, the iPhone listed after ~2 min, the PC never listed on the iPhone).
# Until now that meant reading the whole log by hand. Pure text in, table rows
# out, so -SelfTest checks it without logs or a card.
#   $attemptLines: service.log from the last radio start ('yyyy-MM-dd HH:mm:ss ...')
#   $engineLines:  engine.log ('HH:mm:ss.fff ...'; Python logging lines also carry the date)
function Get-LogTime([string]$line) {
  if ($line -match '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') {
    return [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
  }
  return $null
}
function Get-DiscoverySummary($attemptLines, $engineLines) {
  $lines = @($attemptLines | Where-Object { $_ })
  if (-not $lines.Count) { return @() }
  $t0 = Get-LogTime $lines[0]
  if (-not $t0) { return @() }
  $rows = @()
  # One row: when (seconds after the start) and the line that says so.
  $row = {
    param([string]$name, $line, [string]$detail = '')
    if (-not $line) { return "| $name | - | $(if ($detail) { $detail } else { 'not in the log' }) |" }
    $t = Get-LogTime $line
    $after = if ($t) { '+{0} s' -f [int][Math]::Round(($t - $t0).TotalSeconds) } else { '?' }
    $text = if ($detail) { $detail } else { '`' + ((($line -replace '^\S+ \S+ ', '') -replace '^radio: \S+ radio: ', '') -replace '\|', '/') + '`' }
    return "| $name | $after | $text |"
  }
  $first = { param([string]$re) $lines | Where-Object { $_ -match $re } | Select-Object -First 1 }
  $rows += & $row 'Radio ready' (& $first 'radio: ready on channel')
  $startCh = & $first 'event: channel \d+ (active|passive)'
  $rows += & $row 'AWDL channel at start' $startCh
  $fast = & $first 'experimental fast passive-channel unlock: on'
  $rows += "| Fast passive-channel unlock (experimental) | - | $(if ($fast) { 'on' } else { 'off' }) |"
  # 0.1.25+ logs each first once; older radios only have the 5 s rx counters.
  $awdl = & $first 'discovery: first AWDL action frame'
  if (-not $awdl) { $awdl = $lines | Where-Object { $_ -match 'rx: \d+ frames, [1-9]\d* AWDL action frames' } | Select-Object -First 1 }
  $rows += & $row 'First AWDL frame heard' $awdl
  $mif = & $first 'discovery: first AWDL MIF'
  if (-not $mif) { $mif = $lines | Where-Object { $_ -match 'PSF, [1-9]\d* MIF' } | Select-Object -First 1 }
  $rows += & $row 'First MIF (awdld takes the peer as valid)' $mif
  $scans = @($lines | Where-Object { $_ -match 'is passive: (scanning once|fast discovery scan)' })
  $rows += & $row "Discovery scans on the passive channel ($($scans.Count))" ($scans | Select-Object -First 1)
  $rows += & $row 'Transmitting allowed (beacon or AWDL peer)' (& $first 'transmitting allowed here')
  $notice = & $first 'regulatory: firmware notice'
  $rows += & $row 'Firmware country notice' $notice
  $active = & $first 'event: channel \d+ active'
  $rows += & $row 'Channel active (firmware country)' $active
  $held = $lines | Where-Object { $_ -match '(\d+) held \(passive channel\)' } | ForEach-Object { [int]$Matches[1] } | Measure-Object -Maximum
  $rows += "| Frames held on the passive channel | - | $(if ($held.Count) { "up to $($held.Maximum)" } else { 'none' }) |"
  $toUs = & $first 'discovery: first frame addressed to us'
  if (-not $toUs) { $toUs = $lines | Where-Object { $_ -match '[1-9]\d* addressed to us' } | Select-Object -First 1 }
  $rows += & $row 'First frame addressed to us' $toUs
  # The engine's own log: times of day only, the date from its logging lines.
  $day = $t0.Date
  $noAnswer = 0
  $peerAt = $null
  foreach ($e in @($engineLines)) {
    if ($e -match '^\d\d:\d\d:\d\d\.\d+ (\d{4}-\d\d-\d\d) ') { $day = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    if (-not ($e -match '^(\d\d):(\d\d):(\d\d)')) { continue }
    $t = $day.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]).AddSeconds([int]$Matches[3])
    if ($t -lt $t0) { continue }
    if ($e -match 'does not answer yet') { $noAnswer++ }
    if ($e -match '"event":"peer"') { $peerAt = $t; break }
  }
  $engineRow = if ($peerAt) { "| AirDrop engine: first device listed | +$([int][Math]::Round(($peerAt - $t0).TotalSeconds)) s | after $noAnswer ""does not answer yet"" timeouts |" }
               else { "| AirDrop engine: first device listed | - | none since this start; $noAnswer ""does not answer yet"" timeouts |" }
  $rows += $engineRow
  return $rows
}

if ($SelfTest) {
  $fail = @()
  $cases = @(
    @('PCI\VEN_8086&DEV_43F0&SUBSYS_00748086&REV_00\3&11583659&0&A3', 'supported', 'Intel Wi-Fi 6/6E'),
    @('PCI\VEN_8086&DEV_2725&SUBSYS_00248086&REV_1A\4&2A1B3C4D&0&00E0', 'supported', 'Intel Wi-Fi 6/6E'),
    @('PCI\VEN_8086&DEV_7E40&SUBSYS_00908086&REV_20\3&11583659&0&A3', 'intel-fw', 'Intel Ma (Meteor Lake CNVi)'),
    @('PCI\VEN_8086&DEV_2726&SUBSYS_00248086', 'intel-fw', 'Intel SnJ'),
    @('PCI\VEN_8086&DEV_272B&SUBSYS_00F48086&REV_1A\4&1', 'intel-be-exp', 'Intel BE200 (Wi-Fi 7)'),
    @('PCI\VEN_8086&DEV_A840&SUBSYS_00E48086&REV_10\3&1', 'intel-be', 'Intel BE201/BE211 (Wi-Fi 7, CNVi)'),
    @('PCI\VEN_8086&DEV_1234&SUBSYS_00008086\4&1', 'intel-other', 'Intel 1234 (not in nekodrop''s table)'),
    @('PCI\VEN_10EC&DEV_C852&SUBSYS_C85210EC&REV_00\4&1&0&00E8', 'supported-rtl', 'Realtek RTL8852CE'),
    @('pci\ven_10ec&dev_c852&subsys_c85210ec', 'supported-rtl', 'Realtek RTL8852CE'),
    @('PCI\VEN_10EC&DEV_B852&SUBSYS_B85217AA\4&1', 'rtl', 'Realtek RTL8852BE'),
    @('PCI\VEN_10EC&DEV_ABCD&SUBSYS_000010EC', 'rtl', 'Realtek ABCD (not in nekodrop''s table)'),
    @('PCI\VEN_14C3&DEV_7922&SUBSYS_7922103C\4&1', 'supported-mtk', 'MediaTek MT7922'),
    @('PCI\VEN_14C3&DEV_0616&SUBSYS_E0CD1A3B\4&1', 'supported-mtk', 'MediaTek MT7922 (AMD RZ616)'),
    @('PCI\VEN_14C3&DEV_7961&SUBSYS_796114C3\4&1', 'supported-mtk', 'MediaTek MT7921'),
    @('PCI\VEN_14C3&DEV_0608&SUBSYS_060814C3\4&1', 'supported-mtk', 'MediaTek MT7921 (AMD RZ608)'),
    @('PCI\VEN_14C3&DEV_7925&SUBSYS_792514C3\4&1', 'mtk', 'MediaTek MT7925'),
    @('PCI\VEN_14C3&DEV_7927&SUBSYS_792714C3\4&1', 'mtk', 'MediaTek MT7927 (Wi-Fi 7)'),
    @('PCI\VEN_14C3&DEV_7902&SUBSYS_790214C3\4&1', 'supported-mtk', 'MediaTek MT7902'),
    @('PCI\VEN_17CB&DEV_1103&SUBSYS_010817CB\4&1', 'qcom', 'Qualcomm WCN6855 (FastConnect 6800/6900)'),
    @('PCI\VEN_168C&DEV_003E&SUBSYS_3212144F\4&1', 'qcom', 'Qualcomm Atheros QCA6174'),
    @('PCI\VEN_14E4&DEV_43A0&SUBSYS_0000106B\4&1', 'bcm', 'Broadcom BCM4360'),
    @('USB\VID_0BDA&PID_8812\00E04C000001', 'usb', 'Realtek 8812 (not in nekodrop''s table)'),
    @('USB\VID_0BDA&PID_C820&REV_0200&MI_02\B&1D92DF5B&0&0002', 'supported-rtl-usb', 'Realtek RTL8821CU (USB)'),
    @('USB\VID_0BDA&PID_C821\123456', 'supported-rtl-usb', 'Realtek RTL8821CU (USB)'),
    @('usb\vid_0bda&pid_c820&rev_0200&mi_02\B&1', 'supported-rtl-usb', 'Realtek RTL8821CU (USB)'),
    @('USB\VID_0BDA&PID_C822\1', 'usb', 'Realtek C822 (not in nekodrop''s table)'),
    @('PCI\VEN_1AE0&DEV_1234&SUBSYS_00001AE0\4&1', 'other', 'vendor 1AE0 1234 (not in nekodrop''s table)')
  )
  foreach ($c in $cases) {
    $r = Classify-WifiCard $c[0]
    if ($r.Kind -ne $c[1] -or $r.Chip -ne $c[2] -or -not $r.Status) { $fail += "$($c[0]): got $($r.Kind) / $($r.Chip), want $($c[1]) / $($c[2])" }
  }
  if ((Classify-WifiCard 'PCI\VEN_10EC&DEV_C852&SUBSYS_1\4&1' 'Realtek 8852CE').HardwareId -ne 'VEN_10EC&DEV_C852&SUBSYS_1') { $fail += 'hardware ID not split from the instance path' }
  if ((Classify-WifiCard 'PCI\VEN_10EC&DEV_C852').Family -ne 'Realtek RTL8852CE') { $fail += 'Family alias mismatch' }
  $rtlCard = Classify-WifiCard 'PCI\VEN_10EC&DEV_C852&SUBSYS_C85210EC&REV_00\4&1&0&00E8'
  if ($rtlCard.Status -notmatch 'on-demand' -or $rtlCard.Status -notmatch 'RTL8852CE') { $fail += "10EC:C852 status missing on-demand/RTL8852CE: $($rtlCard.Status)" }
  # The RTL8821CU USB dongle: accepted in every form, classified before the
  # generic USB refusal, and never a 5-digit PID.
  $usbCard = Classify-WifiCard 'USB\VID_0BDA&PID_C820&REV_0200&MI_02\B&1D92DF5B&0&0002'
  if ($usbCard.Status -notmatch 'RTL8821CU' -or $usbCard.Status -notmatch 'experimental') { $fail += "0BDA:C820 status missing RTL8821CU/experimental: $($usbCard.Status)" }
  if ($usbCard.Note -notmatch 'WinUSB') { $fail += "0BDA:C820 note does not say the dongle is kept: $($usbCard.Note)" }
  if ('USB\VID_0BDA&PID_C820&REV_0200' -notmatch $SupportedCardPattern) { $fail += '0BDA:C820 not a supported card' }
  if ('USB\VID_0BDA&PID_C8201' -match $SupportedCardPattern) { $fail += '5-digit USB PID accepted' }
  if (-not (Test-KnownWifiId 'USB\VID_0BDA&PID_C820\123456')) { $fail += '0BDA:C820 not found as Wi-Fi by its ID' }
  foreach ($d in $SupportedIntelIds) {
    if ((Classify-WifiCard "PCI\VEN_8086&DEV_$d").Kind -ne 'supported') { $fail += "8086:$d not supported" }
  }
  # Ethernet chips must never be taken for Wi-Fi by their ID.
  foreach ($eth in 'PCI\VEN_10EC&DEV_8168', 'PCI\VEN_10EC&DEV_8125', 'PCI\VEN_8086&DEV_15F3', 'PCI\VEN_8086&DEV_15BC', 'PCI\VEN_14E4&DEV_16B1') {
    if (Test-KnownWifiId $eth) { $fail += "$eth is Ethernet but listed as Wi-Fi" }
  }
  foreach ($w in 'PCI\VEN_10EC&DEV_C852', 'PCI\VEN_14C3&DEV_0616', 'PCI\VEN_8086&DEV_7E40', 'PCI\VEN_8086&DEV_43F0') {
    if (-not (Test-KnownWifiId $w)) { $fail += "$w not found as Wi-Fi by its ID" }
  }
  foreach ($k in $WifiChips.Keys) {
    if (-not $WifiKinds.ContainsKey($WifiChips[$k][0])) { $fail += "$k has unknown kind $($WifiChips[$k][0])" }
  }
  # Discovery timing: a #11-like start (passive 149, fast unlock on, held
  # frames, a peer unlocking it, the firmware's notice) and an older radio's
  # log with only the 5 s counters.
  $svc11 = @(
    '2026-11-21 10:00:00 starting: woken',
    '2026-11-21 10:00:05 radio: 10:00:05.050 radio: event: channel 149 passive',
    '2026-11-21 10:00:05 radio: 10:00:05.060 radio: experimental fast passive-channel unlock: on (discovery scans at 1.5, 12 and 30 s while the channel is passive)',
    '2026-11-21 10:00:05 radio: 10:00:05.100 radio: ready on channel 149, waiting for a client',
    '2026-11-21 10:00:07 radio: 10:00:07.000 radio: channel 149 is passive: fast discovery scan 1 of 3 so the firmware can learn the country',
    '2026-11-21 10:00:10 radio: 10:00:10.000 radio: tx: 0 submitted, 0 done, 0 failed; unicast: 0 resent, 0 given up, 0 waiting, 0 dropped; rate step 0 (0 up, 0 down); BA answers 0; 22 held (passive channel)',
    '2026-11-21 10:00:12 radio: 10:00:12.000 radio: discovery: first AWDL action frame after 7.0 s (channel 149, -60 dBm)',
    '2026-11-21 10:00:12 radio: 10:00:12.000 radio: AWDL peer heard on channel 149: transmitting allowed here',
    '2026-11-21 10:00:20 radio: 10:00:20.000 radio: regulatory: firmware notice TW (source 5)',
    '2026-11-21 10:00:20 radio: 10:00:20.000 radio: event: channel 149 active',
    '2026-11-21 10:00:25 radio: 10:00:25.000 radio: discovery: first AWDL MIF after 20.0 s',
    '2026-11-21 10:00:30 radio: 10:00:30.000 radio: discovery: first frame addressed to us after 25.0 s'
  )
  $eng11 = @(
    '09:59:00.000 2026-11-21 09:59:00,000 INFO engine started',
    '09:59:30.000 {"event":"peer","id":"stale","name":"before this start"}',
    '10:00:40.000 2026-11-21 10:00:40,000 WARNING a receiver at fe80::1 does not answer yet: timed out',
    '10:00:50.000 2026-11-21 10:00:50,000 WARNING a receiver at fe80::1 does not answer yet: timed out',
    '10:01:00.000 {"event":"peer","id":"x","name":"iPhone","model":null}'
  )
  $d11 = (Get-DiscoverySummary $svc11 $eng11) -join "`n"
  foreach ($want in '| Radio ready | +5 s |', '| AWDL channel at start | +5 s | `event: channel 149 passive` |',
                    '| Fast passive-channel unlock (experimental) | - | on |', '| First AWDL frame heard | +12 s |',
                    '| First MIF (awdld takes the peer as valid) | +25 s |', '| Discovery scans on the passive channel (1) | +7 s |',
                    '| Transmitting allowed (beacon or AWDL peer) | +12 s |', '| Firmware country notice | +20 s |',
                    '| Channel active (firmware country) | +20 s |', '| Frames held on the passive channel | - | up to 22 |',
                    '| First frame addressed to us | +30 s |', '| AirDrop engine: first device listed | +60 s | after 2 "does not answer yet" timeouts |') {
    if (-not $d11.Contains($want)) { $fail += "discovery timing (#11 log): missing $want" }
  }
  $svcOld = @(
    '2026-11-21 11:00:00 starting: boot (concurrent mode)',
    '2026-11-21 11:00:06 radio: 11:00:06.000 radio: ready on channel 44, waiting for a client',
    '2026-11-21 11:00:15 radio: 11:00:15.000 radio: rx: 100 frames, 3 AWDL action frames (3 PSF, 0 MIF; last -70 dBm), 0 addressed to us',
    '2026-11-21 11:00:20 radio: 11:00:20.000 radio: rx: 200 frames, 9 AWDL action frames (7 PSF, 2 MIF; last -70 dBm), 4 addressed to us'
  )
  $dOld = (Get-DiscoverySummary $svcOld @()) -join "`n"
  foreach ($want in '| First AWDL frame heard | +15 s |', '| First MIF (awdld takes the peer as valid) | +20 s |',
                    '| First frame addressed to us | +20 s |', '| Fast passive-channel unlock (experimental) | - | off |',
                    '| Transmitting allowed (beacon or AWDL peer) | - | not in the log |',
                    '| AirDrop engine: first device listed | - | none since this start; 0 "does not answer yet" timeouts |') {
    if (-not $dOld.Contains($want)) { $fail += "discovery timing (older log): missing $want" }
  }
  if (@(Get-DiscoverySummary @() @()).Count) { $fail += 'discovery timing: rows without a radio start' }
  if ($fail) { $fail | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
  Write-Host "report.ps1 self-test: $($cases.Count) cases, the ID tables and the discovery timing passed"
  exit 0
}

# --------------------------------------------------------------- elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  # The signed-in user's Desktop and engine log, before an elevation that may
  # run as another account.
  $desk = [Environment]::GetFolderPath('Desktop')
  $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -OutDir `"$desk`" " +
             "-UserData `"$env:LOCALAPPDATA`" -UserName `"$env:USERNAME`""
  if ($NoOpen) { $argLine += ' -NoOpen' }
  try { Start-Process powershell.exe -ArgumentList $argLine -Verb RunAs | Out-Null }
  catch { Write-Host 'nekodrop: the diagnostic report needs administrator rights.' }
  exit
}
if (-not $OutDir) { $OutDir = [Environment]::GetFolderPath('Desktop') }
if (-not $UserData) { $UserData = $env:LOCALAPPDATA }
if (-not $UserName) { $UserName = $env:USERNAME }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$state = Join-Path $env:ProgramData 'nekodrop'
$app = $PSScriptRoot
# Downloaded on its own (for an older nekodrop): the installed copy's folder.
if (-not (Test-Path (Join-Path $app 'NekoDropService.exe'))) { $app = Join-Path $env:ProgramFiles 'nekodrop' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$reportPath = Join-Path $OutDir "nekodrop-report-$stamp.md"
$logsPath = Join-Path $OutDir "nekodrop-logs-$stamp.txt"
Write-Host 'nekodrop: collecting the diagnostic report...'

# ---------------------------------------------------------------- helpers
function Read-Tail([string]$path, [int]$n) {
  if (-not (Test-Path $path)) { return @() }
  try { return @(Get-Content -LiteralPath $path -Tail $n -Encoding UTF8 -ErrorAction Stop) } catch { return @() }
}
function Read-All([string]$path) {
  if (-not (Test-Path $path)) { return @() }
  try { return @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop) } catch { return @() }
}
function Try-Get([scriptblock]$block) { try { & $block } catch { $null } }
# netsh's output: UTF-8 on some systems, the OEM code page on others (it came
# out garbled on a Traditional Chinese Windows 11, issue #11). Strict UTF-8
# first, then the OEM code page.
function Run-Netsh([string[]]$netshArgs) {
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $p = Start-Process netsh.exe -ArgumentList $netshArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp
    $bytes = [IO.File]::ReadAllBytes($tmp)
    try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { $text = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage).GetString($bytes) }
    return @($text -split "`r?`n")
  } catch { return @() } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

# Service log, the rotated copy first (oldest lines first).
$serviceLog = @(Read-All (Join-Path $state 'service.log.1')) + @(Read-All (Join-Path $state 'service.log'))
$engineDir = Join-Path $UserData 'nekodrop'
$engineLog = @(Read-All (Join-Path $engineDir 'engine.log.old')) + @(Read-All (Join-Path $engineDir 'engine.log'))
$appleIdLog = Read-All (Join-Path $engineDir 'appleid\appleid.log')
$installLog = Read-All (Join-Path $state 'install.log')
$restoreLog = Read-All (Join-Path $state 'restore.log')

# --------------------------------------------------------------- redaction
# SSIDs: Windows' saved profiles, the current connection and the names the
# service logged; longest first so a name inside another goes second.
$ssids = New-Object System.Collections.Generic.List[string]
foreach ($line in (Run-Netsh @('wlan', 'show', 'profiles'))) {
  if ($line -match '^\s{4}.+?\s:\s(.+)$') { $ssids.Add($Matches[1].Trim()) }
}
$wlanInterfaces = Run-Netsh @('wlan', 'show', 'interfaces')
foreach ($line in $wlanInterfaces) {
  if ($line -match '^\s*SSID\s*:\s(.+)$') { $ssids.Add($Matches[1].Trim()) }
}
foreach ($line in $serviceLog) {
  foreach ($m in [regex]::Matches($line, '(?:joining|connecting to|chosen in nekodrop|Forget|forget)\s+"([^"]+)"')) { $ssids.Add($m.Groups[1].Value) }
  foreach ($m in [regex]::Matches($line, '^\S+ \S+ Wi-Fi: "([^"]+)"')) { $ssids.Add($m.Groups[1].Value) }
}
$ssidList = @($ssids | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object -Unique | Sort-Object Length -Descending)
$macMap = @{}
$ipMap = @{}
function Redact([string]$s) {
  if (-not $s) { return $s }
  $i = 0
  foreach ($name in $ssidList) { $i++; $s = $s.Replace($name, "<SSID-$i>") }
  # "event: bss <bssid> <channel> <dBm> <security> <ssid hex>": the name in hex.
  $s = [regex]::Replace($s, '(event: bss \S+ \S+ \S+ \S+ )[0-9A-Fa-f]+', '$1<ssid-hex>')
  $s = [regex]::Replace($s, '\b[0-9A-Fa-f]{2}([:-])[0-9A-Fa-f]{2}(\1[0-9A-Fa-f]{2}){4}\b', {
    param($m) $k = $m.Value.ToLower().Replace('-', ':')
    if (-not $macMap.ContainsKey($k)) { $macMap[$k] = "<MAC-$($macMap.Count + 1)>" }
    $macMap[$k] })
  # Private, link-local and CGNAT IPv4 (version numbers such as 23.150.0.4 stay).
  $s = [regex]::Replace($s, '\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01])|169\.254|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b', {
    param($m) if (-not $ipMap.ContainsKey($m.Value)) { $ipMap[$m.Value] = "<IP-$($ipMap.Count + 1)>" }
    $ipMap[$m.Value] })
  $s = [regex]::Replace($s, '(?i)\b(?:fe80|f[cd][0-9a-f]{2}|2[0-9a-f]{3}):[0-9a-f:%]{2,}[0-9a-f]', '<IPv6>')
  $s = [regex]::Replace($s, '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '<email>')
  $s = [regex]::Replace($s, '(?i)([A-Z]:\\Users\\)[^\\\s"]+', '$1<user>')
  if ($UserName -and $UserName.Length -ge 2) { $s = $s.Replace($UserName, '<user>') }
  if ($env:COMPUTERNAME) { $s = $s.Replace($env:COMPUTERNAME, '<pc>') }
  return $s
}

# ------------------------------------------------------------- collection
$os = Try-Get { Get-CimInstance Win32_OperatingSystem }
$cv = Try-Get { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' }
$cs = Try-Get { Get-CimInstance Win32_ComputerSystem }
$cpu = Try-Get { (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim() }
$dg = Try-Get { Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard }
$svc = Get-Service NekoDropService -ErrorAction SilentlyContinue
$svcStart = Try-Get { (Get-CimInstance Win32_Service -Filter "Name='NekoDropService'").StartMode }
$exe = Join-Path $app 'NekoDropService.exe'
$version = Try-Get { (Get-Item $exe).VersionInfo.ProductVersion }
$config = Try-Get { Get-Content (Join-Path $state 'service.json') -Raw | ConvertFrom-Json }
# Every present device once: the supported card and the other wireless cards
# below both come from it.
$pnpAll = @(Try-Get { Get-PnpDevice -PresentOnly } | Where-Object { $_ })
$card = $pnpAll | Where-Object { $_.InstanceId -match $SupportedCardPattern } | Select-Object -First 1
# A device property as text ('' when missing); any device, not only $card, so
# the report can show an unsupported card's driver too.
function Dev-Prop([string]$instanceId, [string]$key) {
  if (-not $instanceId) { return '' }
  $v = Try-Get { (Get-PnpDeviceProperty -InstanceId $instanceId -KeyName $key -ErrorAction Stop).Data }
  if ($null -eq $v) { return '' } else { return "$v" }
}
function Card-Prop([string]$key) {
  if (-not $card) { return '' }
  return (Dev-Prop $card.InstanceId $key)
}
# The other wireless cards (not $card), up to 5, PCIe first. Three sources, as
# each misses some: (1) the adapter's medium, NdisPhysicalMedium 9 = native
# 802.11, which is language-independent and never an Ethernet chip; (2) a known
# Wi-Fi chip ID, which also finds a disabled card or one with no driver (then
# it is no network adapter and has no class); (3) the adapter's name. Only
# physical devices (PCI\, USB\): Wi-Fi Direct and TAP adapters are virtual.
function Find-OtherWireless($pnp, [string]$exclude) {
  $candidates = @()
  foreach ($a in @(Try-Get { Get-NetAdapter -IncludeHidden -ErrorAction Stop } | Where-Object { $_ })) {
    if ($a.PnPDeviceID -and ($a.NdisPhysicalMedium -eq 9 -or "$($a.PhysicalMediaType)" -match '802\.11|Wireless')) {
      $candidates += @($pnp | Where-Object { $_.InstanceId -eq $a.PnPDeviceID })
    }
  }
  # Match exact known Wi-Fi VEN:DEV pairs across all PnP classes, so a card
  # with no driver (Class = Unknown) or bound to WinAwdlRadio is still found.
  $candidates += @($pnp | Where-Object { Test-KnownWifiId $_.InstanceId })
  # Do not match bare "Killer" (Ethernet chips E2600/E3100 use it too); match
  # Killer wireless models only.
  $candidates += @($pnp | Where-Object { $_.Class -eq 'Net' -and "$($_.FriendlyName)" -match 'Wi-?Fi|Wireless|802\.11|WLAN|RZ[67]\d\d|FastConnect|Killer.*(?:AX|BE|1[4567]\d\d)|无线|無線' })
  $seen = @{}
  $found = foreach ($d in $candidates) {
    if (-not $d -or "$($d.InstanceId)" -notmatch '^(PCI|USB)\\') { continue }
    if ($exclude -and $d.InstanceId -eq $exclude) { continue }
    $k = "$($d.InstanceId)".ToUpper()
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = $true
    $d
  }
  return @($found | Where-Object { $_ } | Sort-Object { if ($_.InstanceId -match '^PCI\\') { 0 } else { 1 } } | Select-Object -First 5)
}
$otherWireless = @(Find-OtherWireless $pnpAll $(if ($card) { $card.InstanceId } else { '' }))
# A card without a driver may have no friendly name yet.
function Dev-Name($dev) {
  if ($dev.FriendlyName) { return (Redact $dev.FriendlyName) }
  if ($dev.Name) { return (Redact $dev.Name) }
  return 'unnamed device'
}
# One line per device: name, ID without the instance part (a USB adapter's
# serial, often its MAC address), and what nekodrop makes of it.
function Wireless-Summary($dev) {
  $c = Classify-WifiCard $dev.InstanceId
  $hw = if ($c.Bus -and $c.HardwareId -and $c.HardwareId -ne $c.Bus) { "$($c.Bus)\$($c.HardwareId)" } else { $c.HardwareId }
  return "$(Dev-Name $dev) (``$(Redact $hw)``): $($c.Chip), $($c.Status)"
}
$procs = @('nekodrop-radio', 'nekodrop-radio-rtl', 'nekodrop-radio-usb', 'nekodrop-radio-mt', 'nekodrop-radio-mtk', 'awdld', 'nekodrop', 'NekoDropService') | ForEach-Object {
  $p = Get-Process $_ -ErrorAction SilentlyContinue
  if ($p) { "$_ (running)" } else { "$_ (not running)" }
}
$engineRunning = Try-Get { @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like '*engine.py*' }).Count }

# Bring-up of the last radio start, from the service log.
# It begins at the last "radio: card" line, or at the "taking the card" line
# just before it (or after it, when the last attempt failed at the bind).
$attempt = @()
$lastRadio = -1; $lastTake = -1
for ($i = 0; $i -lt $serviceLog.Count; $i++) {
  if ($serviceLog[$i] -match 'radio: card 0x|mtkradio: regproxy opened:') { $lastRadio = $i }
  elseif ($serviceLog[$i] -match 'taking the card from') { $lastTake = $i }
}
$start = $lastRadio
if ($lastTake -gt $lastRadio) { $start = $lastTake }
elseif ($lastTake -ge 0 -and $lastRadio -ge 0) {
  $between = $serviceLog[$lastTake..$lastRadio] | Where-Object { $_ -match 'radio: card 0x|mtkradio: regproxy opened:' }
  if (@($between).Count -eq 1) { $start = $lastTake }
}
if ($start -ge 0) { $attempt = $serviceLog[$start..($serviceLog.Count - 1)] }
function Stage([string]$name, [string]$ok, [string]$bad, [string]$skipIf = '') {
  $okLine = $attempt | Where-Object { $_ -match $ok } | Select-Object -Last 1
  $badLine = if ($bad) { $attempt | Where-Object { $_ -match $bad } | Select-Object -Last 1 } else { $null }
  if ($skipIf -and -not ($attempt | Where-Object { $_ -match $skipIf })) { return "| $name | - | not applicable |" }
  if ($badLine) { return "| $name | FAIL | ``$(Redact (($badLine -replace '^\S+ \S+ ', '') -replace '\|', '/'))`` |" }
  if ($okLine) { return "| $name | ok | ``$(Redact (($okLine -replace '^\S+ \S+ ', '') -replace '\|', '/'))`` |" }
  return "| $name | ? | not reached |"
}

# --------------------------------------------------------------- the report
$sb = New-Object System.Text.StringBuilder
function W([string]$s = '') { [void]$sb.AppendLine($s) }

W '# nekodrop diagnostic report'
W ''
W "Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm'). SSIDs, MAC and IP addresses, the user and computer names are replaced by placeholders; please look it over before posting."
W ''
W '## Summary'
W ''
W "- nekodrop: $(if ($version) { $version } else { 'not found at ' + (Redact $app) })"
W "- Windows: $(if ($os) { $os.Caption }) $(if ($cv) { $cv.DisplayVersion }) (build $(if ($cv) { "$($cv.CurrentBuild).$($cv.UBR)" }))"
W "- Service: $(if ($svc) { "$($svc.Status), start $svcStart" } else { 'not installed' }); mode $(if ($config) { $config.Mode } else { '?' })"
# Without a supported card, say which card is there and why it is not (#16).
$cardSummary = if ($card) { "$($card.FriendlyName) ($($card.InstanceId -replace '\\[^\\]+$', ''))" }
  elseif ($otherWireless.Count) { "no supported Wi-Fi card found; detected $(Wireless-Summary $otherWireless[0])$(if ($otherWireless.Count -gt 1) { " (+$($otherWireless.Count - 1) more below)" })" }
  else { 'no supported Wi-Fi card found' }
W "- Card: $cardSummary"
$lastErr = $serviceLog | Where-Object { $_ -match 'start failed|bring-up failed|keeps failing|taking the card failed|LMAC error|UMAC error|firmware error|refusing|cannot give' } | Select-Object -Last 1
# The AirDrop engine's failures too (#4: "none in the log" beside send failures).
$lastEngineErr = $engineLog | Where-Object { $_ -match '"state":"failed"|Traceback|\bERROR\b|send failed|WinError' -and $_ -notmatch 'mdns: (send|query) failed' } | Select-Object -Last 1
W "- Last error: $(if ($lastErr) { '`' + (Redact $lastErr) + '`' } else { 'none in the service log' })"
W "- Last AirDrop engine error: $(if ($lastEngineErr) { '`' + (Redact ($lastEngineErr -replace '`', "'")) + '`' } else { 'none' })"
W ''
W '## Bring-up (last radio start)'
W ''
if ($start -lt 0) {
  W 'No radio start in the service log.'
} else {
  W "From ``$(Redact ($attempt[0] -replace '\|', '/'))``"
  W ''
  W '| Step | Result | Line |'
  W '|---|---|---|'
  W (Stage 'Take the card (driver bind)' 'radio: card 0x|mtkradio: regproxy opened:' 'taking the card failed|binding .* failed|register proxy did not start|register proxy not openable')
  W (Stage 'Identify the card' 'radio: .*\((AX210|22000) family|mtkradio: MTK chip_id=' 'unsupported card|not an Intel device|card does not answer')
  W (Stage 'DMA memory' 'DMA: \d+ pages in use|mtkradio: 32-bit DMA pool locked' 'out of DMA memory for (the rings|receive|the transmit|command|the firmware|the peripheral)|could not lock|DMA: .*fail|SeLockMemoryPrivilege')
  W (Stage 'Load the firmware' 'radio: firmware \S+: \d+ LMAC|mtkradio: loading RAM firmware' 'firmware has more sections|no image loader|cannot read|firmware file')
  W (Stage 'Firmware alive' 'radio: firmware alive|mtkradio: MT792\d firmware booted and ready' 'did not come alive|failed ALIVE|no ALIVE notification|card not ready|APM init failed|hardware start failed')
  W (Stage 'PNVM (AX210 family)' 'PNVM: \d+ bytes for this SKU' 'PNVM: none|PNVM: no buffer|PNVM: out of DMA|no PNVM_INIT_COMPLETE|did not take its platform NVM' 'AX210 family')
  W (Stage 'Firmware init (INIT_COMPLETE)' 'radio: NVM: tx antennas|mtkradio: WFDMA rings allocated' 'no INIT_COMPLETE|INIT_EXTENDED_CFG failed|NVM_ACCESS_COMPLETE failed|reading the NVM failed')
  W (Stage 'Firmware setup commands' 'radio: ready on channel|mtkradio: tuned to ch' 'firmware init commands failed|PHY context add failed|MAC context|binding failed')
  W (Stage 'Radio ready' 'radio: ready on channel|mtkradio: listening on ' 'radio exited during bring-up|never became ready')
  $awdl = $attempt | Where-Object { $_ -match 'rx: \d+ frames, (\d+) AWDL action frames' } | ForEach-Object { [int]$Matches[1] } | Measure-Object -Maximum
  # MIF counts (0.1.9+): awdld takes a peer as valid only after one (#16).
  $mif = $attempt | Where-Object { $_ -match 'AWDL action frames \((\d+) PSF, (\d+) MIF' } | ForEach-Object { [int]$Matches[2] } | Measure-Object -Maximum
  $peers = @($attempt | Where-Object { $_ -match 'event: peer-channel|event: peer-country' }).Count
  W "| AWDL frames heard | $(if ($awdl.Maximum -gt 0) { 'ok' } else { '?' }) | $(if ($awdl.Count) { "up to $($awdl.Maximum) AWDL action frames$(if ($mif.Count) { " ($($mif.Maximum) MIF)" }); $peers peer channel/country events" } else { 'no rx statistics yet' }) |"
  # Transmitting: on a passive 5 GHz channel the radio sends nothing until a
  # beacon (or, 0.1.10+, an AWDL peer) is heard there (#11).
  $txLast = $attempt | Where-Object { $_ -match 'radio: tx: \d+ submitted, \d+ done' } | Select-Object -Last 1
  $txUnlock = $attempt | Where-Object { $_ -match 'transmitting allowed here' } | Select-Object -Last 1
  $txRow = if (-not $txLast) { '?' }
    elseif ($txLast -match 'tx: \d+ submitted, 0 done' -and $txLast -match 'held \(passive channel\)' -and -not $txUnlock) { 'FAIL' }
    else { 'ok' }
  $txWhy = if ($txRow -eq 'FAIL') { 'nothing sent: the channel is passive (the firmware did not take the country) and no beacon or AWDL peer was heard on it' }
    elseif ($txUnlock) { '`' + ($txUnlock -replace '^\S+ \S+ ', '') + '`' }
    elseif ($txLast) { '`' + (($txLast -replace '^\S+ \S+ ', '') -replace '; unicast.*', '') + '`' } else { 'no tx statistics yet' }
  W "| Transmitting | $txRow | $txWhy |"
  # Experimental A-MPDU sending (0.1.15+): prefer the last active (asking/agreed)
  # snapshot over a trailing idle line so completed/fallback sends are not hidden (#4).
  $aggActive = $attempt | Where-Object { $_ -match 'radio: aggregate: (asking|agreed)' } | Select-Object -Last 1
  $aggLast = if ($aggActive) { $aggActive } else { $attempt | Where-Object { $_ -match 'radio: aggregate: (idle|asking|agreed)' } | Select-Object -Last 1 }
  if ($aggLast) {
    $aggRow = if ($aggLast -match 'aggregate: agreed') { 'ok' } elseif ($aggLast -match 'aggregate: asking') { 'asking' } else { '-' }
    W "| A-MPDU sending | $aggRow | ``$((($aggLast -replace '^\S+ \S+ radio: \S+ radio: ', '') -replace '\|', '/'))`` |"
  }
  # The latest station event decides: "authenticating" is a step of every join,
  # not a failure (#4, #14, #16 all showed FAIL while connected).
  $wifiLast = $attempt | Where-Object { $_ -match 'event: wifi \S|not supported beside AirDrop|not joining a saved network' } | Select-Object -Last 1
  $wifiRow = if (-not $wifiLast) { 'not applicable' }
    elseif ($wifiLast -match 'event: wifi connected') { 'ok' }
    elseif ($wifiLast -match 'event: wifi (failed|deauth)|not supported beside AirDrop') { 'FAIL' }
    elseif ($wifiLast -match 'not joining a saved network') { 'not applicable' }
    else { 'joining' }
  W "| Wi-Fi station | $(if ($wifiRow -eq 'not applicable') { '-' } else { $wifiRow }) | $(if ($wifiLast) { '`' + (Redact (($wifiLast -replace '^\S+ \S+ ', '') -replace '\|', '/')) + '`' } else { 'no station in this start' }) |"
  W ''
  $fw = $attempt | Where-Object { $_ -match 'LMAC error|UMAC error|SecBoot|UMAC PC' } | Select-Object -Last 4
  if ($fw) {
    W 'Firmware error tables:'
    W ''
    W '```'
    $fw | ForEach-Object { W (Redact $_) }
    W '```'
    W ''
  }
}

W '## System'
W ''
W "- Computer: $(if ($cs) { "$($cs.Manufacturer) $($cs.Model)" })"
W "- CPU: $cpu"
W "- Edition: $(if ($cv) { $cv.EditionID }), $(if ($os) { $os.OSArchitecture })"
W "- VBS: $(if ($dg) { @('off', 'configured', 'running')[[int]$dg.VirtualizationBasedSecurityStatus] } else { '?' }); services running: $(if ($dg) { ($dg.SecurityServicesRunning -join ',') } else { '?' }) (2 = HVCI / Memory Integrity)"
W "- Processes: $($procs -join ', '); AirDrop engine (python): $(if ($engineRunning) { 'running' } else { 'not running' })"
W ''

W '## Wi-Fi card'
W ''
if ($card) {
  W "- Device: $($card.FriendlyName), status $($card.Status), class $($card.Class)"
  W "- Hardware ID: ``$(($card.InstanceId -split '\\')[1])``"
  W "- Driver: service $(Card-Prop 'DEVPKEY_Device_Service'), INF $(Card-Prop 'DEVPKEY_Device_DriverInfPath'), version $(Card-Prop 'DEVPKEY_Device_DriverVersion'), provider $(Card-Prop 'DEVPKEY_Device_DriverProvider')"
  $problem = Card-Prop 'DEVPKEY_Device_ProblemCode'
  W "- Device Manager problem code: $(if ($problem) { $problem } else { '0' }) (0 = none; 10 = cannot start; 28 = no driver; 31/37/39 = driver did not load; 52 = signature)"
  # The NTSTATUS behind a problem code (#18: code 31 with 0xC0000494 on Windows 10).
  $problemStatus = Card-Prop 'DEVPKEY_Device_ProblemStatus'
  if ($problemStatus) { W ("- Problem status: 0x{0:X8}" -f ([int64]$problemStatus -band 0xFFFFFFFF)) }
  W "- Vendor driver to give it back to: $(if ($config -and $config.VendorInf) { Split-Path $config.VendorInf -Leaf } else { 'not recorded' })"
  # Windows' own record of the card's driver installs and start failures.
  $devId = ($card.InstanceId -split '\\')[1] -replace '&SUBSYS.*$', ''
  $pnp = @(Try-Get { Get-WinEvent -LogName 'Microsoft-Windows-Kernel-PnP/Configuration' -MaxEvents 400 -ErrorAction Stop |
           Where-Object { $_.Message -like "*$devId*" } | Select-Object -First 8 } | Where-Object { $_ })
  if ($pnp.Count) {
    W '- Recent driver events (Kernel-PnP):'
    W ''
    W '```'
    $pnp | ForEach-Object { W (Redact ("$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) [$($_.Id)] " + (($_.Message -split "`r?`n" | Where-Object { $_.Trim() }) -join ' | '))) }
    W '```'
    W ''
  }
  $umdf = @(Try-Get { Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-DriverFrameworks-UserMode' } -MaxEvents 6 -ErrorAction Stop } | Where-Object { $_ })
  if ($umdf.Count) {
    W '- Recent user-mode driver (UMDF) events:'
    W ''
    W '```'
    $umdf | ForEach-Object { W (Redact ("$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')) [$($_.Id)] " + (($_.Message -split "`r?`n" | Where-Object { $_.Trim() }) -join ' | '))) }
    W '```'
    W ''
  }
  # Windows' device-install log for the register proxy's last install: why a
  # driver bound but did not start shows up here (#18, Windows 10).
  $setupLog = Join-Path $env:windir 'INF\setupapi.dev.log'
  $setupLines = @(Try-Get { Get-Content $setupLog -Tail 6000 -ErrorAction Stop })
  if ($setupLines.Count) {
    # Section starts; the last one that installed the register proxy is the
    # one that explains a failed bind (giving the card back installs Intel's
    # driver afterwards, in its own section).
    $all = @(for ($i = 0; $i -lt $setupLines.Count; $i++) { if ($setupLines[$i] -match '^>>>  \[') { $i } })
    $starts = @(for ($k = 0; $k -lt $all.Count; $k++) {
      $last = if ($k + 1 -lt $all.Count) { $all[$k + 1] - 1 } else { $setupLines.Count - 1 }
      if (($setupLines[$all[$k]..$last] -join ' ') -match 'winawdl_regproxy|RegProxy|WUDFRd') { $all[$k] }
    })
    if ($starts.Count) {
      $from = $starts[-1]
      $section = @($setupLines[$from..($setupLines.Count - 1)])
      $end = [Array]::FindIndex([string[]]$section, [Predicate[string]] { param($l) $l -match '^<<<  \[Exit status' })
      if ($end -ge 0) { $section = $section[0..$end] }
      $keep = @($section | Where-Object { $_ -match '^(>>>|<<<)|!!!|^\s+!|Exit status|[Ss]ervice|WUDF|Install|Driver Node|Selected|Status|error|failed' } | Select-Object -First 45)
      if ($keep.Count) {
        W '- Last device install (setupapi.dev.log):'
        W ''
        W '```'
        $keep | ForEach-Object { W (Redact $_.TrimEnd()) }
        W '```'
        W ''
      }
    }
  }
  $radioCard = $serviceLog | Where-Object { $_ -match 'radio: card 0x|\((AX210|22000) family' } | Select-Object -Last 2
  $radioCard | ForEach-Object { W "- Radio: ``$(Redact ($_ -replace '^\S+ \S+ radio: \S+ radio: ', ''))``" }
  # A second wireless card (a desktop with a USB stick, a laptop with an added
  # card) can confuse which one Windows uses for its own Wi-Fi.
  $otherWireless | ForEach-Object { W "- Additional wireless device: $(Wireless-Summary $_)" }
} else {
  W 'No Wi-Fi card nekodrop supports is present.'
  # Each wireless card that is there, with what it is and its driver, so a
  # report tells an unlisted ID from a card nekodrop cannot drive (#16).
  foreach ($o in $otherWireless) {
    $c = Classify-WifiCard $o.InstanceId
    W ''
    W "- Other wireless device: $(Dev-Name $o), bus $(if ($c.Bus) { $c.Bus } else { '?' }), status $($o.Status), class $(if ($o.Class) { $o.Class } else { 'none (no driver)' })"
    W "  - Hardware ID: ``$(Redact $c.HardwareId)``"
    W "  - Chip: $($c.Chip); $($c.Status)"
    if ($c.Note) { W "  - $($c.Note)" }
    $svcName = Dev-Prop $o.InstanceId 'DEVPKEY_Device_Service'
    $inf = Dev-Prop $o.InstanceId 'DEVPKEY_Device_DriverInfPath'
    $drvVer = Dev-Prop $o.InstanceId 'DEVPKEY_Device_DriverVersion'
    $drvProv = Dev-Prop $o.InstanceId 'DEVPKEY_Device_DriverProvider'
    W "  - Driver: service $(if ($svcName) { Redact $svcName } else { 'none' }), INF $(if ($inf) { Redact $inf } else { 'none' }), version $(if ($drvVer) { Redact $drvVer } else { '?' }), provider $(if ($drvProv) { Redact $drvProv } else { '?' })"
    $oProblem = Dev-Prop $o.InstanceId 'DEVPKEY_Device_ProblemCode'
    W "  - Device Manager problem code: $(if ($oProblem) { $oProblem } else { '0' })"
  }
  if ($otherWireless.Count) {
    W ''
    W 'Which cards nekodrop can support, and why: https://github.com/zytstudio/nekodrop/blob/main/docs/HARDWARE.md'
  }
}
if ($config) {
  W "- Settings: mode $($config.Mode), country '$($config.Country)', start channel $($config.StartChannel), peer channel $($config.PeerChannel), on-demand idle $($config.IdleSeconds) s"
  # The experimental switches change how the radio sends and scans: say which are on.
  # A-MPDU has no switch since 0.1.35 (an old config's "Aggregate" field is stale, so ignore it).
  W "- Faster sending: always on (0.1.25+). A-MPDU sending: always on (0.1.35+). Balanced Bluetooth coexistence: always on, Intel (0.1.37+). Experimental: fast passive-channel unlock $(if ($config.FastUnlock) { 'on' } else { 'off' })"
}
W ''

W '## Network'
W ''
W '| Adapter | Description | Status | Speed | Metric (IPv4) |'
W '|---|---|---|---|---|'
$ifs = Try-Get { Get-NetIPInterface -AddressFamily IPv4 -ErrorAction Stop }
$presentAdapters = @(Try-Get { Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object { $_.Status -ne 'Not Present' } })
foreach ($a in $presentAdapters) {
  $metric = ($ifs | Where-Object { $_.InterfaceIndex -eq $a.ifIndex } | Select-Object -First 1).InterfaceMetric
  W "| $(Redact $a.Name) | $(Redact $a.InterfaceDescription) | $($a.Status) | $($a.LinkSpeed) | $metric |"
}
W ''
if (-not ($presentAdapters | Where-Object { $_.Name -eq 'nekodrop' })) {
  $hiddenTap = @(Try-Get { Get-NetAdapter -Name 'nekodrop' -IncludeHidden -ErrorAction Stop })
  if ($hiddenTap.Count) {
    W "nekodrop TAP adapter: $($hiddenTap[0].Status) ($($hiddenTap[0].InterfaceDescription))"
  } else {
    W 'nekodrop TAP adapter: missing'
  }
  W ''
}
$routes = @(Try-Get { Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop })
W "Default routes: $($routes.Count)"
foreach ($r in $routes) { W "- $(Redact $r.InterfaceAlias): route metric $($r.RouteMetric), interface metric $(($ifs | Where-Object { $_.InterfaceIndex -eq $r.ifIndex } | Select-Object -First 1).InterfaceMetric)" }
W ''
W 'Windows Wi-Fi (netsh wlan show interfaces; names and addresses removed):'
W ''
W '```'
foreach ($line in $wlanInterfaces) {
  if ($line -match '^\s*$' -or $line -match '(?i)SSID|Physical|物理|Profile|配置文件|Hosted|承载') { continue }
  W (Redact $line.TrimEnd())
}
W '```'
W ''
$excludedPorts = @(Run-Netsh @('interface', 'ipv6', 'show', 'excludedportrange', 'protocol=tcp') | Where-Object { $_ -match '^\s*\d+\s+\d+' })
if ($excludedPorts.Count) {
  W 'TCP IPv6 excluded port ranges (Hyper-V / WinNAT):'
  W ''
  W '```'
  $excludedPorts | Select-Object -First 30 | ForEach-Object { W $_.Trim() }
  W '```'
  W ''
}

W '## Bluetooth'
W ''
$bt = @(Try-Get { Get-PnpDevice -PresentOnly -Class Bluetooth -ErrorAction Stop | Where-Object { $_.FriendlyName -notmatch 'Enumerator|RFCOMM|LE Generic|Avrcp|Hands-?free|Audio' } | Select-Object -First 6 } | Where-Object { $_ })
if ($bt.Count) { $bt | ForEach-Object { W "- $(Redact $_.FriendlyName): $($_.Status)" } } else { W 'No Bluetooth adapter found.' }
W ''

W '## Discovery timeline'
W ''
if ($start -ge 0) {
  W "Discovery timing (last radio start, seconds after ``$(Redact (($attempt[0] -replace '^\S+ \S+ ', '') -replace '\|', '/'))``):"
  W ''
  W '| Step | After | Line |'
  W '|---|---|---|'
  Get-DiscoverySummary $attempt $engineLog | ForEach-Object { W (Redact $_) }
  W ''
}
W 'Service (radio ready, AWDL channel and peers, Wi-Fi):'
W ''
W '```'
$lastAwdl = -1
$timeline = foreach ($line in ($serviceLog | Select-Object -Last 4000)) {
  # Also what unlocks a passive channel and the first steps of discovery (#11).
  if ($line -match 'ready on channel|event: peer-channel|event: peer-country|event: channel|moving there|stayed passive|starting:|stopping:|Wi-Fi: joining|event: wifi |gateway|transmitting allowed here|regulatory: firmware notice|is passive: |fast discovery scan done|discovery: first |experimental fast passive-channel unlock') { $line }
  elseif ($line -match 'rx: \d+ frames, (\d+) AWDL action frames') {
    $n = [int]$Matches[1]
    if (($lastAwdl -le 0 -and $n -gt 0) -or ($n -lt $lastAwdl)) { $line }
    $lastAwdl = $n
  }
}
$timeline | Select-Object -Last 40 | ForEach-Object { W (Redact $_) }
W '```'
W ''
W 'Client (looking for devices, Bluetooth beacon, peers, transfers):'
W ''
W '```'
$engineLog | Where-Object { $_ -match '"event":"(looking|peer|lost|ask|progress|done|error|engine)"|beacon|Traceback|ERROR|WARNING' } |
  Select-Object -Last 40 | ForEach-Object { W (Redact $_) }
W '```'
W ''

W '## Key log lines'
W ''
W '```'
$serviceLog | Where-Object { $_ -match '(?i)error|fail|refus|cannot|could not|timed out|not supported|exited|restart|giving the card|taking the card|ready on|PNVM|INIT_COMPLETE|NVM:|alive|unsupported' } |
  Select-Object -Last 120 | ForEach-Object { W (Redact $_) }
W '```'
W ''

function Details([string]$title, $lines) {
  W '<details>'
  W "<summary>$title</summary>"
  W ''
  W '```'
  $lines | ForEach-Object { W (Redact $_) }
  W '```'
  W ''
  W '</details>'
  W ''
}
Details 'service.log (last 250 lines)' ($serviceLog | Select-Object -Last 250)
Details 'engine.log (last 150 lines)' ($engineLog | Select-Object -Last 150)
if ($appleIdLog.Count) { Details 'appleid.log (last 80 lines)' ($appleIdLog | Select-Object -Last 80) }
Details 'install.log (last 80 lines)' ($installLog | Select-Object -Last 80)

$report = $sb.ToString()
# GitHub takes at most 65536 characters in an issue body.
if ($report.Length -gt 60000) {
  $report = $report.Substring(0, 60000) + "`n`n(cut at 60000 characters; the full logs are in the .txt file)`n"
}
[IO.File]::WriteAllText($reportPath, $report, (New-Object System.Text.UTF8Encoding($false)))

# ---------------------------------------------------------- full logs file
$full = New-Object System.Text.StringBuilder
foreach ($part in @(
    @('service.log (+ service.log.1)', $serviceLog),
    @('engine.log (+ engine.log.old)', $engineLog),
    @('appleid.log', $appleIdLog),
    @('install.log', $installLog),
    @('restore.log', $restoreLog))) {
  [void]$full.AppendLine("===== $($part[0]) =====")
  foreach ($l in $part[1]) { [void]$full.AppendLine((Redact $l)) }
  [void]$full.AppendLine()
}
[IO.File]::WriteAllText($logsPath, $full.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "nekodrop: report written to $reportPath"
Write-Host "nekodrop: full logs written to $logsPath"
if (-not $NoOpen) {
  try { Set-Clipboard -Value $report } catch { }
  Start-Process notepad.exe -ArgumentList "`"$reportPath`""
  Start-Process explorer.exe -ArgumentList "/select,`"$reportPath`""
  Write-Host 'The report is also on the clipboard. Paste it into a GitHub issue and attach the .txt file.'
  Start-Sleep -Seconds 3
}
