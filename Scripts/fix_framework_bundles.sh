#!/bin/bash

# fix_framework_bundles.sh
# Converts shallow framework bundles to versioned bundles for macOS
# Also strips x86_64 simulator architectures for App Store submission
# This script should be run as a Build Phase in Xcode

set -e

FRAMEWORKS_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ ! -d "$FRAMEWORKS_PATH" ]; then
    echo "Frameworks directory not found, skipping"
    exit 0
fi

echo "Processing frameworks in: $FRAMEWORKS_PATH"

# Function to strip x86_64 architecture from a binary
strip_simulator_archs() {
    local binary="$1"
    if [ ! -f "$binary" ]; then
        return 0
    fi
    
    # Check if binary contains x86_64
    if lipo -info "$binary" 2>/dev/null | grep -q "x86_64"; then
        echo "  Stripping x86_64 from: $(basename "$binary")"
        # Get all architectures except x86_64
        local archs=$(lipo -info "$binary" | sed 's/.*: //' | tr ' ' '\n' | grep -v x86_64 | tr '\n' ' ')
        if [ -n "$archs" ]; then
            lipo -extract $archs "$binary" -output "${binary}.tmp" 2>/dev/null || \
            lipo -remove x86_64 "$binary" -output "${binary}.tmp" 2>/dev/null || true
            if [ -f "${binary}.tmp" ]; then
                mv "${binary}.tmp" "$binary"
            fi
        fi
    fi
}

convert_to_versioned_bundle() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    # Strip x86_64 from the binary first (works for both shallow and versioned)
    if [ -f "$framework_path/$framework_name" ]; then
        strip_simulator_archs "$framework_path/$framework_name"
    elif [ -f "$framework_path/Versions/Current/$framework_name" ]; then
        strip_simulator_archs "$framework_path/Versions/Current/$framework_name"
    fi
    
    # Check if already a versioned bundle
    if [ -d "$framework_path/Versions" ]; then
        return 0
    fi
    
    # Check if Info.plist exists at root (shallow bundle indicator)
    if [ ! -f "$framework_path/Info.plist" ]; then
        return 0
    fi
    
    echo "Converting to versioned bundle: $framework_name.framework"
    
    # Create temporary directory for new structure
    local temp_dir=$(mktemp -d)
    local version_path="$temp_dir/Versions/A"
    mkdir -p "$version_path/Resources"
    
    # Copy binary
    if [ -f "$framework_path/$framework_name" ]; then
        cp -p "$framework_path/$framework_name" "$version_path/$framework_name"
    fi
    
    # Copy Info.plist to Resources
    cp -p "$framework_path/Info.plist" "$version_path/Resources/Info.plist"
    
    # Copy Headers if exists
    if [ -d "$framework_path/Headers" ]; then
        cp -Rp "$framework_path/Headers" "$version_path/Headers"
    fi
    
    # Copy Modules if exists  
    if [ -d "$framework_path/Modules" ]; then
        cp -Rp "$framework_path/Modules" "$version_path/Modules"
    fi
    
    # Create Current symlink
    (cd "$temp_dir/Versions" && ln -sf "A" "Current")
    
    # Create top-level symlinks
    if [ -f "$version_path/$framework_name" ]; then
        (cd "$temp_dir" && ln -sf "Versions/Current/$framework_name" "$framework_name")
    fi
    (cd "$temp_dir" && ln -sf "Versions/Current/Resources" "Resources")
    if [ -d "$version_path/Headers" ]; then
        (cd "$temp_dir" && ln -sf "Versions/Current/Headers" "Headers")
    fi
    if [ -d "$version_path/Modules" ]; then
        (cd "$temp_dir" && ln -sf "Versions/Current/Modules" "Modules")
    fi
    
    # Replace the original framework
    rm -rf "$framework_path"
    mv "$temp_dir" "$framework_path"
}

# Process all frameworks
for framework in "$FRAMEWORKS_PATH"/*.framework; do
    if [ -d "$framework" ]; then
        convert_to_versioned_bundle "$framework"
    fi
done

echo "Framework processing complete"
