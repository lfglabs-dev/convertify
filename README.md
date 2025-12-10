# Convertify

A native macOS frontend for FFmpeg. Drag, drop, convert.

## What is this?

Convertify wraps FFmpeg in a clean, native interface. No command line needed. It's opinionated where it should be and flexible where it matters.

- **Drag and drop** any video, audio, or image
- **Pick a format** and hit convert
- **Sensible defaults** that just work
- **Hardware acceleration** via Apple VideoToolbox when available

## Supported Formats

| Video | Audio | Image |
|-------|-------|-------|
| MP4, MOV, MKV | MP3, AAC, FLAC | JPEG, PNG, WebP |
| WebM, AVI, GIF | WAV, OGG, M4A | HEIC, TIFF, BMP, ICO |

## Quality Presets

Three presets. No knob-twiddling required.

- **Fast** — Quick encode, smaller file
- **Balanced** — Good quality, reasonable speed
- **Quality** — Best output, takes longer

Need more control? Advanced options are there if you want them.

## Requirements

- macOS
- FFmpeg installed (`brew install ffmpeg`)

## Building

```bash
./build-app.sh
```

Or open `Convertify.xcodeproj` in Xcode.

