# Builds the Realtek RTL8821CU USB radio daemon (nekodrop-radio-usb.exe) into
# build\usbradio: winawdl's radio (the AWDL session the RTL8852CE radio uses)
# over devourer's libusb transport, with only the Jaguar2 8821C backend.
# Links statically against the MSVC runtime (/MT) and vcpkg
# x64-windows-static, so the target PC needs neither vcruntime140.dll nor
# libusb-1.0.dll.
#
# The offline unit tests (block_ack_test, reorder_buffer_test, ...) build in
# build-radio-rtl.ps1's tree: the daemon is the same source file and the same
# headers, only the transport differs.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain.ps1"

$repo = Split-Path $PSScriptRoot -Parent
$tools = Initialize-Toolchain
$winawdl = Join-Path $repo 'third_party\winawdl'
$radioSrc = Join-Path $winawdl 'radio'
$devourerSrc = Join-Path $winawdl 'upstream\devourer'

if (-not (Test-Path (Join-Path $radioSrc 'CMakeLists.txt'))) {
  throw "winawdl radio sources missing at $radioSrc`: run scripts\fetch-deps.ps1 first."
}
if (-not (Test-Path (Join-Path $devourerSrc 'CMakeLists.txt'))) {
  throw "devourer sources missing at $devourerSrc`: run scripts\fetch-deps.ps1 first."
}

# nekodrop's changes to winawdl's radio, both idempotent and both applied to the
# one source file the two Realtek daemons share: the phone's 5 GHz AWDL channel
# report (#32, as the RTL8852CE radio has), then the USB transport (compiled
# only into this daemon, via -DNEKODROP_USB).
& python -I "$PSScriptRoot\patch-radio-rtl.py" $winawdl
if ($LASTEXITCODE -ne 0) { throw 'RTL radio patch failed' }
& python -I "$PSScriptRoot\patch-radio-usb.py" $winawdl
if ($LASTEXITCODE -ne 0) { throw 'USB radio patch failed' }

$vcpkgCandidates = New-Object System.Collections.Generic.List[string]
foreach ($c in $env:VCPKG_ROOT, $env:VCPKG_INSTALLATION_ROOT, 'C:\vcpkg', 'D:\vcpkg') {
  if ($c) { $vcpkgCandidates.Add($c) }
}
if ($tools.VsRoot) {
  $vcpkgCandidates.Add((Join-Path $tools.VsRoot 'VC\vcpkg'))
}
foreach ($pf in $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
  if (-not $pf) { continue }
  foreach ($edition in 'Enterprise', 'Professional', 'Community', 'BuildTools') {
    $vcpkgCandidates.Add((Join-Path $pf "Microsoft Visual Studio\2022\$edition\VC\vcpkg"))
  }
}

$vcpkgRoot = $null
foreach ($c in $vcpkgCandidates) {
  if ((Test-Path (Join-Path $c 'vcpkg.exe')) -and (Test-Path (Join-Path $c 'scripts\buildsystems\vcpkg.cmake'))) {
    $vcpkgRoot = $c
    break
  }
}
if (-not $vcpkgRoot) {
  throw "vcpkg not found (need vcpkg.exe and scripts\buildsystems\vcpkg.cmake). Checked: $($vcpkgCandidates -join ', ')"
}
$env:VCPKG_ROOT = $vcpkgRoot

# devourer finds libusb through pkg-config (find_package(PkgConfig REQUIRED) +
# pkg_check_modules(libusb-1.0)), so the static libusb and vcpkg's pkgconf must
# be installed before configuring. Installed directly rather than through
# winawdl's vcpkg manifest: that manifest pins a pkgconf version a local vcpkg
# may not have in its version database, and this build needs exactly one
# library.
function Get-PkgConf {
  Get-ChildItem (Join-Path $vcpkgRoot 'installed') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'tools\pkgconf\pkgconf.exe' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
}
$pkgConfigPath = Join-Path $vcpkgRoot 'installed\x64-windows-static\lib\pkgconfig'
if (-not (Test-Path (Join-Path $pkgConfigPath 'libusb-1.0.pc'))) {
  'installing libusb (x64-windows-static)'
  & (Join-Path $vcpkgRoot 'vcpkg.exe') install libusb:x64-windows-static
  if ($LASTEXITCODE -ne 0) { throw "vcpkg install libusb failed ($LASTEXITCODE)" }
}
$pkgconf = Get-PkgConf
if (-not $pkgconf) {
  'installing pkgconf'
  & (Join-Path $vcpkgRoot 'vcpkg.exe') install pkgconf
  if ($LASTEXITCODE -ne 0) { throw "vcpkg install pkgconf failed ($LASTEXITCODE)" }
  $pkgconf = Get-PkgConf
}

$build = Join-Path $repo 'build\usbradio'
$configure = @(
  '-S', (Join-Path $repo 'usbradio'),
  '-B', $build,
  '-G', 'Ninja',
  "-DCMAKE_MAKE_PROGRAM=$($tools.Ninja)",
  "-DCMAKE_C_COMPILER=$($tools.Cl)",
  "-DCMAKE_CXX_COMPILER=$($tools.Cl)",
  '-DCMAKE_BUILD_TYPE=Release',
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot\scripts\buildsystems\vcpkg.cmake",
  '-DVCPKG_TARGET_TRIPLET=x64-windows-static',
  '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded'
)
if ($pkgconf) { $configure += "-DPKG_CONFIG_EXECUTABLE=$pkgconf" }
if (Test-Path $pkgConfigPath) { $env:PKG_CONFIG_PATH = $pkgConfigPath }
& $tools.CMake @configure
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed ($LASTEXITCODE)" }

& $tools.CMake --build $build --target nekodrop-radio-usb
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

$exe = Join-Path $build 'nekodrop-radio-usb.exe'
if (-not (Test-Path $exe)) { throw "expected binary missing: $exe" }
Get-Item $exe | Select-Object Name, Length
