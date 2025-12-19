#!/usr/bin/env python3
"""
Generate fallback AppIcon.appiconset from Icon Composer assets.
This provides backwards compatibility for macOS versions that don't
fully support Icon Composer's .icon format.
"""

from PIL import Image, ImageDraw
import os
import json

# Icon sizes for macOS (size, scale, filename)
ICON_SIZES = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]


def create_gradient_background(size):
    """
    Create gradient background matching icon.json Display P3 colors.
    Colors from icon.json:
    - Top: display-p3:0.22178,0.24296,0.24412 
    - Bottom: display-p3:0.13243,0.14192,0.16961
    """
    img = Image.new("RGB", (size, size))
    
    # Convert Display P3 to approximate sRGB values
    # Top color: ~(57, 62, 62)
    # Bottom color: ~(34, 36, 43)
    color_top = (57, 62, 62)
    color_bottom = (34, 36, 43)
    
    # Gradient stops at y=0.7 per icon.json
    gradient_end = 0.7
    
    for y in range(size):
        ty = y / (size - 1) if size > 1 else 0
        
        if ty <= gradient_end:
            t = ty / gradient_end
            r = int(color_top[0] + (color_bottom[0] - color_top[0]) * t)
            g = int(color_top[1] + (color_bottom[1] - color_top[1]) * t)
            b = int(color_top[2] + (color_bottom[2] - color_top[2]) * t)
        else:
            r, g, b = color_bottom
        
        for x in range(size):
            img.putpixel((x, y), (r, g, b))
    
    return img


def create_icon(logo_path, output_path, size, scale):
    """Create app icon at specified size with logo composited on gradient background."""
    actual_size = size * scale
    
    # Create gradient background
    background = create_gradient_background(actual_size)
    
    # Load logo
    logo = Image.open(logo_path).convert("RGBA")
    
    # Scale logo to 25% of icon size (matching icon.json scale: 0.25)
    # But we need it larger for visibility - use ~70% for the logo to fill nicely
    logo_size = int(actual_size * 0.70)
    
    # Maintain aspect ratio
    logo_aspect = logo.width / logo.height
    if logo_aspect > 1:
        new_width = logo_size
        new_height = int(logo_size / logo_aspect)
    else:
        new_height = logo_size
        new_width = int(logo_size * logo_aspect)
    
    logo_resized = logo.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    # Center the logo
    x_offset = (actual_size - new_width) // 2
    y_offset = (actual_size - new_height) // 2
    
    # Composite logo onto background
    background_rgba = background.convert("RGBA")
    background_rgba.paste(logo_resized, (x_offset, y_offset), logo_resized)
    
    # Convert back to RGB (fully opaque)
    final = Image.new("RGB", (actual_size, actual_size), (0, 0, 0))
    final.paste(background_rgba, (0, 0))
    
    final.save(output_path, "PNG")
    print(f"Created: {output_path} ({actual_size}x{actual_size})")


def create_contents_json(output_dir):
    """Create Contents.json for the appiconset."""
    contents = {
        "images": [
            {"filename": "icon_16x16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
            {"filename": "icon_16x16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
            {"filename": "icon_32x32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
            {"filename": "icon_32x32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
            {"filename": "icon_128x128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
            {"filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
            {"filename": "icon_256x256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
            {"filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
            {"filename": "icon_512x512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
            {"filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"},
        ],
        "info": {"author": "xcode", "version": 1}
    }
    
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    print(f"Created: Contents.json")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    # Source logo from Icon Composer assets
    logo_path = os.path.join(project_root, "Convertify", "AppIcon.icon", "Assets", "clean_convertify.png")
    
    # Output to Assets.xcassets
    output_dir = os.path.join(project_root, "Convertify", "Assets.xcassets", "AppIcon.appiconset")
    
    if not os.path.exists(logo_path):
        print(f"Error: Logo not found at {logo_path}")
        return 1
    
    os.makedirs(output_dir, exist_ok=True)
    
    print("=" * 60)
    print("Generating fallback AppIcon.appiconset")
    print("=" * 60)
    print(f"Logo: {logo_path}")
    print(f"Output: {output_dir}")
    print()
    
    for size, scale, filename in ICON_SIZES:
        output_path = os.path.join(output_dir, filename)
        create_icon(logo_path, output_path, size, scale)
    
    create_contents_json(output_dir)
    
    print()
    print("=" * 60)
    print("Fallback icons generated successfully!")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    exit(main())
