cmake_minimum_required(VERSION 3.21)
project(DanzigFormatWrappers LANGUAGES C CXX OBJC OBJCXX)
set(CMAKE_CXX_STANDARD 23)
set(CLAP_WRAPPER_CXX_STANDARD 23 CACHE STRING "C++ standard for wrapper and Apple AudioUnitSDK" FORCE)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (NOT APPLE)
    message(FATAL_ERROR "This wrapper project builds AUv2 on macOS. AAX Windows builds can use clap-wrapper directly.")
endif()

if (NOT DEFINED CLAP_WRAPPER_SOURCE OR NOT EXISTS "${CLAP_WRAPPER_SOURCE}/CMakeLists.txt")
    message(FATAL_ERROR "Set CLAP_WRAPPER_SOURCE to a checkout of free-audio/clap-wrapper")
endif()

if (NOT DEFINED DANZIG_CLAP_BUNDLE OR NOT EXISTS "${DANZIG_CLAP_BUNDLE}")
    message(FATAL_ERROR "Set DANZIG_CLAP_BUNDLE to the built DanzigGain.clap bundle (zig build clap)")
endif()

set(CLAP_WRAPPER_OUTPUT_NAME "DanzigGain" CACHE STRING "CLAP wrapper output" FORCE)
set(CLAP_WRAPPER_COPY_AFTER_BUILD OFF CACHE BOOL "Install wrappers automatically" FORCE)
add_subdirectory("${CLAP_WRAPPER_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}/clap-wrapper")

add_library(danzig_gain_auv2 MODULE)
target_add_auv2_wrapper(
    TARGET danzig_gain_auv2
    OUTPUT_NAME "DanzigGain"
    BUNDLE_IDENTIFIER "dev.superelectric.danzig.gain.auv2"
    BUNDLE_VERSION "0.1.0"
    PREFER_CMAKE_AUV2_CONFIGURATION TRUE
    MANUFACTURER_NAME "Superelectric"
    MANUFACTURER_CODE "SuEl"
    SUBTYPE_CODE "DzGn"
    INSTRUMENT_TYPE "aufx"
    MACOS_EMBEDDED_CLAP_LOCATION "${DANZIG_CLAP_BUNDLE}"
)

option(DANZIG_BUILD_AAX "Build the AAX wrapper with the licensed Avid SDK" OFF)
if (DANZIG_BUILD_AAX)
    if (NOT DEFINED AAX_SDK_ROOT OR NOT EXISTS "${AAX_SDK_ROOT}/Interfaces/AAX_Exports.cpp")
        message(FATAL_ERROR "Set AAX_SDK_ROOT to an installed Avid AAX SDK checkout")
    endif()
    add_library(danzig_gain_aax MODULE)
    target_add_aax_wrapper(
        TARGET danzig_gain_aax
        OUTPUT_NAME "DanzigGain"
        BUNDLE_IDENTIFIER "dev.superelectric.danzig.gain.aax"
        BUNDLE_VERSION "0.1.0"
        MACOS_EMBEDDED_CLAP_LOCATION "${DANZIG_CLAP_BUNDLE}"
    )
endif()
