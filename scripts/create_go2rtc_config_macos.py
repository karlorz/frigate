#!/usr/bin/env python3
"""Creates a go2rtc config file for macOS hybrid setup."""

import json
import os
import sys
from pathlib import Path
from typing import Any

import yaml

# Add frigate to Python path
sys.path.insert(0, "/Users/karlchow/Desktop/code/frigate-local")
from frigate.const import (
    BIRDSEYE_PIPE,
    DEFAULT_FFMPEG_VERSION,
    INCLUDED_FFMPEG_VERSIONS,
    LIBAVFORMAT_VERSION_MAJOR,
)
from frigate.ffmpeg_presets import parse_preset_hardware_acceleration_encode
from frigate.util.config import find_config_file

sys.path.remove("/Users/karlchow/Desktop/code/frigate-local")

# Use standard yaml module

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

def create_go2rtc_config():
    """Create go2rtc configuration for macOS hybrid setup."""
    
    frigate_env_vars = get_frigate_env_vars()
    config_file = find_config_file_macos()

    try:
        with open(config_file) as f:
            raw_config = f.read()

        if config_file.endswith((".yaml", ".yml")):
            config: dict[str, Any] = yaml.safe_load(raw_config)
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

    # For macOS, use the default ffmpeg path or Docker container path
    # Since we're running hybrid, ffmpeg will be in the Docker container
    path = config.get("ffmpeg", {}).get("path", "default")
    if path == "default":
        ffmpeg_path = f"/usr/lib/ffmpeg/{DEFAULT_FFMPEG_VERSION}/bin/ffmpeg"
    elif path in INCLUDED_FFMPEG_VERSIONS:
        ffmpeg_path = f"/usr/lib/ffmpeg/{path}/bin/ffmpeg"
    else:
        ffmpeg_path = f"{path}/bin/ffmpeg"

    if go2rtc_config.get("ffmpeg") is None:
        go2rtc_config["ffmpeg"] = {"bin": ffmpeg_path}
    elif go2rtc_config["ffmpeg"].get("bin") is None:
        go2rtc_config["ffmpeg"]["bin"] = ffmpeg_path

    # need to replace ffmpeg command when using ffmpeg4
    if LIBAVFORMAT_VERSION_MAJOR < 59:
        rtsp_args = "-fflags nobuffer -flags low_delay -stimeout 10000000 -user_agent go2rtc/ffmpeg -rtsp_transport tcp -i {input}"
        if go2rtc_config.get("ffmpeg") is None:
            go2rtc_config["ffmpeg"] = {"rtsp": rtsp_args}
        elif go2rtc_config["ffmpeg"].get("rtsp") is None:
            go2rtc_config["ffmpeg"]["rtsp"] = rtsp_args

    # Process stream configurations
    for name in go2rtc_config.get("streams", {}):
        stream = go2rtc_config["streams"][name]

        if isinstance(stream, str):
            try:
                go2rtc_config["streams"][name] = go2rtc_config["streams"][name].format(
                    **frigate_env_vars
                )
            except KeyError as e:
                print(
                    "[ERROR] Invalid substitution found, see https://docs.frigate.video/configuration/restream#advanced-restream-configurations for more info."
                )
                sys.exit(e)

        elif isinstance(stream, list):
            for i, stream in enumerate(stream):
                try:
                    go2rtc_config["streams"][name][i] = stream.format(**frigate_env_vars)
                except KeyError as e:
                    print(
                        "[ERROR] Invalid substitution found, see https://docs.frigate.video/configuration/restream#advanced-restream-configurations for more info."
                    )
                    sys.exit(e)

    # add birdseye restream stream if enabled
    if config.get("birdseye", {}).get("restream", False):
        birdseye: dict[str, Any] = config.get("birdseye")

        input = f"-f rawvideo -pix_fmt yuv420p -video_size {birdseye.get('width', 1280)}x{birdseye.get('height', 720)} -r 10 -i {BIRDSEYE_PIPE}"
        ffmpeg_cmd = f"exec:{parse_preset_hardware_acceleration_encode(ffmpeg_path, config.get('ffmpeg', {}).get('hwaccel_args', ''), input, '-rtsp_transport tcp -f rtsp {output}')}"

        if go2rtc_config.get("streams"):
            go2rtc_config["streams"]["birdseye"] = ffmpeg_cmd
        else:
            go2rtc_config["streams"] = {"birdseye": ffmpeg_cmd}

    return go2rtc_config

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
            yaml.dump(go2rtc_config, f, default_flow_style=False)
            
        print(f"[INFO] go2rtc config created successfully at {config_path}")
        return config_path
        
    except Exception as e:
        print(f"[ERROR] Failed to create go2rtc config: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()