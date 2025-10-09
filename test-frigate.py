#!/usr/bin/env python3

# Simple test to check if frigate modules can import correctly
import sys
import os

# Add frigate to path
sys.path.insert(0, '/Users/karlchow/Desktop/code/frigate-local')

try:
    print("Testing frigate.version import...")
    from frigate.version import VERSION
    print(f"✅ frigate.version imported successfully: {VERSION}")
except ImportError as e:
    print(f"❌ frigate.version import failed: {e}")

try:
    print("Testing frigate.ffmpeg_presets import...")
    from frigate.ffmpeg_presets import parse_preset_hardware_acceleration_encode
    print("✅ frigate.ffmpeg_presets imported successfully")
except ImportError as e:
    print(f"❌ frigate.ffmpeg_presets import failed: {e}")

try:
    print("Testing frigate.app import...")
    from frigate.app import FrigateApp
    print("✅ frigate.app imported successfully")
except ImportError as e:
    print(f"❌ frigate.app import failed: {e}")

print("Import test completed")