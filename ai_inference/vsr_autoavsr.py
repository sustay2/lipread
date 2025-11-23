"""Auto-AVSR model wrapper for video-only lip reading."""

from __future__ import annotations

import logging
from argparse import Namespace
from typing import Union

import torch

from auto_avsr.datamodule.transforms import VideoTransform
from auto_avsr.lightning import ModelModule, get_beam_search_decoder

logger = logging.getLogger(__name__)


class AutoAVSRVSR:
    """Thin convenience wrapper around the Auto-AVSR Lightning module.

    The class normalizes device placement, preprocesses video frames using the
    official evaluation transform, and decodes model outputs into text. It is
    intentionally free of any FastAPI/WebSocket concerns to remain easily
    reusable in other entrypoints (batch/offline, etc.).
    """

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

        # Cache decoder utilities.
        self.text_transform = self.model.text_transform
        self.beam_search = get_beam_search_decoder(
            self.model.model,
            self.model.token_list,
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

    @torch.inference_mode()
    def transcribe(self, video_frames: Union[torch.Tensor, "numpy.ndarray"]) -> str:
        """Run lip-reading inference on a chunk of frames.

        Args:
            video_frames: Array or tensor shaped either [T, H, W, C] or
                [T, C, H, W]. The model expects RGB ordering and float data.

        Returns:
            Text decoded from the visual-only Auto-AVSR stack.
        """

        video_tensor = (
            video_frames
            if isinstance(video_frames, torch.Tensor)
            else torch.as_tensor(video_frames)
        )

        if video_tensor.ndim != 4:
            raise ValueError(
                "Expected video tensor with shape [T, H, W, C] or [T, C, H, W], "
                f"got {video_tensor.shape}"
            )

        # Convert THWC -> TCHW if necessary.
        if video_tensor.shape[-1] in (1, 3):
            video_tensor = video_tensor.permute(0, 3, 1, 2)

        # Normalize to float32 [0, 1] before the official transform.
        if video_tensor.dtype != torch.float32:
            video_tensor = video_tensor.float()
        if video_tensor.max() > 1.5:
            video_tensor = video_tensor / 255.0

        # Normalize + crop using the training-time pipeline.
        processed = self.video_transform(video_tensor)
        processed = processed.to(self.device, non_blocking=True)

        # Forward pass in video-only mode.
        feats = self.model.model.frontend(processed.unsqueeze(0))
        feats = self.model.model.proj_encoder(feats)
        enc_feat, _ = self.model.model.encoder(feats, None)
        enc_feat = enc_feat.squeeze(0)

        nbest_hyps = self.beam_search(enc_feat)
        if not nbest_hyps:
            return ""

        token_ids = torch.tensor(
            list(map(int, nbest_hyps[0].asdict()["yseq"][1:])), device=self.device
        )
        prediction = (
            self.text_transform.post_process(token_ids.cpu()).replace("<eos>", "")
        )

        return prediction
