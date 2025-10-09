#!/usr/bin/env python3

# Debug script to see what gets parsed from config
import sys
sys.path.insert(0, '/Users/karlchow/Desktop/code/frigate-local/scripts')

from create_go2rtc_config_simple import simple_yaml_load, find_config_file_macos

config_file = find_config_file_macos()
print(f"Reading config from: {config_file}")

with open(config_file) as f:
    raw_config = f.read()

print("\nRaw config:")
print(raw_config)

print("\nParsed result:")
config = simple_yaml_load(raw_config)
print(config)

print(f"\ngo2rtc section: {config.get('go2rtc')}")
if 'go2rtc' in config:
    print(f"streams: {config['go2rtc'].get('streams')}")