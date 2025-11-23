import torch
from argparse import Namespace
from auto_avsr.lightning import ModelModule

ckpt = "models/vsr_trlrs2lrs3vox2avsp_base.pth"

args = Namespace(modality="video", ctc_weight=0.1, pretrained_model_path=None)
module = ModelModule(args)
state = torch.load(ckpt, map_location="cpu")
state_dict = state["state_dict"] if "state_dict" in state else state
module.load_state_dict(state_dict, strict=False)

print("Vocab size:", len(module.token_list))
print("Sample tokens:", module.token_list[:200])