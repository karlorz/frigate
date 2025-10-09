#!/usr/bin/env python3
"""
OpenVINO Model Conversion Script for Frigate (macOS)
Simplified version compatible with OpenVINO 2025.2.0
"""

import openvino as ov
import os
import sys
import urllib.request
import tarfile
import shutil
from pathlib import Path

print("OpenVINO Model Converter for Frigate (macOS)")
print(f"OpenVINO version: {ov.get_version()}")

# Create output directory in current working directory
output_dir = Path("./openvino-model")
output_dir.mkdir(parents=True, exist_ok=True)

# Model paths - try multiple locations
possible_model_dirs = [
    "/models/ssdlite_mobilenet_v2_coco_2018_05_09",
    "./models/ssdlite_mobilenet_v2_coco_2018_05_09", 
    "/opt/frigate/models/ssdlite_mobilenet_v2_coco_2018_05_09",
    Path.home() / "frigate-local/models/ssdlite_mobilenet_v2_coco_2018_05_09"
]

frozen_graph_path = None
pipeline_config_path = None

# Find the model files
for model_dir in possible_model_dirs:
    model_path = Path(model_dir)
    if model_path.exists():
        frozen_graph = model_path / "frozen_inference_graph.pb"
        pipeline_config = model_path / "pipeline.config"
        if frozen_graph.exists() and pipeline_config.exists():
            frozen_graph_path = str(frozen_graph)
            pipeline_config_path = str(pipeline_config)
            print(f"Found models in: {model_dir}")
            break

def download_model():
    """Download and extract the TensorFlow model."""
    model_url = "http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz"
    model_filename = "ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz"
    extract_dir = Path("./models")
    
    print("📥 Downloading TensorFlow model...")
    try:
        # Download the model
        urllib.request.urlretrieve(model_url, model_filename)
        print(f"✅ Downloaded {model_filename}")
        
        # Create models directory
        extract_dir.mkdir(exist_ok=True)
        
        # Extract the tarball
        print("📦 Extracting model files...")
        with tarfile.open(model_filename, "r:gz") as tar:
            tar.extractall(path=extract_dir, filter='data')
        
        # Clean up the tarball
        os.remove(model_filename)
        
        # Return paths to the extracted files
        model_dir = extract_dir / "ssdlite_mobilenet_v2_coco_2018_05_09"
        return str(model_dir / "frozen_inference_graph.pb"), str(model_dir / "pipeline.config")
        
    except Exception as e:
        print(f"❌ Download failed: {e}")
        return None, None

if not frozen_graph_path:
    print("❌ TensorFlow model files not found!")
    print("📥 Attempting automatic download...")
    
    # Try to download the model
    frozen_graph_path, pipeline_config_path = download_model()
    
    if not frozen_graph_path:
        print("❌ Automatic download failed!")
        print("📋 Manual download instructions:")
        print("   wget http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz")
        print("   tar -xzf ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz")
        print("   mkdir -p ./models && mv ssdlite_mobilenet_v2_coco_2018_05_09 ./models/")
        
        # Check if we can at least verify the environment
        try:
            import tensorflow as tf
            print(f"\n✅ TensorFlow available: {tf.__version__}")
            print("✅ OpenVINO installation verified")
            print(f"✅ Output directory created: {output_dir.absolute()}")
        except ImportError:
            print("❌ TensorFlow not available - install with: pip install tensorflow")
        sys.exit(1)
    
    print("✅ Model downloaded successfully!")

output_path = "./openvino-model/ssdlite_mobilenet_v2.xml"

print(f"Converting model...")
print(f"Input: {frozen_graph_path}")
print(f"Config: {pipeline_config_path}")
print(f"Output: {output_path}")

try:
    # Try OpenVINO 2025.2.0 simplified API
    print("Using OpenVINO 2025.2.0 convert_model API...")
    ov_model = ov.convert_model(frozen_graph_path)
    
    # Save as FP16 to optimize file size
    from openvino.tools import mo
    print("Compressing model to FP16...")
    ov_model = mo.convert_model(ov_model, compress_to_fp16=True)
    
    ov.save_model(ov_model, output_path)
    print(f"✅ Model converted and saved to: {output_path}")
    
except Exception as e:
    print(f"❌ Conversion with compression failed: {str(e)}")
    
    # Try basic conversion without compression
    try:
        print("Trying basic conversion...")
        ov_model = ov.convert_model(frozen_graph_path)
        ov.save_model(ov_model, output_path)
        print(f"✅ Model converted (uncompressed) and saved to: {output_path}")
        
    except Exception as e2:
        print(f"❌ Basic conversion also failed: {str(e2)}")
        print("This might be due to TensorFlow Object Detection API model format.")
        print("Consider using openvino-dev package for full model conversion support.")
        sys.exit(1)

print("🎉 Model conversion completed successfully!")