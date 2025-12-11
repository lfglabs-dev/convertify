#!/usr/bin/env python3
"""
Generate macOS Big Sur+ style app icons from logo and shadow layers.
Creates FULLY OPAQUE square icons - macOS applies its own squircle mask.
"""

from PIL import Image, ImageDraw, ImageFilter
import os
import math
import subprocess

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
    Create a beautiful gradient background matching the logo's color scheme.
    Uses a diagonal gradient from teal/cyan to purple/magenta.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))

    # Color scheme matching the logo (teal/cyan to purple/pink)
    # Top-left: Dark teal
    # Bottom-right: Deep purple/magenta

    # Define gradient colors
    color_tl = (20, 45, 55)  # Dark teal (top-left)
    color_tr = (35, 40, 70)  # Blue-purple (top-right)
    color_bl = (25, 50, 65)  # Teal (bottom-left)
    color_br = (55, 30, 75)  # Purple (bottom-right)

    for y in range(size):
        for x in range(size):
            # Bilinear interpolation for smooth gradient
            tx = x / (size - 1) if size > 1 else 0
            ty = y / (size - 1) if size > 1 else 0

            # Interpolate top edge
            top_r = int(color_tl[0] + (color_tr[0] - color_tl[0]) * tx)
            top_g = int(color_tl[1] + (color_tr[1] - color_tl[1]) * tx)
            top_b = int(color_tl[2] + (color_tr[2] - color_tl[2]) * tx)

            # Interpolate bottom edge
            bot_r = int(color_bl[0] + (color_br[0] - color_bl[0]) * tx)
            bot_g = int(color_bl[1] + (color_br[1] - color_bl[1]) * tx)
            bot_b = int(color_bl[2] + (color_br[2] - color_bl[2]) * tx)

            # Interpolate between top and bottom
            r = int(top_r + (bot_r - top_r) * ty)
            g = int(top_g + (bot_g - top_g) * ty)
            b = int(top_b + (bot_b - top_b) * ty)

            img.putpixel((x, y), (r, g, b, 255))

    return img


def create_inner_glow(size, color=(80, 200, 200), intensity=0.3):
    """Create a subtle inner glow effect for depth."""
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)

    center = size // 2
    max_radius = size // 2

    # Create radial gradient for glow
    for radius in range(max_radius, 0, -1):
        alpha = int(255 * intensity * (1 - radius / max_radius) ** 2)
        if alpha > 0:
            bbox = [center - radius, center - radius, center + radius, center + radius]
            r, g, b = color
            draw.ellipse(bbox, fill=(r, g, b, alpha))

    return glow


def add_drop_shadow(icon, size, offset=(0, 8), blur_radius=15, shadow_opacity=0.4):
    """Add a drop shadow beneath the icon for macOS-style depth."""
    # Create a larger canvas to accommodate the shadow
    shadow_expansion = blur_radius * 2
    canvas_size = size + shadow_expansion * 2

    # Create shadow from icon alpha channel
    shadow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # Get icon alpha and create shadow shape
    icon_alpha = icon.split()[3]
    shadow_layer = Image.new("RGBA", (size, size), (0, 0, 0, int(255 * shadow_opacity)))
    shadow_layer.putalpha(icon_alpha)

    # Position shadow with offset
    shadow_pos = (shadow_expansion + offset[0], shadow_expansion + offset[1])
    shadow.paste(shadow_layer, shadow_pos, shadow_layer)

    # Blur the shadow
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius))

    # Paste original icon on top
    icon_pos = (shadow_expansion, shadow_expansion)
    shadow.paste(icon, icon_pos, icon)

    # Crop back to original size (centering)
    left = shadow_expansion
    top = shadow_expansion
    right = left + size
    bottom = top + size
    return shadow.crop((left, top, right, bottom))


def create_icon(shadow_path, logo_path, output_path, size, scale):
    """
    Create a macOS-style app icon at the specified size and scale.

    IMPORTANT: Icons are fully opaque squares - macOS applies its own squircle mask.
    Do NOT add transparency to corners, as macOS will fill transparent areas with white/gray.
    """
    actual_size = size * scale

    # Step 1: Create gradient background (fully opaque)
    background = create_gradient_background(actual_size)

    # Step 2: Add subtle inner glow for depth
    glow = create_inner_glow(actual_size, color=(100, 180, 180), intensity=0.15)
    background = Image.alpha_composite(background, glow)

    # Step 3: Load and resize logo layer
    logo = Image.open(logo_path).convert("RGBA")

    # Scale logo to fit nicely within the icon (80% of size for proper padding)
    # This accounts for macOS's squircle mask which will clip corners
    logo_size = int(actual_size * 0.80)
    logo_resized = logo.resize((logo_size, logo_size), Image.Resampling.LANCZOS)

    # Center the logo
    logo_offset = (actual_size - logo_size) // 2

    # Step 4: Create shadow for the logo (subtle drop shadow)
    # Shadow is offset to bottom-left of the logo
    logo_with_shadow = add_drop_shadow(
        logo_resized,
        logo_size,
        offset=(
            int(actual_size * 0.02),
            int(actual_size * 0.02),
        ),  # Bottom-right offset (2% each direction)
        blur_radius=int(actual_size * 0.025),  # Subtle blur
        shadow_opacity=0.07,  # Very subtle shadow
    )

    # Step 5: Composite logo onto background
    final = background.copy()
    final.paste(logo_with_shadow, (logo_offset, logo_offset), logo_with_shadow)

    # Step 6: Convert to RGB (remove alpha channel) to ensure fully opaque
    # This is critical - macOS adds white borders if it detects any transparency
    final_rgb = Image.new("RGB", (actual_size, actual_size), (0, 0, 0))
    final_rgb.paste(final, (0, 0), final if final.mode == "RGBA" else None)

    # Save as PNG (RGB, no transparency)
    final_rgb.save(output_path, "PNG")
    print(f"Created: {output_path} ({actual_size}x{actual_size})")


def create_master_icon(shadow_path, logo_path, output_path, size=1024):
    """Create the master 1024x1024 icon for .icns generation."""
    create_icon(shadow_path, logo_path, output_path, size, 1)


def generate_icns(input_dir, output_path):
    """Generate .icns file from iconset directory using iconutil."""
    try:
        # Create temporary iconset directory
        iconset_path = output_path.replace(".icns", ".iconset")
        os.makedirs(iconset_path, exist_ok=True)

        # Copy icons with proper naming for iconutil
        icon_mapping = [
            ("icon_16x16.png", "icon_16x16.png"),
            ("icon_16x16@2x.png", "icon_16x16@2x.png"),
            ("icon_32x32.png", "icon_32x32.png"),
            ("icon_32x32@2x.png", "icon_32x32@2x.png"),
            ("icon_128x128.png", "icon_128x128.png"),
            ("icon_128x128@2x.png", "icon_128x128@2x.png"),
            ("icon_256x256.png", "icon_256x256.png"),
            ("icon_256x256@2x.png", "icon_256x256@2x.png"),
            ("icon_512x512.png", "icon_512x512.png"),
            ("icon_512x512@2x.png", "icon_512x512@2x.png"),
        ]

        for src_name, dst_name in icon_mapping:
            src = os.path.join(input_dir, src_name)
            dst = os.path.join(iconset_path, dst_name)
            if os.path.exists(src):
                import shutil

                shutil.copy2(src, dst)

        # Run iconutil to create .icns
        result = subprocess.run(
            ["iconutil", "-c", "icns", iconset_path, "-o", output_path],
            capture_output=True,
            text=True,
        )

        if result.returncode == 0:
            print(f"Created: {output_path}")
            # Clean up iconset
            import shutil

            shutil.rmtree(iconset_path)
            return True
        else:
            print(f"Error creating .icns: {result.stderr}")
            return False

    except Exception as e:
        print(f"Error generating .icns: {e}")
        return False


def update_contents_json(output_dir):
    """Update the Contents.json file with the generated icon filenames."""
    contents = {
        "images": [
            {
                "filename": "icon_16x16.png",
                "idiom": "mac",
                "scale": "1x",
                "size": "16x16",
            },
            {
                "filename": "icon_16x16@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": "16x16",
            },
            {
                "filename": "icon_32x32.png",
                "idiom": "mac",
                "scale": "1x",
                "size": "32x32",
            },
            {
                "filename": "icon_32x32@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": "32x32",
            },
            {
                "filename": "icon_128x128.png",
                "idiom": "mac",
                "scale": "1x",
                "size": "128x128",
            },
            {
                "filename": "icon_128x128@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": "128x128",
            },
            {
                "filename": "icon_256x256.png",
                "idiom": "mac",
                "scale": "1x",
                "size": "256x256",
            },
            {
                "filename": "icon_256x256@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": "256x256",
            },
            {
                "filename": "icon_512x512.png",
                "idiom": "mac",
                "scale": "1x",
                "size": "512x512",
            },
            {
                "filename": "icon_512x512@2x.png",
                "idiom": "mac",
                "scale": "2x",
                "size": "512x512",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }

    import json

    contents_path = os.path.join(output_dir, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"Updated: {contents_path}")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    shadow_path = os.path.join(script_dir, "shadow_layer_converted.png")
    logo_path = os.path.join(script_dir, "logo_layer_converted.png")
    output_dir = os.path.join(
        script_dir, "Convertify", "Assets.xcassets", "AppIcon.appiconset"
    )
    icns_path = os.path.join(
        script_dir, "Convertify.app", "Contents", "Resources", "AppIcon.icns"
    )

    if not os.path.exists(shadow_path):
        print(f"Warning: Shadow layer not found at {shadow_path}")
        print("Proceeding without shadow layer...")

    if not os.path.exists(logo_path):
        print(f"Error: Logo layer not found at {logo_path}")
        return 1

    os.makedirs(output_dir, exist_ok=True)

    print("=" * 60)
    print("Generating macOS Big Sur+ style app icons")
    print("=" * 60)
    print(f"Logo layer: {logo_path}")
    print(f"Output: {output_dir}")
    print()

    # Generate all icon sizes
    for size, scale, filename in ICON_SIZES:
        output_path = os.path.join(output_dir, filename)
        create_icon(shadow_path, logo_path, output_path, size, scale)

    # Update Contents.json
    update_contents_json(output_dir)

    # Generate .icns file
    print()
    print("Generating .icns file...")
    os.makedirs(os.path.dirname(icns_path), exist_ok=True)
    generate_icns(output_dir, icns_path)

    print()
    print("=" * 60)
    print("✅ App icons generated successfully!")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Open Xcode and verify the icons in Assets.xcassets")
    print("2. Rebuild the app to apply the new icons")
    print()

    return 0


if __name__ == "__main__":
    exit(main())
