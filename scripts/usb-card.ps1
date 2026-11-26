#Requires -RunAsAdministrator
# Gives the RTL8821CU USB dongle to nekodrop (binds the WinUSB package) or hands
# it back to Realtek's driver. A development and verification tool: the service
# does the same binding when it first takes the dongle, and restore.ps1 gives it
# back. Unlike a PCIe card the dongle cannot be shared, so -Take turns its Wi-Fi
# off until -GiveBack.
#
#   scripts\usb-card.ps1 -Take        bind driver\winusb (signed here, this PC)
#   scripts\usb-card.ps1 -GiveBack    delete that package and re-detect
param([switch]$Take, [switch]$GiveBack)
$ErrorActionPreference = 'Stop'
if ($Take -eq $GiveBack) { throw 'Pass exactly one of -Take or -GiveBack.' }

. "$PSScriptRoot\toolchain.ps1"
$repo = Split-Path $PSScriptRoot -Parent
$tools = Initialize-Toolchain
$package = Join-Path $repo 'build\winusb'
$inf = Join-Path $package 'nekodrop_winusb.inf'
$catalog = Join-Path $package 'nekodrop_winusb.cat'
$certSubject = 'CN=nekodrop driver (signed on this PC)'
$ids = @('USB\VID_0BDA&PID_C820&MI_02', 'USB\VID_0BDA&PID_C821&MI_02')

function Show-Card {
  Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like 'USB\VID_0BDA&PID_C82*' } |
    ForEach-Object {
      $svc = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction SilentlyContinue).Data
      "  $($_.FriendlyName) ($($_.Status)), service $svc"
    }
}

'Before:'
Show-Card

if ($Take) {
  & "$PSScriptRoot\..\driver\winusb\build.ps1" | Out-Null
  $signTool = $tools.SignTool
  $cert = Get-ChildItem Cert:\CurrentUser\My |
          Where-Object { $_.Subject -eq $certSubject -and $_.HasPrivateKey } |
          Sort-Object NotAfter | Select-Object -Last 1
  if (-not $cert) {
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certSubject `
              -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable `
              -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(2)
  }
  foreach ($store in 'Root', 'TrustedPublisher') {
    if (-not (Test-Path "Cert:\LocalMachine\$store\$($cert.Thumbprint)")) {
      $cer = Join-Path $package 'nekodrop-signing.cer'
      Export-Certificate -Cert $cert -FilePath $cer -Force | Out-Null
      Import-Certificate -FilePath $cer -CertStoreLocation "Cert:\LocalMachine\$store" | Out-Null
    }
  }
  & $signTool sign /fd SHA256 /s My /sha1 $cert.Thumbprint $catalog
  if ($LASTEXITCODE -ne 0) { throw "signtool failed ($LASTEXITCODE)" }

  # Add the package, then bind the Wi-Fi FUNCTION by ID: /install would also take
  # any other device the INF lists, and the composite parent must keep usbccgp.
  pnputil /add-driver $inf | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "pnputil could not add the package ($LASTEXITCODE)" }
  Add-Type -Namespace NekoUsb -Name NewDev -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("newdev.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern bool UpdateDriverForPlugAndPlayDevicesW(System.IntPtr hwnd, string hardwareId, string infPath, uint flags, out bool reboot);
'@
  foreach ($id in $ids) {
    $r = $false
    $ok = [NekoUsb.NewDev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $id, $inf, 1, [ref]$r)
    "  $id -> $ok"
  }
} else {
  $store = [xml](pnputil /enum-drivers /format xml | Out-String)
  $store.PnpUtil.Driver |
    Where-Object { $_.OriginalName -eq 'nekodrop_winusb.inf' -and $_.ProviderName -eq 'winairdrop project' } |
    ForEach-Object {
      pnputil /delete-driver $_.DriverName /uninstall /force | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "pnputil /delete-driver $($_.DriverName) exited $LASTEXITCODE" }
    }
  pnputil /scan-devices | Out-Null
  Start-Sleep 3
}

'After:'
Show-Card
