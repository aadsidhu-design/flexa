#!/usr/bin/env python3

import os
import json
from PIL import Image

def generate_app_icons():
    # Source image path
    source_path = "/Users/aadi/Desktop/FlexaSwiftUI/ChatGPT Image Sep 1, 2025, 11_37_08 PM.png"
    
    # Destination directory
    dest_dir = "/Users/aadi/Desktop/FlexaSwiftUI/FlexaSwiftUI/Assets.xcassets/AppIcon.appiconset"
    
    # iOS App Icon sizes and filenames
    icon_sizes = [
        (20, "Icon-20.png"),
        (29, "Icon-29.png"),
        (40, "Icon-40.png"),
        (58, "Icon-58.png"),
        (60, "Icon-60.png"),
        (76, "Icon-76.png"),
        (80, "Icon-80.png"),
        (87, "Icon-87.png"),
        (120, "Icon-120.png"),
        (152, "Icon-152.png"),
        (167, "Icon-167.png"),
        (180, "Icon-180.png"),
        (1024, "Icon-1024.png")
    ]
    
    # Create destination directory if it doesn't exist
    os.makedirs(dest_dir, exist_ok=True)
    
    print(f"📱 Loading source image: {source_path}")
    
    # Load and process source image
    try:
        source_img = Image.open(source_path)
        source_img = source_img.convert("RGBA")
        print(f"✅ Source image loaded: {source_img.size}")
        
        # Generate all icon sizes
        for size, filename in icon_sizes:
            print(f"🖼️  Generating {size}x{size} -> {filename}")
            
            # Resize with high quality
            resized = source_img.resize((size, size), Image.Resampling.LANCZOS)
            
            # Convert to RGB for PNG (removes alpha channel)
            if resized.mode == "RGBA":
                # Create white background
                background = Image.new("RGB", (size, size), (255, 255, 255))
                background.paste(resized, mask=resized.split()[-1])
                resized = background
            
            # Save the icon
            output_path = os.path.join(dest_dir, filename)
            resized.save(output_path, "PNG", quality=100)
            print(f"   ✅ Saved: {output_path}")
        
        # Generate Contents.json
        contents_json = {
            "images": [
                {"filename": "Icon-40.png", "idiom": "ipad", "scale": "1x", "size": "40x40"},
                {"filename": "Icon-80.png", "idiom": "ipad", "scale": "2x", "size": "40x40"},
                {"filename": "Icon-60.png", "idiom": "iphone", "scale": "2x", "size": "30x30"},
                {"filename": "Icon-120.png", "idiom": "iphone", "scale": "2x", "size": "60x60"},
                {"filename": "Icon-180.png", "idiom": "iphone", "scale": "3x", "size": "60x60"},
                {"filename": "Icon-58.png", "idiom": "iphone", "scale": "2x", "size": "29x29"},
                {"filename": "Icon-87.png", "idiom": "iphone", "scale": "3x", "size": "29x29"},
                {"filename": "Icon-80.png", "idiom": "iphone", "scale": "2x", "size": "40x40"},
                {"filename": "Icon-120.png", "idiom": "iphone", "scale": "3x", "size": "40x40"},
                {"filename": "Icon-20.png", "idiom": "iphone", "scale": "1x", "size": "20x20"},
                {"filename": "Icon-40.png", "idiom": "iphone", "scale": "2x", "size": "20x20"},
                {"filename": "Icon-60.png", "idiom": "iphone", "scale": "3x", "size": "20x20"},
                {"filename": "Icon-76.png", "idiom": "ipad", "scale": "1x", "size": "76x76"},
                {"filename": "Icon-152.png", "idiom": "ipad", "scale": "2x", "size": "76x76"},
                {"filename": "Icon-167.png", "idiom": "ipad", "scale": "2x", "size": "83.5x83.5"},
                {"filename": "Icon-1024.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"}
            ],
            "info": {
                "author": "xcode",
                "version": 1
            }
        }
        
        contents_path = os.path.join(dest_dir, "Contents.json")
        with open(contents_path, 'w') as f:
            json.dump(contents_json, f, indent=2)
        
        print(f"📄 Generated Contents.json: {contents_path}")
        print("🎉 App icon generation complete!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    return True

if __name__ == "__main__":
    generate_app_icons()
