# Copyright (c) 2026 Siyuan Wang.
# Licensed under the GNU General Public License v3. See LICENSE.

cmake_minimum_required(VERSION 3.24)
project(BitbotCopilot VERSION 0.2.0 LANGUAGES NONE)

if(NOT APPLE)
    message(FATAL_ERROR "This branch implements the macOS native client only (macOS 14+).")
endif()
find_program(SWIFT_EXECUTABLE swift REQUIRED)
add_custom_target(BitbotCopilot ALL
    COMMAND ${CMAKE_COMMAND} -E env
        "BITBOT_BUILD_ROOT=${CMAKE_BINARY_DIR}/swift"
        "BITBOT_OUTPUT_DIR=${CMAKE_BINARY_DIR}/bin"
        /bin/bash "${CMAKE_SOURCE_DIR}/macOS/build.sh"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    USES_TERMINAL
    COMMENT "Building the native SwiftUI macOS app"
)
