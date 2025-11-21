import torch, platform, sys
print("torch version:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
print("torch.cuda version tag:", torch.version.cuda)
print("device count:", torch.cuda.device_count())
print("current device:", torch.cuda.current_device() if torch.cuda.is_available() else None)
print("gpu name:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)
print("python:", sys.executable)
print("os:", platform.platform())