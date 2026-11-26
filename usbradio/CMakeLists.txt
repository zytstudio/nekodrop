# nekodrop's Realtek RTL8821CU radio: winawdl's radio daemon (radio/, the same
# AWDL session the RTL8852CE uses) over devourer's USB transport instead of the
# Windows register proxy. See docs/RTL8821CU.md.
#
# Only the Jaguar2 8821C backend is compiled in: the PCIe transport and every
# other chip stay out, so this binary carries nothing the dongle cannot use.
# scripts/build-radio-usb.ps1 patches radio/winawdl_radio.cpp first (it adds the
# libusb path under -DNEKODROP_USB; the RTL8852CE daemon is built separately and
# is unaffected).
cmake_minimum_required(VERSION 3.20)
project(usbradio CXX)

# devourer only picks the vcpkg toolchain when it is the top-level project.
if(WIN32 AND NOT "$ENV{VCPKG_ROOT}" STREQUAL "")
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
endif()

set(WINAWDL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/winawdl")
set(DEVOURER_SRC "${WINAWDL_ROOT}/upstream/devourer")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# The 8821C (RTL8811CU/RTL8821CU, 1T1R USB) only; everything else off, including
# the PCIe transport this daemon never opens.
foreach(chip JAGUAR1 8814 JAGUAR2_8822B JAGUAR2_8821C JAGUAR3_8822C
             JAGUAR3_8822E 8733B KESTREL_8852B KESTREL_8852C)
    set(DEVOURER_${chip} OFF CACHE BOOL "" FORCE)
endforeach()
set(DEVOURER_JAGUAR2_8821C ON CACHE BOOL "" FORCE)
set(DEVOURER_PCIE OFF CACHE BOOL "" FORCE)

add_subdirectory("${DEVOURER_SRC}" devourer EXCLUDE_FROM_ALL)

add_executable(nekodrop-radio-usb "${WINAWDL_ROOT}/radio/winawdl_radio.cpp")
target_compile_features(nekodrop-radio-usb PRIVATE cxx_std_20)
target_compile_definitions(nekodrop-radio-usb PRIVATE NEKODROP_USB _CRT_SECURE_NO_WARNINGS
    NOMINMAX WIN32_LEAN_AND_MEAN)
target_include_directories(nekodrop-radio-usb PRIVATE
    "${WINAWDL_ROOT}/radio"          # radio_link.h, pipe_server.h, block_ack.h, ...
    "${DEVOURER_SRC}/src"            # IRadio, WiFiDriver, UsbOpen, ...
    "${DEVOURER_SRC}/examples/common" # DeviceSession.h (the libusb teardown order)
    "${CMAKE_CURRENT_SOURCE_DIR}/src" # nekodrop_usb_session.h
)
if(MSVC)
    # /wd4005: pipe_server.h defines WIN32_LEAN_AND_MEAN and NOMINMAX itself, so
    # passing them on the command line (needed by block_ack.h's std::min) is a
    # redefinition warning here and an error under /WX.
    target_compile_options(nekodrop-radio-usb PRIVATE /W4 /WX /permissive- /utf-8 /wd4005)
endif()
# devourer links libusb (PkgConfig::libusb) PUBLIC, so the session's own libusb
# calls resolve through it.
target_link_libraries(nekodrop-radio-usb PRIVATE devourer)
