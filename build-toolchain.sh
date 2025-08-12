#! /bin/bash
# N64 MIPS GCC toolchain build/install script for Unix distributions
# originally based off libdragon's toolchain script,
# which was licensed under the Unlicense.
# (c) 2012-2023 DragonMinded and libDragon Contributors.

# Bash strict mode http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

# Check that U64_INST is defined
if [ -z "${U64_INST-}" ]; then
    echo "U64_INST environment variable is not defined."
    echo "Please define U64_INST and point it to the requested installation directory"
    exit 1
fi

# Path where the toolchain will be built.
BUILD_PATH="${BUILD_PATH:-toolchain}"
DOWNLOAD_PATH="${DOWNLOAD_PATH:-$BUILD_PATH}"

# Defines the build system variables to allow cross compilation.
U64_BUILD=${U64_BUILD:-""}
U64_HOST=${U64_HOST:-""}
U64_TARGET=${U64_TARGET:-mips64-elf}

# Set U64_INST before calling the script to change the default installation directory path
INSTALL_PATH="${U64_INST}"
# Set PATH for newlib to compile using GCC for MIPS N64 (pass 1)
export PATH="$PATH:$INSTALL_PATH/bin"

# Determine how many parallel Make jobs to run based on CPU count
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
JOBS="${JOBS:-1}" # If getconf returned nothing, default to 1

# GCC configure arguments to use system GMP/MPC/MFPF
GCC_CONFIGURE_ARGS=()

# Dependency source libs (Versions)
BINUTILS_V=2.45
GCC_V=15.2.0
NEWLIB_V=4.5.0.20241231
GMP_V=6.3.0
MPC_V=1.3.1
MPFR_V=4.2.2

# Create build and download directories
mkdir -p "$BUILD_PATH" "$DOWNLOAD_PATH"

# Resolve absolute paths for build and download directories
BUILD_PATH=$(cd "$BUILD_PATH" && pwd)
DOWNLOAD_PATH=$(cd "$DOWNLOAD_PATH" && pwd)

# Check if a command-line tool is available: status 0 means "yes"; status 1 means "no"
command_exists () {
    (command -v "$1" >/dev/null 2>&1)
    return $?
}

# Download the file URL using wget or curl (depending on which is installed)
download () {
    if   command_exists aria2c ; then (cd "$DOWNLOAD_PATH" && aria2c -c -s 16 -x 16 "$1")
    elif command_exists wget ; then (cd "$DOWNLOAD_PATH" && wget -c  "$1")
    elif command_exists curl ; then (cd "$DOWNLOAD_PATH" && curl -LO "$1")
    else
        echo "Install wget or curl to download toolchain sources" 1>&2
        return 1
    fi
}

# Configure GCC arguments for non-macOS platforms
GCC_CONFIGURE_ARGS+=("--with-system-zlib")

cp gas-vr4300.patch $BUILD_PATH
cp gcc-vr4300.patch $BUILD_PATH

# Dependency downloads and unpack
test -f "$DOWNLOAD_PATH/binutils-$BINUTILS_V.tar.gz" || download "https://ftpmirror.gnu.org/gnu/binutils/binutils-$BINUTILS_V.tar.gz"
test -d "$BUILD_PATH/binutils-$BINUTILS_V"           || tar -xzf "$DOWNLOAD_PATH/binutils-$BINUTILS_V.tar.gz" -C "$BUILD_PATH"
pushd "$BUILD_PATH/binutils-$BINUTILS_V" 
patch -p1 < $BUILD_PATH/gas-vr4300.patch
popd

test -f "$DOWNLOAD_PATH/gcc-$GCC_V.tar.gz"           || download "https://ftpmirror.gnu.org/gnu/gcc/gcc-$GCC_V/gcc-$GCC_V.tar.gz"
test -d "$BUILD_PATH/gcc-$GCC_V"                     || tar -xzf "$DOWNLOAD_PATH/gcc-$GCC_V.tar.gz" -C "$BUILD_PATH"
pushd "$BUILD_PATH/gcc-$GCC_V"
patch -p1 < $BUILD_PATH/gcc-vr4300.patch
popd

test -f "$DOWNLOAD_PATH/newlib-$NEWLIB_V.tar.gz"     || download "https://sourceware.org/pub/newlib/newlib-$NEWLIB_V.tar.gz"
test -d "$BUILD_PATH/newlib-$NEWLIB_V"               || tar -xzf "$DOWNLOAD_PATH/newlib-$NEWLIB_V.tar.gz" -C "$BUILD_PATH"

if [ "$GMP_V" != "" ]; then
    test -f "$DOWNLOAD_PATH/gmp-$GMP_V.tar.bz2"      || download "https://ftpmirror.gnu.org/gnu/gmp/gmp-$GMP_V.tar.bz2"
    test -d "$BUILD_PATH/gmp-$GMP_V"                 || tar -xf "$DOWNLOAD_PATH/gmp-$GMP_V.tar.bz2" -C "$BUILD_PATH" # note: no .gz download file currently available
    pushd "$BUILD_PATH/gcc-$GCC_V"
    ln -sf ../"gmp-$GMP_V" "gmp"
    popd
fi

if [ "$MPC_V" != "" ]; then
    test -f "$DOWNLOAD_PATH/mpc-$MPC_V.tar.gz"       || download "https://ftpmirror.gnu.org/gnu/mpc/mpc-$MPC_V.tar.gz"
    test -d "$BUILD_PATH/mpc-$MPC_V"                 || tar -xzf "$DOWNLOAD_PATH/mpc-$MPC_V.tar.gz" -C "$BUILD_PATH"
    pushd "$BUILD_PATH/gcc-$GCC_V"
    ln -sf ../"mpc-$MPC_V" "mpc"
    popd
fi

if [ "$MPFR_V" != "" ]; then
    test -f "$DOWNLOAD_PATH/mpfr-$MPFR_V.tar.gz"     || download "https://ftpmirror.gnu.org/gnu/mpfr/mpfr-$MPFR_V.tar.gz"
    test -d "$BUILD_PATH/mpfr-$MPFR_V"               || tar -xzf "$DOWNLOAD_PATH/mpfr-$MPFR_V.tar.gz" -C "$BUILD_PATH"
    pushd "$BUILD_PATH/gcc-$GCC_V"
    ln -sf ../"mpfr-$MPFR_V" "mpfr"
    popd
fi

cd "$BUILD_PATH"

# Deduce build triplet using config.guess (if not specified)
# This is by the definition the current system so it should be OK.
if [ "$U64_BUILD" == "" ]; then
    U64_BUILD=$("binutils-$BINUTILS_V"/config.guess)
fi

if [ "$U64_HOST" == "" ]; then
    U64_HOST="$U64_BUILD"
fi


# Standard cross.
CROSS_PREFIX=$INSTALL_PATH

# Compile BUILD->TARGET binutils
mkdir -p binutils_compile_target
pushd binutils_compile_target
../"binutils-$BINUTILS_V"/configure \
    --disable-debug \
    --prefix="$CROSS_PREFIX" \
    --target="$U64_TARGET" \
    --with-cpu=mips64vr4300 \
    --program-prefix=mips-n64- \
    --disable-werror
make -j "$JOBS"
make install-strip || sudo make install-strip || su -c "make install-strip"
popd

# Compile GCC for MIPS N64.
# We need to build the C++ compiler to build the target libstd++ later.
mkdir -p gcc_compile_target
pushd gcc_compile_target
../"gcc-$GCC_V"/configure "${GCC_CONFIGURE_ARGS[@]}" \
    --prefix="$CROSS_PREFIX" \
    --target="$U64_TARGET" \
    --program-prefix=mips-n64- \
    --with-arch=vr4300 \
    --with-tune=vr4300 \
    --enable-languages=c,c++ \
    --without-headers \
    --disable-libssp \
    --disable-multilib \
    --disable-shared \
    --with-gcc \
    --with-newlib \
    --disable-win32-registry \
    --disable-nls \
    --disable-werror 
make all-gcc -j "$JOBS"
make install-gcc || sudo make install-gcc || su -c "make install-gcc"
make all-target-libgcc -j "$JOBS" CFLAGS_FOR_TARGET="-mabi=32 -ffreestanding -mfix4300 -G 0 -fno-stack-protector -mno-check-zero-division -fwrapv -Os"
make install-target-libgcc || sudo make install-target-libgcc || su -c "make install-target-libgcc"
popd

# Compile newlib for target.
mkdir -p newlib_compile_target
pushd newlib_compile_target
RANLIB_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-ranlib CC_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-gcc CXX_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-g++ AR_FOR_TARGET=${INSTALL_PATH}/bin/mips-n64-ar CFLAGS_FOR_TARGET="-mabi=32 -ffreestanding -mfix4300 -G 0 -fno-stack-protector -mno-check-zero-division -fno-PIC -fwrapv -Os -DHAVE_ASSERT_FUNC -fpermissive" CXXFLAGS_FOR_TARGET="-mabi=32 -ffreestanding -mfix4300 -G 0 -fno-stack-protector -mno-check-zero-division -fno-PIC -fwrapv -fno-rtti -Os -fno-exceptions -DHAVE_ASSERT_FUNC -fpermissive" ../"newlib-$NEWLIB_V"/configure \
    --prefix="$CROSS_PREFIX" \
    --target="$U64_TARGET" \
    --with-cpu=mips64vr4300 \
    --disable-libssp \
    --disable-werror \
    --enable-newlib-multithread \
    --enable-newlib-retargetable-locking
make -j "$JOBS"
make install || sudo env PATH="$PATH" make install || su -c "env PATH=\"$PATH\" make install"
popd

# For a standard cross-compiler, the only thing left is to finish compiling the target libraries
# like libstd++. We can continue on the previous GCC build target.
pushd gcc_compile_target
make all -j "$JOBS" CFLAGS_FOR_TARGET="-mabi=32 -mfix4300 -G 0 -fno-PIC -fwrapv -fno-stack-protector -mno-check-zero-division -Os" CXXFLAGS_FOR_TARGET="-mabi=32 -mfix4300 -G 0 -fno-stack-protector -mno-check-zero-division -fno-PIC -fno-rtti -Os -fno-exceptions"
make install-strip || sudo make install-strip || su -c "make install-strip" 
popd

# Final message
echo
echo "***********************************************"
echo "Toolchain correctly built and installed"
echo "Installation directory: \"${U64_INST}\""
echo "Build directory: \"${BUILD_PATH}\" (can be removed now)"
