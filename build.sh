#!/bin/bash
# Build script for Sony Xperia XZ2 (akari) - SDM845 Kernel
# Author: RyuDev
# Date: December 23, 2025

set -e

# Load Telegram config if exists
if [ -f "telegram.conf" ]; then
    source telegram.conf
fi

# ===========================
# Configuration Variables
# ===========================

# Device Configuration
DEVICE="akari"
DEVICE_CONFIG="arch/arm64/configs/vendor/sony/akari.config"
BASE_DEFCONFIG="vendor/sdm845-perf_defconfig"

# Architecture
ARCH=arm64
SUBARCH=arm64

# Output Directory
OUT_DIR="out"
KERNEL_IMG="${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"

# Custom Clang Path
CLANG_PATH="/home/romiyus/bringup/cus-clang/bin"

# GCC Cross Compiler (fallback or for some tools)
GCC_PATH="${HOME}/toolchains/aarch64-linux-android-4.9/bin"
GCC_PREFIX="aarch64-linux-android-"

# Alternative: AOSP GCC

# Build Threads
THREADS=$(nproc --all)

# Kernel Version
KERNEL_VERSION="4.19"
KERNEL_NAME="Orion-Akari"

# AnyKernel3 Configuration
ANYKERNEL_DIR="../AnyKernel3"
ANYKERNEL_REPO="https://github.com/romiyusnandar/Anykernel3.git"
ANYKERNEL_BRANCH="akari"

# Telegram Bot Configuration
# Set your bot token and chat ID here or via environment variables
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
ENABLE_TELEGRAM="${ENABLE_TELEGRAM:-false}"

# Final Zip
ZIP_DIR="$PWD/zip"
FINAL_ZIP=""

# ===========================
# Color Output
# ===========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===========================
# Functions
# ===========================

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    telegram_send "❌ *Build Error*" "$1"
    exit 1
}

# ===========================
# Telegram Functions
# ===========================

telegram_send() {
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local title="$1"
        local message="$2"
        local full_message="${title}%0A%0A${message}"

        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d text="${full_message}" \
            -d parse_mode="Markdown" \
            -d disable_web_page_preview=true > /dev/null 2>&1
    fi
}

telegram_upload() {
    if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local file="$1"
        local caption="$2"

        print_info "Uploading to Telegram..."

        curl -F chat_id="${TELEGRAM_CHAT_ID}" \
             -F document=@"${file}" \
             -F caption="${caption}" \
             -F parse_mode="Markdown" \
             "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"

        if [ $? -eq 0 ]; then
            print_success "Uploaded to Telegram"
        else
            print_warning "Failed to upload to Telegram"
        fi
    fi
}

# ===========================
# AnyKernel Functions
# ===========================

setup_anykernel() {
    print_info "Setting up AnyKernel3..."

    if [ ! -d "$ANYKERNEL_DIR" ]; then
        print_info "Cloning AnyKernel3 from $ANYKERNEL_REPO"
        git clone -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" "$ANYKERNEL_DIR"

        if [ $? -ne 0 ]; then
            print_error "Failed to clone AnyKernel3"
        fi
    else
        print_info "AnyKernel3 directory exists, updating..."
        cd "$ANYKERNEL_DIR"
        git fetch origin
        git checkout "$ANYKERNEL_BRANCH"
        git pull origin "$ANYKERNEL_BRANCH"
        cd - > /dev/null
    fi

    print_success "AnyKernel3 ready"
}

make_flashable_zip() {
    print_info "Creating flashable zip..."

    # Determine which image to use
    local IMAGE_SOURCE=""
    if [ -f "$KERNEL_IMG" ]; then
        IMAGE_SOURCE="$KERNEL_IMG"
    elif [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
        IMAGE_SOURCE="${OUT_DIR}/arch/arm64/boot/Image.gz"
    elif [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        IMAGE_SOURCE="${OUT_DIR}/arch/arm64/boot/Image"
    else
        print_error "No kernel image found to pack!"
    fi

    print_info "Using kernel image: $IMAGE_SOURCE"

    # Setup AnyKernel3
    setup_anykernel

    # Clean AnyKernel directory
    rm -f "$ANYKERNEL_DIR"/*.zip
    rm -f "$ANYKERNEL_DIR"/Image*
    rm -f "$ANYKERNEL_DIR"/*.img

    # Copy kernel image
    cp "$IMAGE_SOURCE" "$ANYKERNEL_DIR/"

    # Copy DTB if exists
    if [ -f "${OUT_DIR}/arch/arm64/boot/dtb.img" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/dtb.img" "$ANYKERNEL_DIR/"
        print_info "DTB image copied"
    fi

    # Copy modules if exists
    if [ -d "${OUT_DIR}/modules" ]; then
        cp -r "${OUT_DIR}/modules" "$ANYKERNEL_DIR/"
        print_info "Kernel modules copied"
    fi

    # Create zip filename with date and time
    local DATE=$(date +%Y%m%d)
    local TIME=$(date +%H%M)
    local SHORT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE}-${TIME}-${SHORT_COMMIT}.zip"

    # Create zip directory
    mkdir -p "$ZIP_DIR"
    FINAL_ZIP="${ZIP_DIR}/${ZIP_NAME}"

    # Create zip
    cd "$ANYKERNEL_DIR"
    print_info "Packaging: $ZIP_NAME"

    zip -r9 "$FINAL_ZIP" * -x .git README.md .gitignore *.zip

    cd - > /dev/null

    if [ -f "$FINAL_ZIP" ]; then
        local ZIP_SIZE=$(du -h "$FINAL_ZIP" | cut -f1)
        print_success "Flashable zip created: $FINAL_ZIP ($ZIP_SIZE)"
        return 0
    else
        print_error "Failed to create zip"
        return 1
    fi
}

# ===========================
# Build Info
# ===========================

get_build_info() {
    local CLANG_VERSION=$("$CLANG_PATH/clang" --version | head -n 1 | sed 's/clang version //g')
    local KERNEL_VER=$(make kernelversion 2>/dev/null || echo "$KERNEL_VERSION")
    local BUILD_DATE=$(date '+%Y-%m-%d %H:%M:%S')
    local BUILD_HOST=$(hostname)
    local BUILD_USER=$(whoami)
    local COMMIT=$(git log --pretty=format:"%h - %s" -1 2>/dev/null || echo "No git info")

    cat << EOF
*🔨 Build Started*

📱 *Device:* \`$DEVICE\` (Xperia XZ2)
🐧 *Kernel:* \`$KERNEL_NAME v$KERNEL_VER\`
📅 *Date:* \`$BUILD_DATE\`
👤 *Builder:* \`$BUILD_USER@$BUILD_HOST\`
🔧 *Compiler:* \`${CLANG_VERSION}\`
📝 *Commit:* \`${COMMIT}\`
⚙️ *Threads:* \`$THREADS\`
EOF
}

check_dependencies() {
    print_info "Checking dependencies..."

    # Check if zip command exists
    if ! command -v zip &> /dev/null; then
        print_warning "zip not found, installing..."
        telegram_send "⚠️ *Dependency Check*" "Installing zip utility..."
    fi

    # Check if clang exists
    if [ -d "$CLANG_PATH" ]; then
        print_success "Clang found at: $CLANG_PATH"
    else
        print_error "Clang not found at: $CLANG_PATH. Please edit CLANG_PATH in this script or install clang toolchain"
    fi

    # Check if make exists
    if ! command -v make &> /dev/null; then
        print_error "make not found. Please install build-essential"
    fi

    # Check if device config exists
    if [ ! -f "$DEVICE_CONFIG" ]; then
        print_error "Device config not found: $DEVICE_CONFIG"
    fi

    # Check if curl exists for Telegram
    if [ "$ENABLE_TELEGRAM" = "true" ] && ! command -v curl &> /dev/null; then
        print_warning "curl not found, Telegram notifications disabled"
        ENABLE_TELEGRAM="false"
    fi

    print_success "All dependencies checked"
}

clean_build() {
    print_info "Cleaning build directory..."
    rm -rf "$OUT_DIR"
    print_success "Clean completed"
}

make_defconfig() {
    print_info "Generating base defconfig: $BASE_DEFCONFIG"

    PATH="$CLANG_PATH:$GCC_PATH:$PATH" \
    make O="$OUT_DIR" \
        ARCH=$ARCH \
        SUBARCH=$SUBARCH \
        "$BASE_DEFCONFIG"

    print_success "Base defconfig created"
}

merge_device_config() {
    print_info "Merging device config for: $DEVICE"

    ./scripts/kconfig/merge_config.sh -m -O "$OUT_DIR" \
        "$OUT_DIR/.config" \
        "$DEVICE_CONFIG"

    print_success "Device config merged"
}

build_kernel() {
    print_info "Building kernel for $DEVICE..."
    print_info "Using $THREADS threads"

    telegram_send "" "$(get_build_info)"

    START_TIME=$(date +%s)

    PATH="$CLANG_PATH:$GCC_PATH:$PATH" \
    make -j${THREADS} O="$OUT_DIR" \
        ARCH=$ARCH \
        SUBARCH=$SUBARCH \
        CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=$GCC_PREFIX \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        LLVM=1 \
        LLVM_IAS=1

    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    MINUTES=$((ELAPSED / 60))
    SECONDS=$((ELAPSED % 60))
    BUILD_TIME="${MINUTES}m ${SECONDS}s"

    print_success "Kernel built in $BUILD_TIME"
    telegram_send "✅ *Build Completed*" "⏱ *Build Time:* \`$BUILD_TIME\`"
}

check_output() {
    print_info "Checking output files..."

    if [ -f "$KERNEL_IMG" ]; then
        SIZE=$(du -h "$KERNEL_IMG" | cut -f1)
        print_success "Kernel image found: $KERNEL_IMG ($SIZE)"
    else
        # Try alternative image locations
        if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
            print_success "Kernel image found: ${OUT_DIR}/arch/arm64/boot/Image.gz"
        elif [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
            print_success "Kernel image found: ${OUT_DIR}/arch/arm64/boot/Image"
        else
            print_error "Kernel image not found!"
        fi
    fi

    # Check for DTB
    if [ -f "${OUT_DIR}/arch/arm64/boot/dtb.img" ]; then
        print_success "DTB image found: ${OUT_DIR}/arch/arm64/boot/dtb.img"
    fi

    # List all images
    echo ""
    print_info "All generated images:"
    find "$OUT_DIR/arch/arm64/boot" -type f -name "Image*" -o -name "*.img" 2>/dev/null | while read file; do
        SIZE=$(du -h "$file" | cut -f1)
        echo "  - $file ($SIZE)"
    done
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  clean       Clean build directory"
    echo "  config      Generate defconfig only"
    echo "  build       Build kernel (default)"
    echo "  rebuild     Clean and build"
    echo "  zip         Build kernel and create flashable zip"
    echo "  repack      Only create zip from existing build"
    echo "  help        Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CLANG_PATH          Path to clang toolchain (default: $CLANG_PATH)"
    echo "  GCC_PATH            Path to GCC toolchain (default: $GCC_PATH)"
    echo "  TELEGRAM_BOT_TOKEN  Telegram bot token for notifications"
    echo "  TELEGRAM_CHAT_ID    Telegram chat ID for notifications"
    echo "  ENABLE_TELEGRAM     Enable Telegram notifications (true/false)"
    echo ""
    echo "Example:"
    echo "  $0 build"
    echo "  $0 zip"
    echo "  ENABLE_TELEGRAM=true TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=yyy $0 zip"
    echo "  CLANG_PATH=~/my-clang/bin $0 rebuild"
}

# ===========================
# Main Script
# ===========================

print_info "========================================"
print_info "  Sony Xperia XZ2 (akari) Kernel Build"
print_info "========================================"
echo ""

# Parse arguments
case "$1" in
    clean)
        clean_build
        telegram_send "🧹 *Clean Completed*" "Build directory has been cleaned"
        exit 0
        ;;
    config)
        check_dependencies
        make_defconfig
        merge_device_config
        print_success "Configuration completed"
        telegram_send "⚙️ *Configuration Completed*" "📱 *Device:* \`$DEVICE\`%0A🔧 *Config:* \`$BASE_DEFCONFIG + $DEVICE_CONFIG\`"
        exit 0
        ;;
    rebuild)
        check_dependencies
        clean_build
        make_defconfig
        merge_device_config
        build_kernel
        check_output
        make_flashable_zip

        # Upload to Telegram
        if [ -f "$FINAL_ZIP" ]; then
            ZIP_SIZE=$(du -h "$FINAL_ZIP" | cut -f1)
            BUILD_DATE=$(date '+%d %B %Y')
            telegram_upload "$FINAL_ZIP" "📦 *Flashable Kernel Zip Ready!"
        fi
        ;;
    zip)
        check_dependencies

        # Check if config exists
        if [ ! -f "$OUT_DIR/.config" ]; then
            print_info "No existing config found, generating new one"
            make_defconfig
            merge_device_config
        else
            print_info "Using existing config from $OUT_DIR/.config"
        fi

        build_kernel
        check_output
        make_flashable_zip

        # Upload to Telegram
        if [ -f "$FINAL_ZIP" ]; then
            ZIP_SIZE=$(du -h "$FINAL_ZIP" | cut -f1)
            BUILD_DATE=$(date '+%d %B %Y')
            telegram_upload "$FINAL_ZIP" "📦 *Flashable Kernel Zip*%0A%0A📱 *Device:* \`$DEVICE\`%0A🐧 *Kernel:* \`$KERNEL_NAME v$KERNEL_VERSION\`%0A📅 *Date:* \`$BUILD_DATE\`%0A💾 *Size:* \`$ZIP_SIZE\`%0A⏱ *Build Time:* \`$BUILD_TIME\`"
        fi
        ;;
    repack)
        check_output
        make_flashable_zip

        # Upload to Telegram
        if [ -f "$FINAL_ZIP" ]; then
            ZIP_SIZE=$(du -h "$FINAL_ZIP" | cut -f1)
            BUILD_DATE=$(date '+%d %B %Y')
            telegram_upload "$FINAL_ZIP" "📦 *Flashable Kernel Zip*%0A%0A📱 *Device:* \`$DEVICE\`%0A🐧 *Kernel:* \`$KERNEL_NAME v$KERNEL_VERSION\`%0A📅 *Date:* \`$BUILD_DATE\`%0A💾 *Size:* \`$ZIP_SIZE\`%0A♻️ *Status:* \`Repacked from existing build\`"
        fi
        ;;
    help|--help|-h)
        show_usage
        exit 0
        ;;
    build|"")
        check_dependencies

        # Check if config exists
        if [ ! -f "$OUT_DIR/.config" ]; then
            print_info "No existing config found, generating new one"
            make_defconfig
            merge_device_config
        else
            print_info "Using existing config from $OUT_DIR/.config"
        fi

        build_kernel
        check_output
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac

echo ""
print_success "All done!"

if [ -f "$FINAL_ZIP" ]; then
    print_info "Flashable zip: $FINAL_ZIP"
elif [ -f "$KERNEL_IMG" ]; then
    print_info "Kernel image: $KERNEL_IMG"
fi
echo ""
