# Removes nekodrop: gives the Wi-Fi card back to its vendor driver first, then
# removes the service, the driver package, the certificate trust, the firewall
# rules, nekodrop's TAP adapter, settings and the files. Received files stay
# where they were saved. Best effort: a step that fails is reported in
# %ProgramData%\nekodrop-uninstall.log and the rest still runs (#22: failures
# were silent and left parts behind).
#
# -Inno is passed by the Inno Setup uninstaller. It keeps unins000.exe alive
# (the uninstaller is the parent of this PowerShell process) and leaves the
# shortcuts and uninstall registration to Setup, which removes them after this
# script returns. Without it, the install-folder process sweep below would
# kill unins000.exe itself and Setup could never finish its own cleanup.
#
# Needs administrator rights. It is checked at run time, not with
# #Requires -RunAsAdministrator, so -SelfTest can run without elevation.
param([string]$Target = "$env:ProgramFiles\nekodrop", [switch]$Inno, [switch]$SelfTest)
$ErrorActionPreference = 'Continue'
$Service = 'NekoDropService'
$CertSubject = 'CN=nekodrop driver (signed on this PC)'
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{6C1F2E7A-4B8E-4E57-9C61-5E2B1D0A9F31}_is1'

function Try-Step($what, [scriptblock]$do) {
  $what
  try { & $do 2>&1 | ForEach-Object { "  $_" } | Add-Content $Log -ErrorAction SilentlyContinue }
  catch { $script:failures++; "  FAILED: $what - $($_.Exception.Message)" | Tee-Object -Append $Log }
}

# Only a folder that still looks like nekodrop's install folder may be
# recursively removed. A broken or wrong -Target must never delete elsewhere.
function Test-NekodropInstall([string]$Path) {
  if (-not $Path) { return $false }
  try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $false }
  if ($full.Length -le 3 -or -not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
  try { $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop } catch { return $false }
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
  foreach ($name in 'nekodrop.exe', 'NekoDropService.exe') {
    if (Test-Path -LiteralPath (Join-Path $full $name) -PathType Leaf) { return $true }
  }
  # A partially uninstalled folder keeps the uninstaller and the script, but
  # may have lost the two application binaries already.
  return ((Test-Path -LiteralPath (Join-Path $full 'uninstall.ps1') -PathType Leaf) -and
          (Test-Path -LiteralPath (Join-Path $full 'unins000.exe') -PathType Leaf))
}

# unins000.exe is the parent of this PowerShell process when Inno Setup runs
# the uninstaller. Keep it, this process and their ancestors out of the
# install-folder process sweep; otherwise Inno Setup is killed before it can
# remove shortcuts, the uninstall registration and its own files.
function Get-ProtectedProcessIds {
  $keep = @([int]$PID)
  $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $byId = @{}
  foreach ($p in $procs) { $byId[[int]$p.ProcessId] = $p }
  $id = [int]$PID
  while ($byId.ContainsKey($id)) {
    $parent = [int]$byId[$id].ParentProcessId
    if ($parent -le 0 -or $keep -contains $parent) { break }
    $keep += $parent
    $id = $parent
  }
  foreach ($p in @(Get-Process -Name 'unins000' -ErrorAction SilentlyContinue)) {
    $keep += [int]$p.Id
  }
  foreach ($p in $procs) {
    if ($p.Name -eq 'unins000.exe') { $keep += [int]$p.ProcessId }
  }
  return @($keep | Sort-Object -Unique)
}

function Stop-FromTarget {
  $root = [IO.Path]::GetFullPath($Target).TrimEnd('\') + '\'
  # Never by path under a drive root or a folder that is not nekodrop's.
  $byPath = $root.Length -gt 4 -and ((Test-Path (Join-Path $root 'NekoDropService.exe')) -or (Test-Path (Join-Path $root 'python\python.exe')))
  $keep = @(Get-ProtectedProcessIds)
  # Everything running from the install folder, the AirDrop engine's python.exe
  # too (#22). The uninstaller and this PowerShell process are not ours to kill.
  $ours = @(Get-Process nekodrop, nekodrop-radio, nekodrop-radio-rtl, nekodrop-radio-usb, nekodrop-radio-mt, nekodrop-radio-mtk, awdld -ErrorAction SilentlyContinue)
  $ours += @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      try {
        $byPath -and $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and
        ($keep -notcontains [int]$_.Id)
      } catch { $false } })
  # Processes started from elsewhere that name the folder on their command
  # line: airdrop-beacon.ps1's powershell.exe held airdrop\ open (#22).
  $ours += @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
      $byPath -and $_.ProcessId -ne $PID -and ($keep -notcontains [int]$_.ProcessId) -and
      $_.CommandLine -and $_.CommandLine.IndexOf($root.TrimEnd(''), [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
    ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
  $ours = @($ours | Where-Object { $keep -notcontains [int]$_.Id } | Sort-Object Id -Unique)
  $ours | Stop-Process -Force -ErrorAction SilentlyContinue
  $ours | ForEach-Object { try { $_.WaitForExit(10000) | Out-Null } catch { } }
  $ours
}

function Remove-NekodropPath([string]$Path, [switch]$KeepUninstaller) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "Refusing reparse point: $Path"
  }
  if (-not $item.PSIsContainer) {
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    return
  }
  $skip = @()
  if ($KeepUninstaller) { $skip = @('unins000.exe', 'unins000.dat') }
  $bad = @()
  foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)) {
    if ($skip -contains $child.Name) { continue }
    try { Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop }
    catch { $bad += "$($child.FullName): $($_.Exception.Message)" }
  }
  if (-not $KeepUninstaller) {
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
    catch { $bad += "$($Path): $($_.Exception.Message)" }
  } elseif (-not (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  }
  if ($bad) { throw ($bad -join '; ') }
}

function Remove-NekodropShortcuts {
  $names = @('nekodrop.lnk', 'nekodrop - diagnostic report.lnk', 'nekodrop - restore Windows Wi-Fi.lnk')
  $startDirs = @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
  )
  foreach ($dir in $startDirs) {
    foreach ($name in $names) {
      Remove-Item -LiteralPath (Join-Path $dir $name) -Force -ErrorAction SilentlyContinue
    }
  }
  foreach ($dir in @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Desktop'))) {
    if ($dir) { Remove-Item -LiteralPath (Join-Path $dir 'nekodrop.lnk') -Force -ErrorAction SilentlyContinue }
  }
}

function Remove-NekodropRegistration {
  if (Test-Path -LiteralPath $UninstallKey) {
    Remove-Item -LiteralPath $UninstallKey -Recurse -Force -ErrorAction Stop
  }
}

function Invoke-ClientUnregister {
  $client = Join-Path $Target 'nekodrop.exe'
  if (-not (Test-Path -LiteralPath $client -PathType Leaf)) { return }
  $p = Start-Process -FilePath $client -ArgumentList '--unregister' -PassThru -WindowStyle Hidden -ErrorAction Stop
  if (-not $p.WaitForExit(15000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    throw 'nekodrop.exe --unregister did not exit within 15 seconds'
  }
  if ($p.ExitCode -ne 0) { throw "nekodrop.exe --unregister exited $($p.ExitCode)" }
}

if ($SelfTest) {
  $fail = @()
  $temps = @()
  try {
    $tmp = Join-Path $env:TEMP ('nekodrop-uninstall-selftest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -ErrorAction Stop | Out-Null
    $temps += $tmp
    foreach ($name in 'nekodrop.exe', 'NekoDropService.exe', 'uninstall.ps1', 'unins000.exe', 'unins000.dat') {
      New-Item -ItemType File -Path (Join-Path $tmp $name) -ErrorAction Stop | Out-Null
    }
    if (-not (Test-NekodropInstall $tmp)) { $fail += 'a complete install folder was not recognized' }

    $other = Join-Path $env:TEMP ('nekodrop-uninstall-selftest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $other -ErrorAction Stop | Out-Null
    $temps += $other
    New-Item -ItemType File -Path (Join-Path $other 'other.exe') -ErrorAction Stop | Out-Null
    if (Test-NekodropInstall $other) { $fail += 'an unrelated folder was accepted as the install folder' }
    if (Test-NekodropInstall ([IO.Path]::GetPathRoot($env:SystemRoot))) { $fail += 'a drive root was accepted as the install folder' }

    $keep = @(Get-ProtectedProcessIds)
    if ($keep -notcontains [int]$PID) { $fail += 'the current process is not protected' }
    $parent = [int](Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue).ParentProcessId
    if ($parent -gt 0 -and $keep -notcontains $parent) { $fail += 'the parent process is not protected' }

    Remove-NekodropPath -Path $tmp -KeepUninstaller
    foreach ($name in 'unins000.exe', 'unins000.dat') {
      if (-not (Test-Path -LiteralPath (Join-Path $tmp $name) -PathType Leaf)) { $fail += "$name was removed with -KeepUninstaller" }
    }
    foreach ($name in 'nekodrop.exe', 'NekoDropService.exe', 'uninstall.ps1') {
      if (Test-Path -LiteralPath (Join-Path $tmp $name)) { $fail += "$name survived -KeepUninstaller" }
    }
    Remove-NekodropPath -Path $tmp
    if (Test-Path -LiteralPath $tmp) { $fail += 'the test install folder survived a full remove' }
  } catch {
    $fail += $_.Exception.Message
  } finally {
    foreach ($path in $temps) {
      Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if ($fail) { $fail | ForEach-Object { Write-Host "FAIL $_" }; exit 1 }
  Write-Host 'uninstall.ps1 self-test: target guard, process protection and file cleanup passed'
  exit 0
}

# --------------------------------------------------------------- elevation
# What "#Requires -RunAsAdministrator" did, before anything is written (the
# log folder below is for administrators only).
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'uninstall.ps1 needs administrator rights: run the nekodrop setup, or this script from an administrator PowerShell.'
  exit 1
}

$Log = Join-Path $env:ProgramData 'nekodrop-uninstall.log'
"nekodrop uninstall $(Get-Date -Format s), target $Target" | Set-Content $Log -ErrorAction SilentlyContinue
$failures = 0

Try-Step 'Giving the Wi-Fi card back' {
  if (Get-Service $Service -ErrorAction SilentlyContinue) {
    Stop-Service $Service -Force -ErrorAction SilentlyContinue  # the card is given back below either way
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Service $Service).Status -ne 'Stopped' -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  }
  Stop-FromTarget | Out-Null
  $svc = Join-Path $Target 'NekoDropService.exe'
  if (Test-Path $svc) { & $svc --give-back }
  else {
    # A failed update can leave the folder without the service: restore.ps1
    # gives the card back on its own, from the same folder or this script's.
    $restore = @((Join-Path $Target 'restore.ps1'), (Join-Path $PSScriptRoot 'restore.ps1')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($restore) { & $restore } else { throw "neither NekoDropService.exe nor restore.ps1 is in $Target" }
  }
}

Try-Step 'Service' {
  if (Get-Service $Service -ErrorAction SilentlyContinue) {
    sc.exe delete $Service | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc.exe delete exited $LASTEXITCODE" }
  }
}

Try-Step 'Driver package and certificate' {
  $store = [xml](pnputil /enum-drivers /format xml | Out-String)
  # The PCIe register proxy and the USB dongle's WinUSB package. Deleting the
  # WinUSB package leaves the dongle on winusb.sys until it is unplugged or the
  # vendor's driver is reinstalled (restore.ps1 does that before this runs).
  $store.PnpUtil.Driver | Where-Object {
      $_.ProviderName -eq 'winairdrop project' -and
      ($_.OriginalName -eq 'winawdl_regproxy.inf' -or $_.OriginalName -eq 'nekodrop_winusb.inf')
    } |
    ForEach-Object {
      pnputil /delete-driver $_.DriverName /uninstall /force | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "pnputil /delete-driver $($_.DriverName) exited $LASTEXITCODE" }
    }
  # A USB dongle released from the deleted package needs a re-detect before
  # Windows binds the vendor's driver again (a PCIe card does it by itself).
  pnputil /scan-devices | Out-Null
  foreach ($s in 'Root', 'TrustedPublisher') {
    Get-ChildItem "Cert:\LocalMachine\$s" | Where-Object { $_.Subject -eq $CertSubject } | Remove-Item -ErrorAction Stop
  }
}

Try-Step 'Firewall' {
  Get-NetFirewallRule -Group 'nekodrop AirDrop' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
}

# Only the adapter setup-tap.ps1 made and named "nekodrop"; the TAP-Windows
# driver stays, other programs (VPNs) may use it (#22).
Try-Step 'TAP adapter' {
  foreach ($a in @(Get-NetAdapter -Name 'nekodrop' -IncludeHidden -ErrorAction SilentlyContinue |
                   Where-Object { $_.InterfaceDescription -like 'TAP-Windows Adapter V9*' })) {
    if ($a.PnPDeviceID) {
      pnputil /remove-device $a.PnPDeviceID | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "pnputil /remove-device exited $LASTEXITCODE" }
    }
  }
}

Try-Step 'Files' {
  Get-AppxPackage -AllUsers -Name nekodrop.shell -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
  $errors = @()
  # Inno Setup already ran nekodrop.exe --unregister as the original user;
  # doing it again from an elevated process would touch the wrong HKCU.
  if (-not $Inno) {
    try { Invoke-ClientUnregister }
    catch { $errors += "nekodrop.exe --unregister - $($_.Exception.Message)" }
  }
  foreach ($dir in @("$env:LOCALAPPDATA\nekodrop", "$env:ProgramData\nekodrop")) {
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    try { Remove-NekodropPath -Path $dir }
    catch { $errors += "$dir - $($_.Exception.Message)" }
  }
  if (Test-Path -LiteralPath $Target) {
    if (-not (Test-NekodropInstall $Target)) {
      $errors += "refusing to remove unexpected target: $Target"
    } else {
      try {
        if ($Inno) { Remove-NekodropPath -Path $Target -KeepUninstaller }
        else { Remove-NekodropPath -Path $Target }
      } catch { $errors += "$Target - $($_.Exception.Message)" }
    }
  }
  # A direct uninstall.ps1 has no Setup to remove the shortcuts or the
  # Add/Remove Programs entry. Clear them only after the folder is really gone,
  # so a failed file removal leaves a retryable registration behind.
  if (-not $Inno -and -not (Test-Path -LiteralPath $Target)) {
    Remove-NekodropShortcuts
    Remove-NekodropRegistration
  }
  if ($errors) { throw ($errors -join '; ') }
}

if ($failures) { "nekodrop is removed, with $failures step(s) failed: see $Log"; exit 1 }
'nekodrop is removed.'
exit 0
