#!/bin/bash

# fix_framework_bundles.sh
# Converts shallow framework bundles to versioned bundles for macOS
# Also strips x86_64 simulator architectures and fixes bundle identifiers for App Store
# This script should be run as a Build Phase in Xcode

set -e

FRAMEWORKS_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
APP_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER}"

if [ ! -d "$FRAMEWORKS_PATH" ]; then
    echo "Frameworks directory not found, skipping"
    exit 0
fi

echo "Processing frameworks in: $FRAMEWORKS_PATH"
echo "App Bundle ID: $APP_BUNDLE_ID"

# Function to fix bundle identifier in Info.plist
fix_bundle_identifier() {
    local plist_path="$1"
    local framework_name="$2"
    
    if [ ! -f "$plist_path" ]; then
        return 0
    fi
    
    local current_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2>/dev/null || echo "")
    local new_id="${APP_BUNDLE_ID}.${framework_name}"
    
    if [ -n "$current_id" ] && [ "$current_id" != "$new_id" ]; then
        echo "  Fixing bundle ID: $current_id -> $new_id"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_id" "$plist_path" 2>/dev/null || true
    fi
}

# Function to strip x86_64 architecture from a binary
strip_simulator_archs() {
    local binary="$1"
    if [ ! -f "$binary" ]; then
        return 0
    fi
    
    # Check if binary contains x86_64
    if lipo -info "$binary" 2>/dev/null | grep -q "x86_64"; then
        echo "  Stripping x86_64 from: $(basename "$binary")"
        lipo -remove x86_64 "$binary" -output "${binary}.tmp" 2>/dev/null || true
        if [ -f "${binary}.tmp" ]; then
            mv "${binary}.tmp" "$binary"
        fi
    fi
}

process_framework() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    echo "Processing: $framework_name.framework"
    
    # Strip x86_64 from the binary
    if [ -f "$framework_path/$framework_name" ]; then
        strip_simulator_archs "$framework_path/$framework_name"
    elif [ -f "$framework_path/Versions/Current/$framework_name" ]; then
        strip_simulator_archs "$framework_path/Versions/Current/$framework_name"
    fi
    
    # Fix bundle identifier in Info.plist (check both locations)
    if [ -f "$framework_path/Info.plist" ]; then
        fix_bundle_identifier "$framework_path/Info.plist" "$framework_name"
    fi
    if [ -f "$framework_path/Versions/Current/Resources/Info.plist" ]; then
        fix_bundle_identifier "$framework_path/Versions/Current/Resources/Info.plist" "$framework_name"
    fi
    if [ -f "$framework_path/Resources/Info.plist" ]; then
        fix_bundle_identifier "$framework_path/Resources/Info.plist" "$framework_name"
    fi
    
    # Check if already a versioned bundle
    if [ -d "$framework_path/Versions" ]; then
        return 0
    fi
    
    # Check if Info.plist exists at root (shallow bundle indicator)
    if [ ! -f "$framework_path/Info.plist" ]; then
        return 0
    fi
    
    echo "  Converting to versioned bundle"
    
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
        process_framework "$framework"
    fi
done

echo "Framework processing complete"
