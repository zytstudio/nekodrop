# Values shared by the driver packaging, take-card and give-card scripts.
# Adapted from winawdl's scripts\driver-settings.ps1 for Intel AX201 cards.
$repoRoot = Split-Path $PSScriptRoot -Parent

$DriverSettings = @{
  InfName      = 'winawdl_regproxy.inf'
  BuildDir     = "$repoRoot\driver\regproxy\build"
  PackageDir   = "$repoRoot\driver\regproxy\build\package"
  PackageFiles = @('winawdl_regproxy.inf', 'winawdl_regproxy.dll')
  # The RTL8821CU USB dongle's package: WinUSB, not the register proxy. Bound by
  # scripts\usb-card.ps1 -Take (or by the service), removed by give-card.ps1.
  UsbInfName   = 'nekodrop_winusb.inf'
  UsbDeviceIds = @('C820', 'C821')
  CertSubject  = 'CN=winairdrop driver signing (local test)'
  CertFile     = 'winairdrop-signing.cer'
  # The cards the radio drives (iwxradio/src/cards.h): Qu/QuZ CNVi, AX200, AX210 family.
  DeviceIds    = @('43F0', 'A0F0', '02F0', '06F0', '34F0', '3DF0', '4DF0', '2723', '2725', '7A70', '7AF0', '51F0', '51F1', '54F0', '7F70')
  TrustStores  = @('Root', 'TrustedPublisher')
}

function Get-PublishedPackages {
  $store = [xml](pnputil /enum-drivers /format xml | Out-String)
  $store.PnpUtil.Driver |
    Where-Object { ($_.OriginalName -eq $DriverSettings.InfName -or
                    $_.OriginalName -eq $DriverSettings.UsbInfName) -and
                   $_.ProviderName -eq 'winairdrop project' } |
    ForEach-Object { $_.DriverName }
}

function Get-WifiCard {
  $pci = Get-PnpDevice -PresentOnly |
    Where-Object {
      $id = $_.InstanceId
      $id -like 'PCI\VEN_8086&DEV_*' -and
        ($DriverSettings.DeviceIds | Where-Object { $id -like "PCI\VEN_8086&DEV_$_*" })
    } |
    Select-Object -First 1
  if ($pci) { return $pci }
  # The RTL8821CU USB dongle's device node (its MI_xx functions are not what a
  # driver package binds to).
  Get-PnpDevice -PresentOnly |
    Where-Object {
      $id = $_.InstanceId
      $id -like 'USB\VID_0BDA&PID_*' -and $id -notmatch '&MI_' -and
        ($DriverSettings.UsbDeviceIds | Where-Object { $id -like "USB\VID_0BDA&PID_$_*" })
    } |
    Select-Object -First 1
}

function Get-WifiCardHardwareId {
  $card = Get-WifiCard
  if (-not $card) { return $null }
  # The generic ID the INF matches, e.g. PCI\VEN_8086&DEV_43F0 or USB\VID_0BDA&PID_C820.
  if ($card.InstanceId -like 'USB\*') { return ($card.InstanceId -split '\\')[1] }
  ($card.InstanceId -split '&SUBSYS')[0]
}

function Show-WifiCardDriver {
  $card = Get-WifiCard
  if (-not $card) { 'No supported Intel Wi-Fi card found.'; return }
  $service = (Get-PnpDeviceProperty -InstanceId $card.InstanceId `
                -KeyName DEVPKEY_Device_Service).Data
  $inf = (Get-PnpDeviceProperty -InstanceId $card.InstanceId `
            -KeyName DEVPKEY_Device_DriverInfPath).Data
  "Wi-Fi card: $($card.FriendlyName)"
  "  status $($card.Status), problem code $($card.ConfigManagerErrorCode)"
  "  service $service, driver package $inf"
}

# True when some network other than the Wi-Fi card is up, so taking the card
# does not cut this PC off.
function Test-OtherNetwork {
  $card = Get-WifiCard
  $others = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -eq 'Up' -and $_.PnPDeviceID -ne $card.InstanceId }
  [bool]$others
}
