#!/bin/bash

# fix_framework_bundles.sh
# Converts shallow framework bundles to versioned bundles for macOS
# This script should be run as a Build Phase in Xcode

set -e

FRAMEWORKS_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

if [ ! -d "$FRAMEWORKS_PATH" ]; then
    echo "Frameworks directory not found, skipping"
    exit 0
fi

echo "Converting shallow framework bundles in: $FRAMEWORKS_PATH"

convert_to_versioned_bundle() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    # Check if already a versioned bundle
    if [ -d "$framework_path/Versions" ]; then
        return 0
    fi
    
    # Check if Info.plist exists at root (shallow bundle indicator)
    if [ ! -f "$framework_path/Info.plist" ]; then
        return 0
    fi
    
    echo "Converting: $framework_name.framework"
    
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

echo "Framework bundle conversion complete"

