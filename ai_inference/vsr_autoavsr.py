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
        if device is None:
            resolved = "cuda" if torch.cuda.is_available() else "cpu"
        elif isinstance(device, str) and device == "cuda" and not torch.cuda.is_available():
            logger.warning("Requested CUDA but it is unavailable; falling back to CPU")
            resolved = "cpu"
        else:
            resolved = device

        self.device = torch.device(resolved)
        self.video_transform = VideoTransform("test")

        args = Namespace(modality="video", ctc_weight=0.1, pretrained_model_path=None)
        self.model = self._load_model(ckpt_path, args)
        self.model.eval().to(self.device)
        logger.info("Auto-AVSR model loaded on device %s", self.device)

        if hasattr(self.model, "token_list"):
            self.token_list = self.model.token_list
            logger.info("Loaded token list of size %d", len(self.token_list))
        else:
            raise RuntimeError("Checkpoint missing token_list.")

        self.beam_search = get_beam_search_decoder(
            self.model.model,
            self.token_list,
            ctc_weight=getattr(self.model.args, "ctc_weight", 0.1),
        )

    def _load_model(self, ckpt_path: str, args: Namespace) -> ModelModule:
        if ckpt_path.endswith(".ckpt"):
            return ModelModule.load_from_checkpoint(
                ckpt_path, args=args, map_location=self.device
            )

        module = ModelModule(args)
        state = torch.load(ckpt_path, map_location=self.device)
        state_dict = (
            state["state_dict"] if isinstance(state, dict) and "state_dict" in state else state
        )

        if any(k.startswith("model.") for k in state_dict):
            module.load_state_dict(state_dict, strict=False)
        else:
            module.model.load_state_dict(state_dict, strict=False)

        return module

    @torch.inference_mode()
    def transcribe(self, video_frames: Union[torch.Tensor, "numpy.ndarray"]) -> str:
        """Run Auto-AVSR on a batch of lip crops.

        Args:
            video_frames: Numpy or torch tensor shaped [T, 112, 112, 1] in [0,1].
        Returns:
            Cleaned English string without SentencePiece markers or special tokens.
        """

        video_tensor = (
            video_frames if isinstance(video_frames, torch.Tensor) else torch.as_tensor(video_frames)
        )

        if video_tensor.ndim != 4 or video_tensor.shape[-1] != 1:
            raise ValueError(f"Invalid shape for grayscale input: {video_tensor.shape}")

        video_tensor = video_tensor.float()
        video_tensor = video_tensor.permute(0, 3, 1, 2).contiguous()

        processed = self.video_transform(video_tensor)
        processed = processed.to(self.device, non_blocking=True)

        feats = self.model.model.frontend(processed.unsqueeze(0))
        feats = self.model.model.proj_encoder(feats)
        enc_feat, _ = self.model.model.encoder(feats, None)
        enc_feat = enc_feat.squeeze(0)

        nbest_hyps = self.beam_search(enc_feat)
        if not nbest_hyps:
            return ""

        yseq = nbest_hyps[0].asdict()["yseq"]
        token_ids = [int(i) for i in yseq[1:]]

        subwords: list[str] = []
        for tid in token_ids:
            if tid < 0 or tid >= len(self.token_list):
                continue

            tok = self.token_list[tid]

            if tok.startswith("<") and tok.endswith(">"):
                continue
            if tok in {"<blank>", "<unk>", "<eos>", "<sos>"}:
                continue

            subwords.append(tok)

        return self._merge_subwords(subwords)

    def _merge_subwords(self, subwords: list[str]) -> str:
        """Merge SentencePiece-style subwords into clean English text."""

        words: list[str] = []
        current = ""

        for piece in subwords:
            if not piece:
                continue

            if piece.startswith("▁"):
                if current:
                    words.append(current)
                current = piece.lstrip("▁")
            else:
                current += piece

        if current:
            words.append(current)

        return " ".join(words).strip()
