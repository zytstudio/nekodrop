# Builds the Realtek RTL8852CE user-mode radio daemon (winawdl_radio.exe,
# backed by raph559/devourer) into build\rtlradio and runs its offline unit
# tests. Links statically against MSVC runtime (/MT) and vcpkg x64-windows-static
# so the target PC needs neither vcruntime140.dll nor libusb-1.0.dll.
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

# nekodrop's change to the radio: it reports the phone's 5 GHz AWDL channel (#32).
& python -I "$PSScriptRoot\patch-radio-rtl.py" $winawdl
if ($LASTEXITCODE -ne 0) { throw 'RTL radio patch failed' }

$vcpkgCandidates = New-Object System.Collections.Generic.List[string]
foreach ($c in $env:VCPKG_ROOT, $env:VCPKG_INSTALLATION_ROOT, 'C:\vcpkg') {
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

$build = Join-Path $repo 'build\rtlradio'
& $tools.CMake -S $radioSrc -B $build -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$($tools.Ninja)" `
  "-DCMAKE_C_COMPILER=$($tools.Cl)" `
  "-DCMAKE_CXX_COMPILER=$($tools.Cl)" `
  -DCMAKE_BUILD_TYPE=Release `
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkgRoot\scripts\buildsystems\vcpkg.cmake" `
  "-DVCPKG_MANIFEST_DIR=$winawdl\deps" `
  '-DCMAKE_CXX_FLAGS=/EHsc /utf-8' `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed ($LASTEXITCODE)" }

& $tools.CMake --build $build --target winawdl_radio block_ack_test reorder_buffer_test outgoing_session_test dma_address_test
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }

foreach ($test in 'block_ack_test.exe', 'reorder_buffer_test.exe', 'outgoing_session_test.exe', 'dma_address_test.exe') {
  & (Join-Path $build $test)
  if ($LASTEXITCODE -ne 0) { throw "$test failed ($LASTEXITCODE)" }
}

$exe = Join-Path $build 'winawdl_radio.exe'
if (-not (Test-Path $exe)) { throw "expected binary missing: $exe" }
Get-ChildItem $build -Filter *.exe | Select-Object Name, Length
