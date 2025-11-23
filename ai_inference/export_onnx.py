import sys
import torch
from pathlib import Path

# -----------------------
# Adjust python path to import auto_avsr
# -----------------------
ROOT = Path(__file__).resolve().parent

# Prefer the downloaded Auto-AVSR sources under ai_inference/models, but fall back
# to a local checkout (ai_inference/auto_avsr) for convenience. This mirrors the
# layout described in the README where model artifacts are kept inside models/.
auto_avsr_candidates = [
    ROOT / "models" / "auto_avsr",
    ROOT / "auto_avsr",
]

for candidate in auto_avsr_candidates:
    if not candidate.exists():
        continue

    # Ensure the `pipelines` package is importable even if it lives in a nested
    # folder (some distributions wrap the source under an extra directory).
    pipelines_parent = None
    if (candidate / "pipelines").exists():
        pipelines_parent = candidate
    else:
        for maybe_dir in candidate.rglob("*"):
            if maybe_dir.is_dir() and maybe_dir.name.lower() == "pipelines":
                pipelines_parent = maybe_dir.parent
                break

    if pipelines_parent is None:
        contents = [p.name for p in candidate.iterdir()]
        available = ", ".join(sorted(contents)) if contents else "(empty)"
        raise FileNotFoundError(
            "Auto-AVSR sources found, but no 'pipelines' package detected inside "
            f"{candidate}. Contents found: {available}. Please ensure the downloaded "
            "Auto-AVSR code includes the 'pipelines' directory (for example, clone "
            "the repository or extract the release archive)."
        )

    AUTO_AVSR_ROOT = candidate
    sys.path.insert(0, str(pipelines_parent))
    sys.path.insert(0, str(AUTO_AVSR_ROOT))
    break
else:
    raise FileNotFoundError(
        "Auto-AVSR sources not found. Please place them under "
        "ai_inference/models/auto_avsr or ai_inference/auto_avsr."
    )

from pipelines.model import AVSR

# -----------------------
# 1. Load checkpoint
# -----------------------
checkpoint_path = AUTO_AVSR_ROOT / "benchmarks" / "LRS3" / "vsr_trlrs2lrs3vox2avsp_base.pth"
ckpt = torch.load(checkpoint_path, map_location="cpu")

config = ckpt["config"]   # contains model args
model_args = config["model_args"]

# Force VSR-only:
model_args["modality"] = "video"
model_args["use_video"] = True
model_args["use_audio"] = False

model = AVSR(**model_args)
model.load_state_dict(ckpt["model"])
model.eval()

# -----------------------
# 2. Dummy Input
# -----------------------
# Auto-AVSR uses 96×96 grayscale lips
dummy = torch.randn(1, 1, 50, 96, 96)  # (B,C,T,H,W)

# -----------------------
# 3. Export ONNX
# -----------------------
onnx_path = ROOT / "models" / "vsr_autoavsr.onnx"
onnx_path.parent.mkdir(exist_ok=True, parents=True)

torch.onnx.export(
    model,
    dummy,
    onnx_path.as_posix(),
    opset_version=12,
    input_names=["video_input"],
    output_names=["logits"],
    dynamic_axes={
        "video_input": {2: "time"},   # dynamic T
        "logits": {0: "time"}         # output is (T, C)
    }
)

print("✅ Exported:", onnx_path)