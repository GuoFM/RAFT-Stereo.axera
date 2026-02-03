#!/bin/bash

# RAFT-Stereo Build Script for AX637
# The AX637 BSP SDK must be obtained from FAE. Please set the BSP_MSP_DIR environment variable or use the --bsp option to specify the path.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CHIP_TYPE=ax637

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build_ax637"
THIRDPARTY_DIR="${SCRIPT_DIR}/3rdparty"
TOOLCHAIN_DIR="${BUILD_DIR}/toolchain"

OPENCV_URL="https://github.com/AXERA-TECH/ax-samples/releases/download/v0.1/opencv-aarch64-linux-gnu-gcc-7.5.0.zip"
TOOLCHAIN_URL1="https://developer.arm.com/-/media/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
TOOLCHAIN_URL2="https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu-a/9.2-2019.12/binrel/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"

BSP_MSP_DIR_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --bsp)
            BSP_MSP_DIR_ARG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--bsp <BSP_MSP_DIR>]"
            echo ""
            echo "Options:"
            echo "  --bsp <path>   Path to AX637 BSP msp/out directory"
            echo ""
            echo "Environment variables:"
            echo "  BSP_MSP_DIR    Alternative way to specify BSP path"
            echo ""
            echo "Example:"
            echo "  $0 --bsp /path/to/AX637_SDK/package/msp/out"
            echo "  BSP_MSP_DIR=/path/to/msp/out $0"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

if [ -n "$BSP_MSP_DIR_ARG" ]; then
    BSP_MSP_DIR="$BSP_MSP_DIR_ARG"
elif [ -z "$BSP_MSP_DIR" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}ERROR: AX637 BSP SDK path not specified${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "The AX637 BSP SDK must be obtained from FAE. Please specify the path using one of the following methods:"
    echo ""
    echo "Method 1: Use the --bsp option"
    echo "  $0 --bsp /path/to/AX637_SDK/package/msp/out"
    echo ""
    echo "Method 2: Set the environment variable"
    echo "  export BSP_MSP_DIR=/path/to/AX637_SDK/package/msp/out"
    echo "  $0"
    echo ""
    echo "The BSP directory should contain:"
    echo "  msp/out/"
    echo "  ├── include/"
    echo "  │   ├── ax_sys_api.h"
    echo "  │   ├── ax_engine_api.h"
    echo "  │   └── ..."
    echo "  └── lib/"
    echo "      ├── libax_engine.so"
    echo "      ├── libax_sys.so"
    echo "      └── ..."
    exit 1
fi

if [ ! -d "$BSP_MSP_DIR/include" ] || [ ! -d "$BSP_MSP_DIR/lib" ]; then
    echo -e "${RED}ERROR: Invalid BSP path: $BSP_MSP_DIR${NC}"
    echo "Expected directories not found: include/ and lib/"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}RAFT-Stereo AX637 Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "BSP_MSP_DIR: ${BSP_MSP_DIR}"

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo -e "${YELLOW}Warning: Not running on x86_64, assuming native compilation${NC}"
    CROSS_COMPILE=false
else
    CROSS_COMPILE=true
fi

download_file() {
    local url=$1
    local output=$2
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        echo "Downloading $(basename $output) (attempt $((retry + 1))/$max_retries)..."
        if wget --progress=bar:force:noscroll --show-progress -O "$output" "$url" 2>&1; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                echo -e "${GREEN}Downloaded: $(basename $output) ($(du -h "$output" | cut -f1))${NC}"
                return 0
            fi
        fi
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            echo -e "${YELLOW}Retry $retry/$max_retries...${NC}"
            sleep 2
            rm -f "$output" 2>/dev/null || true
        fi
    done
    
    echo -e "${RED}Failed to download: $url${NC}"
    return 1
}

echo -e "\n${GREEN}[1/4] Checking system dependencies...${NC}"
MISSING_DEPS=()

command -v cmake >/dev/null 2>&1 || MISSING_DEPS+=("cmake")
command -v wget >/dev/null 2>&1 || MISSING_DEPS+=("wget")
command -v unzip >/dev/null 2>&1 || MISSING_DEPS+=("unzip")
command -v tar >/dev/null 2>&1 || MISSING_DEPS+=("tar")
command -v make >/dev/null 2>&1 || MISSING_DEPS+=("build-essential")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    echo -e "${YELLOW}Please install them with: sudo apt-get install ${MISSING_DEPS[*]}${NC}"
    exit 1
fi
echo -e "${GREEN}All system dependencies found${NC}"

echo -e "\n${GREEN}[2/4] Setting up OpenCV library...${NC}"
mkdir -p "${THIRDPARTY_DIR}"
OPENCV_ZIP="${THIRDPARTY_DIR}/opencv-aarch64-linux-gnu-gcc-7.5.0.zip"
OPENCV_EXTRACT_DIR="${THIRDPARTY_DIR}/opencv-aarch64-linux"

if [ ! -d "${OPENCV_EXTRACT_DIR}" ]; then
    if [ ! -f "${OPENCV_ZIP}" ]; then
        download_file "${OPENCV_URL}" "${OPENCV_ZIP}"
    fi
    
    echo "Extracting OpenCV..."
    unzip -q -o "${OPENCV_ZIP}" -d "${THIRDPARTY_DIR}"
    echo -e "${GREEN}OpenCV setup complete${NC}"
else
    echo -e "${GREEN}OpenCV already exists${NC}"
fi

if [ -d "${OPENCV_EXTRACT_DIR}/lib/cmake/opencv4" ]; then
    export OpenCV_DIR="${OPENCV_EXTRACT_DIR}/lib/cmake/opencv4"
elif [ -d "${OPENCV_EXTRACT_DIR}/share/OpenCV" ]; then
    export OpenCV_DIR="${OPENCV_EXTRACT_DIR}/share/OpenCV"
else
    export OpenCV_DIR="${OPENCV_EXTRACT_DIR}"
fi

if [ "$CROSS_COMPILE" = true ]; then
    echo -e "\n${GREEN}[3/4] Setting up cross-compilation toolchain...${NC}"
    mkdir -p "${TOOLCHAIN_DIR}"
    TOOLCHAIN_TAR="${TOOLCHAIN_DIR}/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
    TOOLCHAIN_DIR_EXTRACTED="${TOOLCHAIN_DIR}/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu"
    
    if [ ! -d "${TOOLCHAIN_DIR_EXTRACTED}/bin" ]; then
        if [ ! -f "${TOOLCHAIN_TAR}" ]; then
            if ! download_file "${TOOLCHAIN_URL1}" "${TOOLCHAIN_TAR}"; then
                echo "Trying alternative URL..."
                download_file "${TOOLCHAIN_URL2}" "${TOOLCHAIN_TAR}" || {
                    echo -e "${RED}Failed to download toolchain${NC}"
                    exit 1
                }
            fi
        fi
        
        echo "Extracting toolchain..."
        tar -xf "${TOOLCHAIN_TAR}" -C "${TOOLCHAIN_DIR}"
        echo -e "${GREEN}Toolchain setup complete${NC}"
    else
        echo -e "${GREEN}Toolchain already exists${NC}"
    fi
    
    export PATH="${TOOLCHAIN_DIR_EXTRACTED}/bin:${PATH}"
    
    if ! aarch64-none-linux-gnu-gcc -v >/dev/null 2>&1; then
        echo -e "${RED}Toolchain verification failed${NC}"
        exit 1
    fi
    echo -e "${GREEN}Toolchain verified${NC}"
else
    echo -e "\n${GREEN}[3/4] Skipping cross-compilation toolchain (native build)${NC}"
fi

echo -e "\n${GREEN}[4/4] Building RAFT-Stereo...${NC}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DBSP_MSP_DIR="${BSP_MSP_DIR}"
    -DAXERA_TARGET_CHIP="${CHIP_TYPE}"
    -DOpenCV_DIR="${OpenCV_DIR}"
    -DCMAKE_INSTALL_PREFIX=./install
)

if [ "$CROSS_COMPILE" = true ]; then
    CMAKE_ARGS+=(
        -DCMAKE_TOOLCHAIN_FILE="${SCRIPT_DIR}/toolchains/aarch64-none-linux-gnu.toolchain.cmake"
    )
    echo "Configuring CMake for cross-compilation (AX637)..."
else
    echo "Configuring CMake for native build (AX637)..."
fi

cmake "${CMAKE_ARGS[@]}" "${SCRIPT_DIR}" || {
    echo -e "${RED}CMake configuration failed${NC}"
    exit 1
}

echo "Building..."
make -j$(nproc) || {
    echo -e "${RED}Build failed${NC}"
    exit 1
}

echo "Installing..."
make install || {
    echo -e "${YELLOW}Warning: Install failed, but build may have succeeded${NC}"
}

BINARY_PATH=""
if [ -f "./install/bin/raft_stereo_inference" ]; then
    BINARY_PATH="./install/bin/raft_stereo_inference"
    cp "${BINARY_PATH}" ./raft_stereo_inference 2>/dev/null || true
elif [ -f "./raft_stereo_inference" ]; then
    BINARY_PATH="./raft_stereo_inference"
fi

if [ -n "${BINARY_PATH}" ] && [ -f "${BINARY_PATH}" ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Build completed successfully for AX637!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Chip type: ${CHIP_TYPE}"
    echo -e "Binary location: ${BUILD_DIR}/${BINARY_PATH}"
    echo -e "File info:"
    file "${BUILD_DIR}/${BINARY_PATH}"
    ls -lh "${BUILD_DIR}/${BINARY_PATH}"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}Build completed but binary not found${NC}"
    exit 1
fi
