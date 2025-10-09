#!/usr/bin/env python3
"""Creates a go2rtc config file for macOS hybrid setup (working version)."""

import json
import os
import sys
from pathlib import Path
from typing import Any

def get_frigate_env_vars():
    """Get Frigate environment variables and secrets."""
    env_vars = {k: v for k, v in os.environ.items() if k.startswith("FRIGATE_")}
    
    # Read docker secret files as env vars too (if they exist)
    secrets_dir = "/run/secrets"
    if os.path.isdir(secrets_dir):
        for secret_file in os.listdir(secrets_dir):
            if secret_file.startswith("FRIGATE_"):
                secret_path = Path(os.path.join(secrets_dir, secret_file))
                env_vars[secret_file] = secret_path.read_text().strip()
    
    return env_vars

def find_config_file_macos():
    """Find Frigate config file for macOS setup."""
    # Look for config in common locations
    config_locations = [
        "/Users/karlchow/Desktop/code/frigate-local/config/config.yml",
        "/Users/karlchow/Desktop/code/frigate-local/config/config.yaml",
        "/Users/karlchow/Desktop/code/frigate-local/config.yml",
        "/Users/karlchow/Desktop/code/frigate-local/config.yaml",
    ]
    
    for config_path in config_locations:
        if os.path.exists(config_path):
            return config_path
    
    # If not found, return the expected location
    return "/Users/karlchow/Desktop/code/frigate-local/config/config.yml"

def extract_go2rtc_section(content):
    """Extract just the go2rtc section from YAML content."""
    lines = content.split('\n')
    go2rtc_lines = []
    in_go2rtc_section = False
    
    for line in lines:
        if line.strip() == 'go2rtc:':
            in_go2rtc_section = True
            continue
        
        if in_go2rtc_section:
            if line.strip() == '':
                continue
                
            line_indent = len(line) - len(line.lstrip())
            
            # If we hit a line at the same level or less indented than 'go2rtc:', we're done
            if line_indent == 0 and line.strip().endswith(':'):
                break
                
            # Collect lines that are indented (part of go2rtc section)
            if line_indent > 0:
                go2rtc_lines.append(line)
    
    # Parse the collected lines into a simple structure
    result = {}
    current_stream = None
    
    for line in go2rtc_lines:
        line_indent = len(line) - len(line.lstrip())
        
        if line.strip().startswith('- '):
            # This is a list item
            list_value = line.strip()[2:].strip('"\'')  # Remove '- ' and quotes
            if current_stream and isinstance(result.get("streams", {}).get(current_stream), list):
                result["streams"][current_stream].append(list_value)
            continue
            
        if ':' in line:
            key = line.split(':')[0].strip()
            value = line.split(':', 1)[1].strip() if ':' in line and len(line.split(':', 1)) > 1 else ""
            
            if line_indent == 2:  # First level under go2rtc
                if value:
                    result[key] = value
                else:
                    result[key] = {}
                    if key == "streams":
                        current_stream = None
            elif line_indent == 4:  # Second level (stream names)
                if "streams" in result:
                    current_stream = key
                    if value:
                        result["streams"][key] = value
                    else:
                        result["streams"][key] = []  # Initialize as list for array items
            elif line_indent == 6:  # Third level (stream properties)
                parent_key = current_stream
                if parent_key and "streams" in result and parent_key in result["streams"]:
                    if isinstance(result["streams"][parent_key], dict):
                        result["streams"][parent_key][key] = value if value else None
    
    return result

def create_go2rtc_config():
    """Create go2rtc configuration for macOS hybrid setup."""
    
    frigate_env_vars = get_frigate_env_vars()
    config_file = find_config_file_macos()

    try:
        with open(config_file) as f:
            raw_config = f.read()

        # Extract just the go2rtc section
        go2rtc_config = extract_go2rtc_section(raw_config)
        
    except FileNotFoundError:
        print(f"[WARN] Config file not found at {config_file}, using empty config")
        go2rtc_config = {}

    # Apply defaults
    
    # Need to enable CORS for go2rtc so the frigate integration / card work automatically
    if go2rtc_config.get("api") is None:
        go2rtc_config["api"] = {"origin": "*"}
    elif isinstance(go2rtc_config["api"], dict) and go2rtc_config["api"].get("origin") is None:
        go2rtc_config["api"]["origin"] = "*"

    # Need to set default location for HA config (adapt for macOS)
    if go2rtc_config.get("hass") is None:
        go2rtc_config["hass"] = {"config": "/homeassistant"}

    # we want to ensure that logs are easy to read
    if go2rtc_config.get("log") is None:
        go2rtc_config["log"] = {"format": "text"}
    elif isinstance(go2rtc_config["log"], dict) and go2rtc_config["log"].get("format") is None:
        go2rtc_config["log"]["format"] = "text"

    # ensure there is a default webrtc config
    if go2rtc_config.get("webrtc") is None:
        go2rtc_config["webrtc"] = {}

    if not isinstance(go2rtc_config["webrtc"], dict):
        go2rtc_config["webrtc"] = {}
        
    if go2rtc_config["webrtc"].get("candidates") is None:
        default_candidates = []
        # use internal candidate if it was discovered when running through the add-on
        internal_candidate = os.environ.get("FRIGATE_GO2RTC_WEBRTC_CANDIDATE_INTERNAL")
        if internal_candidate is not None:
            default_candidates.append(internal_candidate)
        # should set default stun server so webrtc can work (for macOS, use localhost)
        default_candidates.append("stun:8555")

        go2rtc_config["webrtc"]["candidates"] = default_candidates

    if isinstance(go2rtc_config.get("rtsp"), dict):
        if go2rtc_config["rtsp"].get("username") is not None:
            go2rtc_config["rtsp"]["username"] = go2rtc_config["rtsp"]["username"].format(
                **frigate_env_vars
            )

        if go2rtc_config["rtsp"].get("password") is not None:
            go2rtc_config["rtsp"]["password"] = go2rtc_config["rtsp"]["password"].format(
                **frigate_env_vars
            )

    # For macOS, use the default ffmpeg path
    ffmpeg_path = "/usr/lib/ffmpeg/7.0/bin/ffmpeg"  # Default version

    if go2rtc_config.get("ffmpeg") is None:
        go2rtc_config["ffmpeg"] = {"bin": ffmpeg_path}
    elif isinstance(go2rtc_config["ffmpeg"], dict) and go2rtc_config["ffmpeg"].get("bin") is None:
        go2rtc_config["ffmpeg"]["bin"] = ffmpeg_path

    # Process stream configurations - preserve all streams including empty ones
    if "streams" in go2rtc_config and isinstance(go2rtc_config["streams"], dict):
        for name, stream in go2rtc_config["streams"].items():
            if isinstance(stream, str) and stream:
                # Process string streams with environment variable substitution
                try:
                    go2rtc_config["streams"][name] = stream.format(**frigate_env_vars)
                except KeyError as e:
                    print(f"[WARN] Invalid substitution in stream '{name}': {e}, keeping original")
            elif isinstance(stream, list):
                # Process list streams (like [""] or ["rtsp://...", "ffmpeg:..."])
                processed_list = []
                for item in stream:
                    if isinstance(item, str):
                        try:
                            processed_item = item.format(**frigate_env_vars) if item else ""
                            processed_list.append(processed_item)
                        except KeyError as e:
                            print(f"[WARN] Invalid substitution in stream '{name}' item: {e}, keeping original")
                            processed_list.append(item)
                    else:
                        processed_list.append(item)
                go2rtc_config["streams"][name] = processed_list
            # For None, empty string, or empty dict - keep as-is
            # This preserves the user's intent even if the stream is empty

    return go2rtc_config

def simple_yaml_dump(data, indent=0):
    """Very basic YAML writer."""
    result = []
    for key, value in data.items():
        if isinstance(value, dict):
            result.append(f"{'  ' * indent}{key}:")
            result.append(simple_yaml_dump(value, indent + 1))
        elif isinstance(value, list):
            result.append(f"{'  ' * indent}{key}:")
            for item in value:
                if isinstance(item, str) and item.startswith('stun:'):
                    result.append(f"{'  ' * (indent + 1)}- \"{item}\"")
                else:
                    result.append(f"{'  ' * (indent + 1)}- {item}")
        else:
            # Properly quote values that need it
            if isinstance(value, str) and ('*' in value or ':' in value):
                result.append(f"{'  ' * indent}{key}: \"{value}\"")
            else:
                result.append(f"{'  ' * indent}{key}: {value}")
    return '\n'.join(result)

def main():
    """Main function to create go2rtc config."""
    config_dir = "/Users/karlchow/Desktop/code/frigate-local/config"
    os.makedirs(config_dir, exist_ok=True)
    
    config_path = os.path.join(config_dir, "go2rtc.yaml")
    
    print(f"[INFO] Creating go2rtc config at {config_path}")
    
    try:
        go2rtc_config = create_go2rtc_config()
        
        print(f"[DEBUG] Generated config: {go2rtc_config}")
        
        # Write go2rtc_config to file
        with open(config_path, "w") as f:
            f.write(simple_yaml_dump(go2rtc_config))
            
        print(f"[INFO] go2rtc config created successfully at {config_path}")
        return config_path
        
    except Exception as e:
        print(f"[ERROR] Failed to create go2rtc config: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()