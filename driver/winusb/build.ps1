# Stages the RTL8821CU USB dongle's WinUSB package into build\winusb: copies the
# INF, catalogues it with Inf2Cat and reports the files. Signing and installation
# are separate, deliberate steps (installer\install.ps1, or scripts\usb-card.ps1).
# Needs administrator rights: Inf2Cat's signability test fails with a
# NullReferenceException ("Signability test failed") in a medium-integrity
# process on Windows 11 26H1.
#Requires -RunAsAdministrator
#
# Two things this deliberately does NOT do:
#  - copy winusb.inf beside our INF: Include=winusb.inf is resolved from
#    %SystemRoot%\inf at install time, and a copy here makes Inf2Cat validate
#    that file as part of the package (winusb.sys missing, no AMD64
#    CatalogFile), which fails.
#  - run stampinf: it cannot open an INF under a directory named "driver" (it
#    answers "Could not open INF file ... Error writing to inf!", exit 1359),
#    which is where this source lives. The INF carries its own DriverVer, and a
#    deliberately older date keeps the package ranked below the vendor's driver.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\..\scripts\toolchain.ps1"

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tools = Initialize-Toolchain
$out = Join-Path $repo 'build\winusb'
New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item "$PSScriptRoot\nekodrop_winusb.inf" $out -Force
Remove-Item (Join-Path $out 'nekodrop_winusb.cat') -ErrorAction SilentlyContinue

& $tools.Inf2Cat "/driver:$out" /os:10_X64 /uselocaltime
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed ($LASTEXITCODE)" }

Get-ChildItem $out -Include *.inf, *.cat -Recurse | Select-Object Name, Length
