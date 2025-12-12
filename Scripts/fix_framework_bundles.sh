#!/bin/bash

# fix_framework_bundles.sh
# Convert shallow framework bundles to versioned bundles for macOS
# Strip x86_64, fix bundle identifiers, and re-sign frameworks for App Store

set -e

FRAMEWORKS_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
APP_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER}"
CODE_SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:-}"

if [ ! -d "$FRAMEWORKS_PATH" ]; then
    echo "Frameworks directory not found, skipping"
    exit 0
fi

echo "Processing frameworks in: $FRAMEWORKS_PATH"
echo "App Bundle ID: $APP_BUNDLE_ID"

# Function to create valid bundle ID (replace underscores with hyphens)
make_valid_bundle_id() {
    echo "$1" | tr '_' '-'
}

# Function to strip x86_64 architecture from a binary
strip_simulator_archs() {
    local binary="$1"
    if [ ! -f "$binary" ]; then
        return 0
    fi
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
    # Create valid bundle ID (no underscores allowed)
    local safe_name=$(make_valid_bundle_id "$framework_name")
    local new_bundle_id="${APP_BUNDLE_ID}.${safe_name}"
    
    echo "Processing: $framework_name.framework -> $new_bundle_id"
    
    # Find and strip x86_64 from binary
    local binary_path=""
    if [ -f "$framework_path/$framework_name" ]; then
        binary_path="$framework_path/$framework_name"
    elif [ -f "$framework_path/Versions/Current/$framework_name" ]; then
        binary_path="$framework_path/Versions/Current/$framework_name"
    fi
    
    if [ -n "$binary_path" ]; then
        strip_simulator_archs "$binary_path"
    fi
    
    # Fix bundle identifier in all possible Info.plist locations
    for plist in "$framework_path/Info.plist" \
                 "$framework_path/Resources/Info.plist" \
                 "$framework_path/Versions/Current/Resources/Info.plist" \
                 "$framework_path/Versions/A/Resources/Info.plist"; do
        if [ -f "$plist" ]; then
            echo "  Updating bundle ID in: $plist"
            /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_bundle_id" "$plist" 2>/dev/null || true
        fi
    done
    
    # Convert shallow bundle to versioned if needed
    if [ ! -d "$framework_path/Versions" ] && [ -f "$framework_path/Info.plist" ]; then
        echo "  Converting to versioned bundle"
        local temp_dir=$(mktemp -d)
        local version_path="$temp_dir/Versions/A"
        mkdir -p "$version_path/Resources"
        
        [ -f "$framework_path/$framework_name" ] && cp -p "$framework_path/$framework_name" "$version_path/$framework_name"
        cp -p "$framework_path/Info.plist" "$version_path/Resources/Info.plist"
        [ -d "$framework_path/Headers" ] && cp -Rp "$framework_path/Headers" "$version_path/Headers"
        [ -d "$framework_path/Modules" ] && cp -Rp "$framework_path/Modules" "$version_path/Modules"
        
        (cd "$temp_dir/Versions" && ln -sf "A" "Current")
        [ -f "$version_path/$framework_name" ] && (cd "$temp_dir" && ln -sf "Versions/Current/$framework_name" "$framework_name")
        (cd "$temp_dir" && ln -sf "Versions/Current/Resources" "Resources")
        [ -d "$version_path/Headers" ] && (cd "$temp_dir" && ln -sf "Versions/Current/Headers" "Headers")
        [ -d "$version_path/Modules" ] && (cd "$temp_dir" && ln -sf "Versions/Current/Modules" "Modules")
        
        rm -rf "$framework_path"
        mv "$temp_dir" "$framework_path"
    fi
    
    # Re-sign framework with correct identifier
    echo "  Re-signing with identifier: $new_bundle_id"
    if [ -n "$CODE_SIGN_ID" ] && [ "$CODE_SIGN_ID" != "-" ]; then
        codesign --force --sign "$CODE_SIGN_ID" --identifier "$new_bundle_id" --timestamp=none --generate-entitlement-der "$framework_path" 2>/dev/null || \
        codesign --force --sign "$CODE_SIGN_ID" --identifier "$new_bundle_id" "$framework_path" 2>/dev/null || true
    else
        codesign --force --sign - --identifier "$new_bundle_id" "$framework_path" 2>/dev/null || true
    fi
}

# Process all frameworks
for framework in "$FRAMEWORKS_PATH"/*.framework; do
    if [ -d "$framework" ]; then
        process_framework "$framework"
    fi
done

echo "Framework processing complete"
