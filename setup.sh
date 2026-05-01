#!/bin/bash
set -e
ROOT_DIR="$(pwd)"

echo "Step 1: Initializing submodules..."
git submodule update --init --recursive

# Pythia 8 setup
# Priority: 1. Environment variable 2. ~/lib/pythia8 3. Project deps/
if [ -n "$PYTHIA8" ] && [ -d "$PYTHIA8/include/Pythia8" ]; then
    echo "Using Pythia 8 from environment variable: $PYTHIA8"
    PYTHIA_INSTALL_PATH="$PYTHIA8"
elif [ -d "$HOME/lib/pythia8/include/Pythia8" ]; then
    echo "Using Pythia 8 from default path: $HOME/lib/pythia8"
    PYTHIA_INSTALL_PATH="$HOME/lib/pythia8"
else
    echo "Pythia 8 not found in system paths. Checking deps/..."
    PYTHIA_INSTALL_PATH="$ROOT_DIR/deps/pythia8312/install"
    if [ ! -d "$PYTHIA_INSTALL_PATH/include/Pythia8" ]; then
        echo "Pythia 8 not found. Downloading and building Pythia 8.312..."
        mkdir -p deps
        PYTHIA_VER="8312"
        PYTHIA_ARCHIVE="pythia${PYTHIA_VER}.tgz"
        if [ ! -f "deps/${PYTHIA_ARCHIVE}" ]; then
            curl -L "https://pythia.org/download/pythia83/${PYTHIA_ARCHIVE}" -o "deps/${PYTHIA_ARCHIVE}"
        fi
        cd deps
        tar -xf "$PYTHIA_ARCHIVE"
        PYTHIA_DIR=$(tar -tf "$PYTHIA_ARCHIVE" | head -1 | cut -f1 -d"/")
        cd "$PYTHIA_DIR"
        ./configure --prefix="$(pwd)/install"
        make -j$(nproc)
        make install
        PYTHIA_INSTALL_PATH="$(pwd)/install"
        cd "$ROOT_DIR"
    fi
fi

echo "Step 2: Applying compatibility patches to JAM2..."
if [ -f "patches/jam2_compatibility.patch" ]; then
    # Check if already patched
    if grep -q "Basics.h" jam2-code/jam2/initcond/Constraints.h 2>/dev/null; then
        echo "JAM2 already appears to be patched. Skipping."
    else
        echo "Applying patches/jam2_compatibility.patch..."
        patch -p1 -d jam2-code < patches/jam2_compatibility.patch
    fi
else
    echo "Warning: patches/jam2_compatibility.patch not found!"
fi

echo "Step 3: Building JAM2..."
cd "$ROOT_DIR/jam2-code"
# Clean previous build artifacts if any
[ -f Makefile ] && make distclean || true

# Download missing autoconf macros
mkdir -p m4
for macro in ax_cxx_compile_stdcxx.m4 ax_require_defined.m4 ax_split_version.m4; do
    if [ ! -f "m4/$macro" ]; then
        curl -L -s "https://raw.githubusercontent.com/autoconf-archive/autoconf-archive/master/m4/$macro" -o "m4/$macro"
    fi
done

# Run autoreconf instead of ./autogen to properly pick up m4 files
autoreconf -vif
./configure PYTHIA8="$PYTHIA_INSTALL_PATH" --prefix="$(pwd)/install"
make -j$(nproc)
make install

echo "--------------------------------------------------"
echo "Environment setup complete!"
echo "To use JAM2, please set the following environment variables:"
echo "export PYTHIA8=$PYTHIA_INSTALL_PATH"
echo "export LD_LIBRARY_PATH=\$PYTHIA8/lib:\$LD_LIBRARY_PATH"
echo "JAM2 executable is at: $(pwd)/install/bin/jam"
