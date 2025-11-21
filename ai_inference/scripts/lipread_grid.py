"""
Lip Reading on GRID with CNN‑RNN + CTC (PyTorch)
=================================================
Single‑file project you can run end‑to‑end:
  1) Preprocess: extract mouth ROIs into frame folders
  2) Train: 3D‑CNN -> BiLSTM -> CTC
  3) Evaluate: CER/WER + sample decoding

Usage examples
--------------
# 1) Preprocess original GRID into frame datasets (uses MediaPipe FaceMesh)
python lipread_grid.py preprocess
  --grid_root /path/to/grid
  --out_root /path/to/grid_frames_96
  --speakers s1 s2 s3 s4
  --min_frames 60 --max_frames 80

# 2) Train with GRID Corpus
python scripts/lipread_grid.py train
  --data_root data_processed
  --train_speakers s1_processed s2_processed s3_processed s4_processed 
    s5_processed s6_processed s7_processed s8_processed s9_processed 
    s10_processed s11_processed s12_processed s13_processed s14_processed 
    s15_processed s16_processed s17_processed s18_processed s19_processed 
    s20_processed s21_processed s22_processed s23_processed s24_processed 
    s25_processed s26_processed s27_processed s28_processed s29_processed 
    s30_processed s31_processed s32_processed
  --val_speakers s33_processed s34_processed
  --epochs 40 --batch_size 4 --num_workers 4 --amp
  --early_stop_patience 10 --min_delta 0.001 --lr 1e-4

# 3) Train with Lombard GRID
python scripts/lipread_grid.py train \
  --data_root data_lombard_processed \
  --train_speakers
    s3_front s4_front s5_front s7_front s8_front s9_front s11_front s12_front s13_front s15_front s16_front
    s17_front s19_front s20_front s21_front s23_front s24_front s25_front s27_front s28_front s29_front
    s31_front s32_front s33_front s35_front s36_front s37_front s39_front s40_front s41_front s43_front
    s44_front s45_front s46_front s47_front s48_front s49_front s50_front s51_front s52_front s53_front
    s54_front s55_front
  --val_speakers
    s2_front s6_front s10_front s14_front s18_front s22_front s26_front s30_front s34_front s38_front s42_front
  --epochs 20
  --batch_size 4
  --num_workers 4
  --lr 1e-4
  --amp
  --resume_ckpt ai_inference/runs/grid_ctc/best.pt

4) Train with Data Synth
python scripts/lipread_grid.py train
  --data_root data_synth/processed_synth
  --train_speakers speaker_1 speaker_2 speaker_3 speaker_4 speaker_5
  --val_speakers speaker_6
  --batch_size 8
  --num_workers 4
  --epochs 40
  --lr 5e-5
  --amp
  --resume_ckpt runs/lombard_front_ctc/best.pt
  --out_dir runs/synth_words_from_lombard_front_ctc

python scripts/lipread_grid.py train
  --data_root data_lombard_processed
  --train_speakers
    s3_front s3_side s4_front s4_side s5_front s5_side s7_front s7_side s8_front s8_side s9_front s9_side
    s11_front s11_side s12_front s12_side s13_front s13_side s15_front s15_side s16_front s16_side
    s17_front s17_side s19_front s19_side s20_front s20_side s21_front s21_side s23_front s23_side
    s24_front s24_side s25_front s25_side s27_front s27_side s28_front s28_side s29_front s29_side
    s31_front s31_side s32_front s32_side s33_front s33_side s35_front s35_side s36_front s36_side
    s37_front s37_side s39_front s39_side s40_front s40_side s41_front s41_side s43_front s43_side
    s44_front s44_side s45_front s45_side s46_front s46_side s47_front s47_side s48_front s48_side
    s49_front s49_side s50_front s50_side s51_front s51_side s52_front s52_side s53_front s53_side
    s54_front s54_side s55_front s55_side
  --val_speakers
    s2_front s2_side s6_front s6_side s10_front s10_side s14_front s14_side s18_front s18_side
    s22_front s22_side s26_front s26_side s30_front s30_side s34_front s34_side s38_front s38_side
    s42_front s42_side
  --epochs 20
  --batch_size 2
  --num_workers 4
  --lr 7e-5
  --amp
  --resume_ckpt runs/grid_ctc/best.pt

# 4) Evaluate / Decode sample videos
python lipread_grid.py test
  --data_root /path/to/grid_frames_96
  --ckpt runs/grid_ctc/best.pt
  --val_speakers s4 --num_samples 8

Notes
-----
• This script expects transcripts in standard GRID format (e.g., align/utt.align or trans/utt.txt).
• If MediaPipe fails to detect landmarks, we fall back to a centered face crop (robust for GRID).
• All frames are normalized to 96×96 grayscale and time‑center padded/truncated to a range if needed.
• Character set covers [A‑Z, 0‑9, space, apostrophe] + CTC blank.

Dependencies
------------
python -m pip install torch torchvision torchaudio opencv-python mediapipe decord numpy pandas tqdm editdistance
"""

from __future__ import annotations
import os
import sys
import cv2
import math
import time
import json
import glob
import random
import shutil
import string
import itertools
from dataclasses import dataclass
from typing import List, Tuple, Dict, Optional

import multiprocessing as mproc

import numpy as np
from tqdm import tqdm

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
from torch.amp import autocast, GradScaler

try:
    import mediapipe as mp
    MP_OK = True
except Exception:
    MP_OK = False

try:
    import decord
    from decord import VideoReader
    from decord import cpu as decpu
    DECORD_OK = True
except Exception:
    DECORD_OK = False

try:
    import editdistance
    ED_OK = True
except Exception:
    ED_OK = False

ALPHABET = " " + string.ascii_lowercase + string.digits + "'"  # leading space is index 0
# CTC uses an extra blank token at the end
BLANK_INDEX = len(ALPHABET)
NUM_CLASSES = len(ALPHABET) + 1

# ------------------------------------------------------------
# Utils
# ------------------------------------------------------------

def set_seed(seed: int = 1337):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)


def list_speakers(root: str) -> List[str]:
    return sorted([
        d for d in os.listdir(root)
        if (d.startswith('s') and os.path.isdir(os.path.join(root, d)))
    ])


def grid_find_alignment_file(spk_dir: str, utt_id: str) -> Optional[str]:
    # Try typical GRID layouts
    for rel in [f"align/{utt_id}.align", f"labels/{utt_id}.align", f"trans/{utt_id}.txt"]:
        p = os.path.join(spk_dir, rel)
        if os.path.isfile(p):
            return p
    return None


def grid_read_transcript(aln_file: str) -> str:
    # GRID alignment files often hold word + timings per line; we just need the words in order.
    with open(aln_file, 'r', encoding='utf-8', errors='ignore') as f:
        lines = [ln.strip() for ln in f.readlines() if ln.strip()]
    # Heuristics: if file has spaces with 3+ columns, last token is the word; otherwise a single line transcript
    words = []
    if len(lines) == 1 and (' ' not in lines[0] or lines[0].count(' ') < 2):
        # maybe it's a plain transcript file
        words = lines[0].split()
    else:
        for ln in lines:
            parts = ln.split()
            if len(parts) >= 3:
                words.append(parts[-1])
            else:
                # fallback: take whole line
                words += ln.split()
    sent = ' '.join(words).lower()
    return sent


def text_to_labels(text: str) -> List[int]:
    return [ALPHABET.index(ch) if ch in ALPHABET else ALPHABET.index(' ') for ch in text]


def labels_to_text(labels: List[int]) -> str:
    return ''.join(ALPHABET[i] for i in labels)


def greedy_decode(logits: torch.Tensor) -> List[str]:
    # logits: (T, B, C)
    probs = logits.softmax(-1)
    best = probs.argmax(-1)  # (T, B)
    outs = []
    T, B = best.shape
    for b in range(B):
        seq = best[:, b].cpu().tolist()
        # collapse repeats + remove blanks
        collapsed = []
        prev = None
        for t in seq:
            if t == BLANK_INDEX:
                prev = None
                continue
            if t != prev:
                collapsed.append(t)
            prev = t
        outs.append(labels_to_text(collapsed))
    return outs


def wer(reference: str, hyp: str) -> float:
    if not ED_OK:
        return float('nan')
    r = reference.split()
    h = hyp.split()
    return editdistance.eval(r, h) / max(1, len(r))


def cer(reference: str, hyp: str) -> float:
    if not ED_OK:
        return float('nan')
    r = list(reference)
    h = list(hyp)
    return editdistance.eval(r, h) / max(1, len(r))


# ------------------------------------------------------------
# Preprocessing: mouth ROI extraction
# ------------------------------------------------------------

@dataclass
class PreprocessArgs:
    grid_root: str
    out_root: str
    speakers: List[str]
    fps: int = 25
    out_size: int = 96
    min_frames: int = 48
    max_frames: int = 80
    face_scale: float = 1.2  # expand box a bit
    verbose: bool = False


def extract_mouth_roi(frame: np.ndarray, face_mesh, out_size: int = 96) -> np.ndarray:
    h, w = frame.shape[:2]
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    res = face_mesh.process(rgb)
    if not res.multi_face_landmarks:
        # fallback: center crop
        sz = min(h, w)
        y0 = (h - sz) // 2
        x0 = (w - sz) // 2
        crop = frame[y0:y0+sz, x0:x0+sz]
        crop = cv2.resize(crop, (out_size, out_size), interpolation=cv2.INTER_AREA)
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        return gray
    lm = res.multi_face_landmarks[0]
    pts = np.array([(p.x * w, p.y * h) for p in lm.landmark])
    # Mouth landmarks (outer lips) approximate indices in FaceMesh
    mouth_idx = list(range(61, 88))  # 61..87
    mpts = pts[mouth_idx]
    x, y, ww, hh = cv2.boundingRect(mpts.astype(np.int32))
    cx = x + ww / 2
    cy = y + hh / 2
    sz = int(max(ww, hh) * 2.0)  # include cheeks/chin for stability
    x0 = max(0, int(cx - sz // 2))
    y0 = max(0, int(cy - sz // 2))
    x1 = min(w, x0 + sz)
    y1 = min(h, y0 + sz)
    crop = frame[y0:y1, x0:x1]
    if crop.size == 0:
        crop = frame
    crop = cv2.resize(crop, (out_size, out_size), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    return gray


def process_speaker(args_tuple):
    spk, args, MP_OK = args_tuple
    try:
        spk_dir = os.path.join(args.grid_root, spk)

        # Detect video folder or direct files
        vdir = os.path.join(spk_dir, 'video')
        if os.path.isdir(vdir):
            mpeg_files = sorted(glob.glob(os.path.join(vdir, '*.mpg')) + glob.glob(os.path.join(vdir, '*.mp4')))
        else:
            mpeg_files = sorted(glob.glob(os.path.join(spk_dir, '*.mpg')) + glob.glob(os.path.join(spk_dir, '*.mp4')))

        if len(mpeg_files) == 0:
            print(f"[WARN] No videos found in {spk}")
            return

        out_spk = os.path.join(args.out_root, spk)
        ensure_dir(out_spk)

        # MediaPipe FaceMesh per process (important for multiprocessing)
        face_mesh = None
        if MP_OK:
            import mediapipe as mpmod
            face_mesh = mpmod.solutions.face_mesh.FaceMesh(static_image_mode=False, refine_landmarks=True)

        for vf in tqdm(mpeg_files, desc=f"{spk}", position=0, leave=False):
            utt_id = os.path.splitext(os.path.basename(vf))[0]
            aln = grid_find_alignment_file(spk_dir, utt_id)
            transcript = grid_read_transcript(aln) if aln else utt_id
            out_utt = os.path.join(out_spk, utt_id)
            if os.path.isdir(out_utt):
                continue
            ensure_dir(out_utt)

            # Read video frames
            cap = cv2.VideoCapture(vf)
            frames = []
            while True:
                ret, img = cap.read()
                if not ret:
                    break
                if face_mesh is not None:
                    gray = extract_mouth_roi(img, face_mesh, out_size=args.out_size)
                else:
                    # fallback: center crop
                    h, w = img.shape[:2]
                    sz = min(h, w)
                    y0 = (h - sz)//2
                    x0 = (w - sz)//2
                    crop = img[y0:y0+sz, x0:x0+sz]
                    crop = cv2.resize(crop, (args.out_size, args.out_size))
                    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                frames.append(gray)
            cap.release()

            # Temporal normalization
            T = len(frames)
            if T < args.min_frames:
                while len(frames) < args.min_frames:
                    frames.append(frames[-1])
            elif T > args.max_frames:
                start = (T - args.max_frames)//2
                frames = frames[start:start+args.max_frames]

            # Save frames + label
            for i, g in enumerate(frames):
                cv2.imwrite(os.path.join(out_utt, f"frame_{i:04d}.png"), g)
            with open(os.path.join(out_utt, 'label.txt'), 'w', encoding='utf-8') as f:
                f.write(transcript.strip() + "\n")

        if face_mesh:
            face_mesh.close()

        print(f"[DONE] {spk} processed ({len(mpeg_files)} videos).")

    except Exception as e:
        print(f"[ERR] Speaker {spk}: {e}")
        return


def preprocess_grid(args: PreprocessArgs):
    assert os.path.isdir(args.grid_root), f"GRID root not found: {args.grid_root}"
    ensure_dir(args.out_root)

    spks = args.speakers or list_speakers(args.grid_root)
    print(f"Detected {len(spks)} speakers → {spks}")

    # Limit to CPU count or fewer
    num_workers = min(mproc.cpu_count(), len(spks))
    print(f"[INFO] Using {num_workers} parallel processes.")

    # Prepare worker arguments
    task_args = [(spk, args, MP_OK) for spk in spks]

    # Use multiprocessing pool
    with mproc.Pool(processes=num_workers) as pool:
        list(tqdm(pool.imap_unordered(process_speaker, task_args), total=len(spks), desc="Overall Progress"))

    print("\nPreprocessing complete for all speakers.")


# ------------------------------------------------------------
# Dataset
# ------------------------------------------------------------

class GridFrames(Dataset):
    def __init__(self, root: str, speakers: List[str], max_frames: int = 80):
        self.items = []
        for spk in speakers:
            spk_dir = os.path.join(root, spk)
            if not os.path.isdir(spk_dir):
                continue
            for utt_dir in sorted(os.listdir(spk_dir)):
                up = os.path.join(spk_dir, utt_dir)
                if not os.path.isdir(up):
                    continue
                lbl = os.path.join(up, 'label.txt')
                if not os.path.isfile(lbl):
                    continue
                frames = sorted(glob.glob(os.path.join(up, 'frame_*.png')))
                if len(frames) == 0:
                    continue
                self.items.append((frames, lbl))
        self.max_frames = max_frames

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        frames, lbl_path = self.items[idx]
        # read label
        with open(lbl_path, 'r', encoding='utf-8') as f:
            text = f.readline().strip().lower()
        y = np.array(text_to_labels(text), dtype=np.int64)

        # read frames as (T, H, W)
        imgs = []
        for fp in frames:
            g = cv2.imread(fp, cv2.IMREAD_GRAYSCALE)
            if g is None:
                # tolerate missing -> skip
                continue
            g = g.astype(np.float32) / 255.0
            imgs.append(g)
        T = len(imgs)
        # (T, 1, H, W)
        x = np.stack(imgs, axis=0)
        x = x[:, None, :, :]  # channel dim
        return x, y, T, len(y)


def pad_collate(batch):
    # batch of (x[T,1,H,W], y[L], T, L)
    T_max = max(item[2] for item in batch)
    H = batch[0][0].shape[-2]
    W = batch[0][0].shape[-1]
    B = len(batch)
    X = np.zeros((B, 1, T_max, H, W), dtype=np.float32)
    input_lengths = []
    Ys = []
    target_lengths = []
    for i, (x, y, T, L) in enumerate(batch):
        X[i, 0, :T] = x[:, 0]
        input_lengths.append(T)
        Ys.append(y)
        target_lengths.append(L)
    Ys_cat = np.concatenate(Ys, axis=0)
    return (
        torch.from_numpy(X),
        torch.from_numpy(Ys_cat),
        torch.tensor(input_lengths, dtype=torch.int32),
        torch.tensor(target_lengths, dtype=torch.int32),
    )


# ------------------------------------------------------------
# Model (3D CNN + BiLSTM + CTC)
# ------------------------------------------------------------

class Conv3DBlock(nn.Module):
    def __init__(self, cin, cout, k=(3,5,5), s=(1,2,2), p=(1,2,2)):
        super().__init__()
        self.conv = nn.Conv3d(cin, cout, k, stride=s, padding=p)
        self.bn = nn.BatchNorm3d(cout)
        self.act = nn.ReLU(inplace=True)

    def forward(self, x):
        return self.act(self.bn(self.conv(x)))
    

class LipReadCTC(nn.Module):
    def __init__(self, num_classes: int = NUM_CLASSES, hidden: int = 256):
        super().__init__()
        self.backbone = nn.Sequential(
            Conv3DBlock(1, 32),
            nn.MaxPool3d((1,2,2)),
            Conv3DBlock(32, 64),
            nn.MaxPool3d((1,2,2)),
            Conv3DBlock(64, 128),
            nn.MaxPool3d((1,2,2)),
        )
        # After backbone, spatial dims are small; we pool them away -> (B, C, T)
        self.rnn = nn.LSTM(input_size=128, hidden_size=512,
                           num_layers=2, batch_first=True, bidirectional=True, dropout=0.3)
        self.classifier = nn.Linear(512*2, num_classes)

    def forward(self, x):
        # x: (B, 1, T, H, W)
        feat = self.backbone(x)                 # (B, C, T, h, w)
        feat = feat.mean(dim=(3, 4))            # spatial global avg -> (B, C, T)
        feat = feat.permute(0, 2, 1).contiguous()  # (B, T, C)
        seq, _ = self.rnn(feat)                 # (B, T, 2H)
        logits = self.classifier(seq)           # (B, T, C)
        logits = logits.permute(1, 0, 2)        # (T, B, C) for CTC
        return logits


# ------------------------------------------------------------
# Training / Evaluation
# ------------------------------------------------------------

@dataclass
class TrainArgs:
    data_root: str
    train_speakers: List[str]
    val_speakers: List[str]
    out_dir: str = "runs/grid_ctc"
    epochs: int = 30
    batch_size: int = 8
    num_workers: int = 8
    lr: float = 1e-3
    weight_decay: float = 1e-4
    grad_clip: float = 5.0
    amp: bool = False
    gpus: int = 1
    seed: int = 1337
    early_stop_patience: int = 40
    min_delta: float = 0.0
    resume_ckpt: Optional[str] = None

def save_ckpt(model, opt, epoch, val_cer, path, meta=None, args=None):
    ensure_dir(os.path.dirname(path))
    train_args = {}
    if args is not None:
        # Store args for reference, but DO NOT force-overwrite user-specified epochs on resume.
        # Only persist for diagnostics / defaults on strict resume.
        train_args = {
            'data_root': getattr(args, 'data_root', None),
            'batch_size': getattr(args, 'batch_size', None),
            'num_workers': getattr(args, 'num_workers', None),
            'lr': getattr(args, 'lr', None),
            'weight_decay': getattr(args, 'weight_decay', None),
            'grad_clip': getattr(args, 'grad_clip', None),
            'amp': getattr(args, 'amp', None),
            'gpus': getattr(args, 'gpus', None),
            'seed': getattr(args, 'seed', None),
            'early_stop_patience': getattr(args, 'early_stop_patience', None),
            'min_delta': getattr(args, 'min_delta', None),
            # NOTE: we persist epochs for info, but will NOT overwrite the user’s target on resume
            'epochs': getattr(args, 'epochs', None),
        }
    torch.save({
        'model': model.state_dict(),
        'opt': opt.state_dict(),
        'epoch': epoch,
        'val_cer': val_cer,
        'meta': meta or {},
        'train_args': train_args
    }, path)

def load_ckpt(model, path, map_location=None):
    ck = torch.load(path, map_location=map_location)
    model.load_state_dict(ck['model'])
    return ck

class EarlyStopping:
    def __init__(self, patience: int = 5, min_delta: float = 0.0):
        self.patience = max(0, int(patience))
        self.min_delta = float(min_delta)
        self.best = None
        self.num_bad_epochs = 0

    def step(self, value: float) -> bool:
        if self.best is None or value < (self.best - self.min_delta):
            self.best = value
            self.num_bad_epochs = 0
            return False
        else:
            self.num_bad_epochs += 1
            return self.num_bad_epochs >= self.patience


def train_loop(args: TrainArgs):
    set_seed(args.seed)
    device = torch.device('cuda' if torch.cuda.is_available() and args.gpus > 0 else 'cpu')
    device_type = 'cuda' if device.type == 'cuda' else 'cpu'

    # -- Show device info --
    if device.type == 'cuda':
        print(f"[GPU] Training on: {torch.cuda.get_device_name(0)}")
        print(f"       CUDA version: {torch.version.cuda}")
        print(f"       PyTorch built with CUDA: {torch.version.cuda is not None}")
        print(f"       Current memory usage: {torch.cuda.memory_allocated(0) / 1024**2:.1f} MB / "
              f"{torch.cuda.get_device_properties(0).total_memory / 1024**2:.1f} MB")
    else:
        print("[CPU] Training on CPU (no CUDA available or gpus=0)")

    model = LipReadCTC(num_classes=NUM_CLASSES).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    sched = torch.optim.lr_scheduler.ReduceLROnPlateau(opt, mode='min', factor=0.5, patience=2)
    ctc = nn.CTCLoss(blank=BLANK_INDEX, zero_infinity=True)

    # Scaler that works on both CUDA and CPU (CPU autocast disabled automatically)
    try:
        scaler = torch.amp.GradScaler(device_type=device_type, enabled=(args.amp and device_type=='cuda'))
    except TypeError:
        from torch.cuda.amp import GradScaler as OldGradScaler
        scaler = OldGradScaler(enabled=(args.amp and device_type=='cuda'))

    start_epoch = 1
    max_epochs  = int(args.epochs)  # preserve user’s target (e.g., 60) and never downgrade
    best_cer = float('inf')
    last_val_cer = float('inf')
    current_epoch = 0

    print("[DEBUG] CWD =", os.getcwd())
    print("[DEBUG] resume_ckpt =", args.resume_ckpt)
    print("[DEBUG] effective early_stop_patience =", args.early_stop_patience)
    print("[DEBUG] effective min_delta =", args.min_delta)

    ckpt_path = os.path.abspath(args.resume_ckpt) if args.resume_ckpt else None
    if ckpt_path and os.path.isfile(ckpt_path):
        print(f"[Resume] Loading checkpoint from {ckpt_path}")
        ck = torch.load(ckpt_path, map_location=device)
        model.load_state_dict(ck['model'])
        opt.load_state_dict(ck['opt'])

        saved_args = ck.get('train_args', {}) or {}
        print("[Resume] (info) saved train_args:", saved_args)

        start_epoch = int(ck.get('epoch', 0)) + 1
        best_cer = float(ck.get('val_cer', float('inf')))
        meta = ck.get('meta', {})

        # restore dataset info if missing
        if (not args.train_speakers) and ('train_speakers' in meta):
            args.train_speakers = meta['train_speakers']
        if (not args.val_speakers) and ('val_speakers' in meta):
            args.val_speakers = meta['val_speakers']
        if (not args.data_root) and ('data_root' in meta):
            args.data_root = meta['data_root']

        # If user’s target is behind last completed, extend just enough to continue
        if max_epochs <= (start_epoch - 1):
            print(f"[Resume] Requested epochs ({max_epochs}) <= last completed ({start_epoch-1}). "
                  f"Setting max_epochs = {start_epoch + 1}.")
            max_epochs = start_epoch + 1

        print("[Resume] (info) using runtime args:", {
            'epochs': max_epochs,
            'batch_size': args.batch_size,
            'lr': args.lr,
            'early_stop_patience': args.early_stop_patience,
            'min_delta': args.min_delta,
        })

        print(f"✔ Resumed from epoch {start_epoch}/{max_epochs} (prev CER={best_cer:.3f})")
    else:
        print("[INFO] Starting fresh training run.")

    # Auto-detect speakers if still missing
    if not args.train_speakers or not args.val_speakers:
        if not args.data_root or not os.path.isdir(args.data_root):
            raise ValueError("❌ data_root is invalid; specify --data_root or resume from checkpoint with meta.")
        detected = list_speakers(args.data_root)
        if not detected:
            raise ValueError(f"❌ No speakers found in {args.data_root}")
        args.train_speakers = args.train_speakers or detected
        args.val_speakers   = args.val_speakers   or detected
        print(f"[AUTO] Using auto-detected speakers (train={len(args.train_speakers)}; val={len(args.val_speakers)})")

    # IMPORTANT: Don’t mutate args.epochs here anymore
    # (remove your old: if args.epochs <= start_epoch: args.epochs = start_epoch + 1)

    # Dataset setup
    ensure_dir(args.out_dir)
    print("[Data] indexing…")
    train_ds = GridFrames(args.data_root, args.train_speakers)
    val_ds   = GridFrames(args.data_root, args.val_speakers)
    print(f"train items: {len(train_ds)} | val items: {len(val_ds)}")

    pin_mem = (device.type == 'cuda')
    train_ld = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True,
                          num_workers=args.num_workers, collate_fn=pad_collate, pin_memory=pin_mem)
    val_ld   = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False,
                          num_workers=args.num_workers, collate_fn=pad_collate, pin_memory=pin_mem)

    stopper = EarlyStopping(patience=args.early_stop_patience, min_delta=args.min_delta)

    try:
        for epoch in range(start_epoch, max_epochs + 1):
            model.train()
            current_epoch = epoch
            pbar = tqdm(train_ld, desc=f"epoch {epoch}/{max_epochs}")  # show true target

            avg_loss = 0.0
            for X, Y, in_lens, tg_lens in pbar:
                X = X.to(device, non_blocking=True)
                Y = Y.to(device, non_blocking=True)
                in_lens = in_lens.to(device)
                tg_lens = tg_lens.to(device)

                opt.zero_grad(set_to_none=True)
                # autocast safely on either device
                with torch.amp.autocast(device_type=device_type, enabled=(args.amp and device_type=='cuda')):
                    logits = model(X)
                    logp = logits.log_softmax(-1)
                    loss = ctc(logp, Y, in_lens, tg_lens)

                scaler.scale(loss).backward()
                if args.grad_clip > 0:
                    scaler.unscale_(opt)
                    torch.nn.utils.clip_grad_norm_(model.parameters(), args.grad_clip)
                scaler.step(opt)
                scaler.update()

                avg_loss = 0.98 * avg_loss + 0.02 * loss.item() if avg_loss > 0 else loss.item()
                pbar.set_postfix(loss=f"{avg_loss:.3f}")

            # Validation
            val_cer, val_wer = evaluate(model, val_ld, device)
            print(f"[VAL] CER={val_cer:.3f} | WER={val_wer:.3f}")
            last_val_cer = val_cer
            sched.step(val_cer)

            # Save checkpoints
            meta = {
                'data_root': args.data_root,
                'train_speakers': args.train_speakers,
                'val_speakers': args.val_speakers,
            }
            ck_path = os.path.join(args.out_dir, f"epoch_{epoch:03d}_cer{val_cer:.3f}.pt")
            save_ckpt(model, opt, epoch, val_cer, ck_path, meta=meta, args=args)
            if val_cer < best_cer:
                best_cer = val_cer
                save_ckpt(model, opt, epoch, val_cer, os.path.join(args.out_dir, "best.pt"), meta=meta, args=args)
                print(f"[BEST] New best CER={best_cer:.3f}")
            else:
                print(f"[NO-IMPROVE] Best CER={best_cer:.3f}")

            if stopper.step(val_cer):
                print(f"[EARLY-STOP] No improvement for {stopper.num_bad_epochs} epochs. Stopping.")
                break

    except KeyboardInterrupt:
        paused_path = os.path.join(args.out_dir, 'paused.pt')
        print("[PAUSE] Ctrl+C detected — saving checkpoint to:", paused_path)
        meta = {
            'data_root': args.data_root,
            'train_speakers': args.train_speakers,
            'val_speakers': args.val_speakers,
        }
        save_ckpt(model, opt, max(current_epoch, 1), last_val_cer, paused_path, meta=meta, args=args)
        print("[PAUSE] Use --resume_ckpt", paused_path, "to continue training.")
        return

    print(f"[DONE] best CER: {best_cer:.3f}")


def evaluate(model: nn.Module, loader: DataLoader, device) -> Tuple[float, float]:
    model.eval()
    cer_list, wer_list = [] , []

    with torch.no_grad():
        for X, Y, in_lens, tg_lens in tqdm(loader, desc="[VAL]", leave=False):
            X = X.to(device, non_blocking=True)
            logits = model(X)   # (T,B,C)
            hyps = greedy_decode(logits)

            # rebuild references per batch item
            bsz = X.size(0)
            idx = 0
            refs = []
            for i in range(bsz):
                L = int(tg_lens[i].item())
                y_i = Y[idx:idx+L].cpu().numpy().tolist()
                refs.append(labels_to_text(y_i))
                idx += L

            for r, h in zip(refs, hyps):
                cer_list.append(cer(r, h))
                wer_list.append(wer(r, h))

    # Return averaged metrics
    return float(np.nanmean(cer_list)), float(np.nanmean(wer_list))


# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

import argparse


def parse_args():
    p = argparse.ArgumentParser(description="GRID Lip Reading CNN‑RNN + CTC")
    sub = p.add_subparsers(dest='cmd', required=True)

    # preprocess
    pp = sub.add_parser('preprocess', help='Extract mouth ROIs into frame folders')
    pp.add_argument('--grid_root', required=True)
    pp.add_argument('--out_root', required=True)
    pp.add_argument('--speakers', nargs='*', default=None)
    pp.add_argument('--fps', type=int, default=25)
    pp.add_argument('--out_size', type=int, default=96)
    pp.add_argument('--min_frames', type=int, default=48)
    pp.add_argument('--max_frames', type=int, default=80)
    pp.add_argument('--verbose', action='store_true')

    # train
    tr = sub.add_parser('train', help='Train the model')
    tr.add_argument('--data_root', required=True)
    tr.add_argument('--train_speakers', nargs='+', required=False)
    tr.add_argument('--val_speakers', nargs='+', required=False)
    tr.add_argument('--out_dir', default='runs/grid_ctc')
    tr.add_argument('--epochs', type=int, default=30)
    tr.add_argument('--batch_size', type=int, default=8)
    tr.add_argument('--num_workers', type=int, default=8)
    tr.add_argument('--lr', type=float, default=1e-3)
    tr.add_argument('--weight_decay', type=float, default=1e-4)
    tr.add_argument('--grad_clip', type=float, default=5.0)
    tr.add_argument('--amp', action='store_true')
    tr.add_argument('--gpus', type=int, default=1)
    tr.add_argument('--seed', type=int, default=1337)
    tr.add_argument('--early_stop_patience', type=int, default=40)
    tr.add_argument('--min_delta', type=float, default=0.0)
    tr.add_argument('--resume_ckpt', default=None)

    # test
    te = sub.add_parser('test', help='Evaluate + sample decode')
    te.add_argument('--data_root', required=True)
    te.add_argument('--val_speakers', nargs='+', required=True)
    te.add_argument('--ckpt', required=True)
    te.add_argument('--num_workers', type=int, default=4)
    te.add_argument('--batch_size', type=int, default=8)
    te.add_argument('--num_samples', type=int, default=8)

    return p.parse_args()


def main():
    args = parse_args()
    if args.cmd == 'preprocess':
        pa = PreprocessArgs(
            grid_root=args.grid_root,
            out_root=args.out_root,
            speakers=args.speakers or [],
            fps=args.fps,
            out_size=args.out_size,
            min_frames=args.min_frames,
            max_frames=args.max_frames,
            verbose=args.verbose,
        )
        preprocess_grid(pa)

    elif args.cmd == 'train':
        ta = TrainArgs(
            data_root=args.data_root,
            train_speakers=args.train_speakers,
            val_speakers=args.val_speakers,
            out_dir=args.out_dir,
            epochs=args.epochs,
            batch_size=args.batch_size,
            num_workers=args.num_workers,
            lr=args.lr,
            weight_decay=args.weight_decay,
            grad_clip=args.grad_clip,
            amp=args.amp,
            gpus=args.gpus,
            seed=args.seed,
            early_stop_patience=args.early_stop_patience,
            min_delta=args.min_delta, 
            resume_ckpt=args.resume_ckpt,
        )
        train_loop(ta)

    elif args.cmd == 'test':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        val_ds = GridFrames(args.data_root, args.val_speakers)
        val_ld = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False,
                            num_workers=args.num_workers, collate_fn=pad_collate)
        model = LipReadCTC(num_classes=NUM_CLASSES).to(device)
        load_ckpt(model, args.ckpt, map_location=device)
        cer_v, wer_v = evaluate(model, val_ld, device)
        print(f"[TEST] CER={cer_v:.3f} | WER={wer_v:.3f}")

        # sample decode
        model.eval()
        shown = 0
        with torch.no_grad():
            for X, Y, in_lens, tg_lens in val_ld:
                X = X.to(device)
                logits = model(X)
                hyps = greedy_decode(logits)
                # rebuild refs
                idx = 0
                refs = []
                for i in range(X.size(0)):
                    L = int(tg_lens[i].item())
                    y_i = Y[idx:idx+L].cpu().numpy().tolist()
                    refs.append(labels_to_text(y_i))
                    idx += L
                for r, h in zip(refs, hyps):
                    print("REF:", r)
                    print("HYP:", h)
                    print('-'*30)
                    shown += 1
                    if shown >= args.num_samples:
                        return
                    
    print(vars(args))

if __name__ == '__main__':
    main()