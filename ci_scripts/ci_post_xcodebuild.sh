#!/bin/bash

# ci_post_xcodebuild.sh
# This script runs after xcodebuild in Xcode Cloud
# It converts shallow framework bundles to versioned bundles for macOS

set -e

echo "🔧 Converting shallow framework bundles to versioned bundles..."

# Find the app bundle in the archive
if [ -n "$CI_ARCHIVE_PATH" ]; then
    APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/Convertify.app"
elif [ -n "$CI_DERIVED_DATA_PATH" ]; then
    APP_PATH=$(find "$CI_DERIVED_DATA_PATH" -name "Convertify.app" -type d | head -1)
else
    echo "⚠️ Could not find app path, skipping bundle conversion"
    exit 0
fi

FRAMEWORKS_PATH="$APP_PATH/Contents/Frameworks"

if [ ! -d "$FRAMEWORKS_PATH" ]; then
    echo "⚠️ Frameworks directory not found at $FRAMEWORKS_PATH"
    exit 0
fi

echo "📂 Processing frameworks in: $FRAMEWORKS_PATH"

# Function to convert a shallow bundle to a versioned bundle
convert_to_versioned_bundle() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    echo "  Converting: $framework_name.framework"
    
    # Check if already a versioned bundle
    if [ -d "$framework_path/Versions" ]; then
        echo "    Already versioned, skipping"
        return 0
    fi
    
    # Check if Info.plist exists at root (shallow bundle indicator)
    if [ ! -f "$framework_path/Info.plist" ]; then
        echo "    No Info.plist at root, skipping"
        return 0
    fi
    
    # Create versioned structure
    local temp_dir=$(mktemp -d)
    local version_path="$temp_dir/Versions/A"
    mkdir -p "$version_path/Resources"
    
    # Move binary (could be named same as framework or different)
    if [ -f "$framework_path/$framework_name" ]; then
        cp "$framework_path/$framework_name" "$version_path/$framework_name"
    fi
    
    # Move Info.plist to Resources
    cp "$framework_path/Info.plist" "$version_path/Resources/Info.plist"
    
    # Move Headers if exists
    if [ -d "$framework_path/Headers" ]; then
        cp -R "$framework_path/Headers" "$version_path/Headers"
    fi
    
    # Move Modules if exists
    if [ -d "$framework_path/Modules" ]; then
        cp -R "$framework_path/Modules" "$version_path/Modules"
    fi
    
    # Move any other resources
    for item in "$framework_path"/*; do
        local item_name=$(basename "$item")
        case "$item_name" in
            "$framework_name"|Info.plist|Headers|Modules|Versions|_CodeSignature)
                # Skip these, already handled or should be regenerated
                ;;
            *)
                if [ -e "$item" ]; then
                    cp -R "$item" "$version_path/Resources/" 2>/dev/null || true
                fi
                ;;
        esac
    done
    
    # Create Current symlink
    ln -s "A" "$temp_dir/Versions/Current"
    
    # Create top-level symlinks
    if [ -f "$version_path/$framework_name" ]; then
        ln -s "Versions/Current/$framework_name" "$temp_dir/$framework_name"
    fi
    ln -s "Versions/Current/Resources" "$temp_dir/Resources"
    if [ -d "$version_path/Headers" ]; then
        ln -s "Versions/Current/Headers" "$temp_dir/Headers"
    fi
    if [ -d "$version_path/Modules" ]; then
        ln -s "Versions/Current/Modules" "$temp_dir/Modules"
    fi
    
    # Replace the original framework
    rm -rf "$framework_path"
    mv "$temp_dir" "$framework_path"
    
    echo "    ✅ Converted successfully"
}

# Process all frameworks
for framework in "$FRAMEWORKS_PATH"/*.framework; do
    if [ -d "$framework" ]; then
        convert_to_versioned_bundle "$framework"
    fi
done

echo "✅ Framework bundle conversion complete"

