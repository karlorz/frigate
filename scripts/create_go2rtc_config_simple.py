#!/usr/bin/env python3
"""Creates a go2rtc config file for macOS hybrid setup (simplified version)."""

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

def simple_yaml_load(content):
    """Very basic YAML parser for simple key-value pairs."""
    # This is a very simplified parser - for production use, install PyYAML
    result = {}
    lines = content.split('\n')
    
    for i, line in enumerate(lines):
        if not line.strip() or line.strip().startswith('#'):
            continue
            
        if ':' in line:
            # Calculate indentation
            indent = len(line) - len(line.lstrip())
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()
            
            # Navigate to correct section based on indentation
            current = result
            if indent == 0:
                current = result
            elif indent == 2:  # First level nesting
                # Find parent key
                for j in range(i-1, -1, -1):
                    prev_line = lines[j]
                    if prev_line.strip() and not prev_line.strip().startswith('#'):
                        prev_indent = len(prev_line) - len(prev_line.lstrip())
                        if prev_indent == 0 and ':' in prev_line:
                            parent_key = prev_line.split(':', 1)[0].strip()
                            if parent_key not in result:
                                result[parent_key] = {}
                            current = result[parent_key]
                            break
            elif indent == 4:  # Second level nesting
                # Find parent and grandparent keys
                parent_key = None
                grandparent_key = None
                for j in range(i-1, -1, -1):
                    prev_line = lines[j]
                    if prev_line.strip() and not prev_line.strip().startswith('#'):
                        prev_indent = len(prev_line) - len(prev_line.lstrip())
                        if prev_indent == 2 and ':' in prev_line and parent_key is None:
                            parent_key = prev_line.split(':', 1)[0].strip()
                        elif prev_indent == 0 and ':' in prev_line and grandparent_key is None:
                            grandparent_key = prev_line.split(':', 1)[0].strip()
                            break
                
                if grandparent_key and parent_key:
                    if grandparent_key not in result:
                        result[grandparent_key] = {}
                    if parent_key not in result[grandparent_key]:
                        result[grandparent_key][parent_key] = {}
                    current = result[grandparent_key][parent_key]
            
            # Set the value
            if value:
                current[key] = value.strip('"\'')
            else:
                # Empty value - treat as None or empty string for streams
                if key.endswith('-live') or key.startswith('camera'):
                    current[key] = None  # Will be processed later
                else:
                    current[key] = {}
    
    return result

def create_go2rtc_config():
    """Create go2rtc configuration for macOS hybrid setup."""
    
    frigate_env_vars = get_frigate_env_vars()
    config_file = find_config_file_macos()

    try:
        with open(config_file) as f:
            raw_config = f.read()

        if config_file.endswith((".yaml", ".yml")):
            config: dict[str, Any] = simple_yaml_load(raw_config)
        elif config_file.endswith(".json"):
            config: dict[str, Any] = json.loads(raw_config)
    except FileNotFoundError:
        print(f"[WARN] Config file not found at {config_file}, using empty config")
        config: dict[str, Any] = {}

    go2rtc_config: dict[str, Any] = config.get("go2rtc", {})

    # Need to enable CORS for go2rtc so the frigate integration / card work automatically
    if go2rtc_config.get("api") is None:
        go2rtc_config["api"] = {"origin": "*"}
    elif go2rtc_config["api"].get("origin") is None:
        go2rtc_config["api"]["origin"] = "*"

    # Need to set default location for HA config (adapt for macOS)
    if go2rtc_config.get("hass") is None:
        go2rtc_config["hass"] = {"config": "/homeassistant"}

    # we want to ensure that logs are easy to read
    if go2rtc_config.get("log") is None:
        go2rtc_config["log"] = {"format": "text"}
    elif go2rtc_config["log"].get("format") is None:
        go2rtc_config["log"]["format"] = "text"

    # ensure there is a default webrtc config
    if go2rtc_config.get("webrtc") is None:
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

    if go2rtc_config.get("rtsp", {}).get("username") is not None:
        go2rtc_config["rtsp"]["username"] = go2rtc_config["rtsp"]["username"].format(
            **frigate_env_vars
        )

    if go2rtc_config.get("rtsp", {}).get("password") is not None:
        go2rtc_config["rtsp"]["password"] = go2rtc_config["rtsp"]["password"].format(
            **frigate_env_vars
        )

    # For macOS, use the default ffmpeg path
    ffmpeg_path = "/usr/lib/ffmpeg/7.0/bin/ffmpeg"  # Default version

    if go2rtc_config.get("ffmpeg") is None:
        go2rtc_config["ffmpeg"] = {"bin": ffmpeg_path}
    elif go2rtc_config["ffmpeg"].get("bin") is None:
        go2rtc_config["ffmpeg"]["bin"] = ffmpeg_path

    # Process stream configurations
    streams_to_remove = []
    for name in go2rtc_config.get("streams", {}):
        stream = go2rtc_config["streams"][name]

        if stream is None or stream == "":
            # Empty stream definition - remove it or add a warning
            print(f"[WARN] Stream '{name}' has no source defined, removing from go2rtc config")
            streams_to_remove.append(name)
            continue

        if isinstance(stream, str):
            try:
                go2rtc_config["streams"][name] = go2rtc_config["streams"][name].format(
                    **frigate_env_vars
                )
            except KeyError as e:
                print(
                    "[ERROR] Invalid substitution found, see https://docs.frigate.video/configuration/restream for more info."
                )
                sys.exit(e)

        elif isinstance(stream, list):
            for i, stream in enumerate(stream):
                try:
                    go2rtc_config["streams"][name][i] = stream.format(**frigate_env_vars)
                except KeyError as e:
                    print(
                        "[ERROR] Invalid substitution found, see https://docs.frigate.video/configuration/restream for more info."
                    )
                    sys.exit(e)

    # Remove empty streams
    for name in streams_to_remove:
        del go2rtc_config["streams"][name]

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
        
        # Write go2rtc_config to file
        with open(config_path, "w") as f:
            f.write(simple_yaml_dump(go2rtc_config))
            
        print(f"[INFO] go2rtc config created successfully at {config_path}")
        return config_path
        
    except Exception as e:
        print(f"[ERROR] Failed to create go2rtc config: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()