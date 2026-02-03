cmake_minimum_required(VERSION 3.13)

# Target chip type (default to ax650)
if(NOT DEFINED AXERA_TARGET_CHIP)
    set(AXERA_TARGET_CHIP "ax650" CACHE STRING "AXERA target chip (ax650, ax630c)")
endif()

project(RAFT_Stereo CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

message(STATUS "Building RAFT-Stereo for chip: ${AXERA_TARGET_CHIP}")

# Set target chip define for conditional compilation
if(AXERA_TARGET_CHIP STREQUAL "ax630c" OR AXERA_TARGET_CHIP STREQUAL "ax620e")
    add_definitions(-DAXERA_TARGET_CHIP_AX620E)
    message(STATUS "Using AX620E/AX630C configuration")
elseif(AXERA_TARGET_CHIP STREQUAL "ax650")
    add_definitions(-DAXERA_TARGET_CHIP_AX650)
    message(STATUS "Using AX650 configuration")
endif()

# Set OpenCV directory (default to bundled prebuilt path, allow override)
if(NOT DEFINED OpenCV_DIR)
    if(DEFINED ENV{OpenCV_DIR})
        set(OpenCV_DIR "$ENV{OpenCV_DIR}" CACHE PATH "OpenCV directory")
    else()
        set(OpenCV_DIR "${CMAKE_SOURCE_DIR}/3rdparty/opencv-aarch64-linux/lib/cmake/opencv4" CACHE PATH "OpenCV directory")
    endif()
endif()

message(STATUS "OpenCV_DIR: ${OpenCV_DIR}")

# Find OpenCV
find_package(OpenCV REQUIRED)
message(STATUS "Found OpenCV: ${OpenCV_VERSION}")

find_package(Threads REQUIRED)
find_package(OpenMP)
if(OpenMP_CXX_FOUND)
    message(STATUS "Found OpenMP: ${OpenMP_CXX_VERSION}")
endif()

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${OpenCV_INCLUDE_DIRS}
)

set(SOURCES
    src/main.cpp
)

set(HEADERS
    include/common.hpp
    include/io.hpp
    include/timer.hpp
    include/file.hpp
    include/cmdline.hpp
)

add_executable(raft_stereo_inference ${SOURCES} ${HEADERS})

target_link_libraries(raft_stereo_inference
    ${OpenCV_LIBS}
    Threads::Threads
    ax_engine
    ax_interpreter
    ax_sys
)

# Link OpenMP if available
if(OpenMP_CXX_FOUND)
    target_link_libraries(raft_stereo_inference OpenMP::OpenMP_CXX)
endif()

if(DEFINED BSP_MSP_DIR)
    target_include_directories(raft_stereo_inference PRIVATE ${BSP_MSP_DIR}/include)
    target_link_directories(raft_stereo_inference PRIVATE ${BSP_MSP_DIR}/lib)
else()
    message(WARNING "BSP_MSP_DIR not set, using default path")
    target_include_directories(raft_stereo_inference PRIVATE /opt/axera/msp/out/include)
    target_link_directories(raft_stereo_inference PRIVATE /opt/axera/msp/out/lib)
endif()

target_compile_options(raft_stereo_inference PRIVATE -O3 -Wall)

install(TARGETS raft_stereo_inference DESTINATION bin)
