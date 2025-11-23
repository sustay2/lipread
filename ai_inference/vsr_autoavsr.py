from __future__ import annotations

import logging
from argparse import Namespace
from typing import Union

import torch

from auto_avsr.datamodule.transforms import VideoTransform
from auto_avsr.lightning import ModelModule, get_beam_search_decoder

logger = logging.getLogger(__name__)


class AutoAVSRVSR:
    def __init__(self, ckpt_path: str, device: Union[str, torch.device, None] = None):
        # Prefer GPU when available unless the caller explicitly requests a
        # device. Fall back to CPU cleanly if CUDA is not present.
        if device is None:
            resolved = "cuda" if torch.cuda.is_available() else "cpu"
        elif isinstance(device, str) and device == "cuda" and not torch.cuda.is_available():
            logger.warning("Requested CUDA but it is unavailable; falling back to CPU")
            resolved = "cpu"
        else:
            resolved = device

        self.device = torch.device(resolved)

        # Match the training-time preprocessing.
        self.video_transform = VideoTransform("test")

        # Minimal args needed by ModelModule to build the architecture.
        args = Namespace(modality="video", ctc_weight=0.1, pretrained_model_path=None)
        self.model = self._load_model(ckpt_path, args)
        self.model.eval().to(self.device)
        logger.info("Auto-AVSR model loaded on device %s", self.device)

        # Use the token list stored in the checkpoint (subword vocab, size 5049)
        if hasattr(self.model, "token_list"):
            self.token_list = self.model.token_list
            logger.info("Loaded token list of size %d", len(self.token_list))
        else:
            raise RuntimeError("Checkpoint missing token_list.")

        # Beam search decoder uses the same token list
        self.beam_search = get_beam_search_decoder(
            self.model.model,
            self.token_list,
            ctc_weight=getattr(self.model.args, "ctc_weight", 0.1),
        )

    def _load_model(self, ckpt_path: str, args: Namespace) -> ModelModule:
        # Lightning checkpoints end with .ckpt; averaged weights are saved as .pth.
        if ckpt_path.endswith(".ckpt"):
            return ModelModule.load_from_checkpoint(
                ckpt_path, args=args, map_location=self.device
            )

        module = ModelModule(args)
        state = torch.load(ckpt_path, map_location=self.device)
        state_dict = (
            state["state_dict"] if isinstance(state, dict) and "state_dict" in state else state
        )

        # If keys include the lightning "model." prefix, load the full module.
        if any(k.startswith("model.") for k in state_dict):
            module.load_state_dict(state_dict, strict=False)
        else:
            module.model.load_state_dict(state_dict, strict=False)

        return module

    # vsr_autoavsr.py (inside transcribe method)

    @torch.inference_mode()
    def transcribe(self, video_frames: Union[torch.Tensor, "numpy.ndarray"]) -> str:
        
        # 1. Convert to Tensor
        video_tensor = (
            video_frames
            if isinstance(video_frames, torch.Tensor)
            else torch.as_tensor(video_frames)
        )

        # 2. Validate Shape
        if video_tensor.ndim != 4:
             # Expect [T, H, W, C] from processor
             raise ValueError(f"Invalid shape: {video_tensor.shape}")

        # 3. Permute [T, H, W, C] -> [T, C, H, W] for the Transform
        if video_tensor.shape[-1] == 3:
            video_tensor = video_tensor.permute(0, 3, 1, 2)
        
        # 4. Ensure Float32 [0, 1] range
        if video_tensor.dtype != torch.float32:
            video_tensor = video_tensor.float()
        
        # Safety check: If data somehow came in as 0-255, fix it.
        # But since frame_processor now guarantees 0-1, this is just a guard rail.
        if video_tensor.max() > 1.5:
            video_tensor = video_tensor / 255.0

        # 5. Apply Model Transform (Normalization/Cropping/Grayscaling)
        # This transform expects (T, C, H, W) or (C, T, H, W) depending on version.
        # Usually VideoTransform("test") handles the [T, C, H, W] input standardly.
        processed = self.video_transform(video_tensor)
        processed = processed.to(self.device, non_blocking=True)

        # Forward pass in video-only mode.
        feats = self.model.model.frontend(processed.unsqueeze(0))
        feats = self.model.model.proj_encoder(feats)
        enc_feat, _ = self.model.model.encoder(feats, None)
        enc_feat = enc_feat.squeeze(0)

        # Beam search over encoder features
        nbest_hyps = self.beam_search(enc_feat)
        if not nbest_hyps:
            return ""

        # Best hypothesis sequence of token IDs (includes <bos>/<eos>/blank)
        yseq = nbest_hyps[0].asdict()["yseq"]

        # Drop the first symbol (usually <bos>), keep the rest
        token_ids = [int(i) for i in yseq[1:]]

        print("[DEBUG] yseq:", yseq)
        print("[DEBUG] token_ids:", token_ids)


        # Map token IDs -> subwords using the checkpoint's token_list
        subwords = []
        for tid in token_ids:
            # Skip invalid indices
            if tid < 0 or tid >= len(self.token_list):
                continue
            tok = self.token_list[tid]
            # Skip special tokens
            if tok in ("<blank>", "<unk>"):
                continue
            subwords.append(tok)

        if not subwords:
            return ""

        # Naive reconstruction: join subwords with spaces.
        # (This is a simple baseline; you can refine heuristics later.)
        prediction = " ".join(subwords).strip()

        return prediction