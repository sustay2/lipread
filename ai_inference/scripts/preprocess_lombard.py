"""
Preprocess Lombard GRID (front + side) into the same frame+label format lipread_grid.py expects.

Input layout:
  lombardgrid/
    front/         # flat video files (e.g., s2_l_bbim3a.mov)
    side/
    alignment/     # JSON phone alignments: { "<utt_id>": [ {duration,offset,phone}, ... ] }

Output layout:
  out_root/
    s2_front/
      s2_l_bbim3a/
        frame_0000.png ... frame_00TT.png
        label.txt
    s2_side/
      s2_l_bbim3a/
        ...

Usage:
  python scripts/preprocess_lombard.py \
    --lombard_root lombardgrid \
    --out_root data_lombard_processed \
    --tracks both \
    --fps 25 --out_size 96 --min_frames 48 --max_frames 80 \
    --skip_unk
"""

from __future__ import annotations
import os, re, json, glob, csv, traceback, subprocess, tempfile
from dataclasses import dataclass
from typing import List, Optional, Dict, Tuple
from pathlib import Path

import cv2
import numpy as np
from tqdm import tqdm

try:
    import mediapipe as mp
    MP_OK = True
except Exception:
    MP_OK = False

# --------- args ---------
@dataclass
class Args:
    lombard_root: str
    out_root: str
    tracks: str = "both"
    fps: int = 25
    out_size: int = 96
    min_frames: int = 48
    max_frames: int = 80
    verbose: bool = False
    skip_unk: bool = False
    lexicon_path: Optional[str] = None


# --------- utils ---------
def ensure_dir(p: str | Path):
    Path(p).mkdir(parents=True, exist_ok=True)

def _speaker_from_name(stem: str) -> str:
    # Expect names like 's2_l_bbim3a' → 's2'
    m = re.match(r"(s\d+)_", stem.lower())
    return m.group(1) if m else "s_unk"

# --------- robust video reader ---------
def _read_frames_resampled(video_path: Path, target_fps: int) -> List[np.ndarray]:
    """
    Robust reader:
      1) Try decord (if available)
      2) Try OpenCV
      3) Remux or transcode via ffmpeg and retry OpenCV
    """
    frames: List[np.ndarray] = []

    # 1) Try decord if available
    try:
        import decord
        from decord import VideoReader
        from decord import cpu as decpu
        vr = VideoReader(str(video_path), ctx=decpu(0))
        src_fps = float(vr.get_avg_fps() or target_fps)
        step = max(1, int(round(src_fps / target_fps)))
        for i in range(0, len(vr), step):
            fr = vr[i].asnumpy()[:, :, ::-1]  # RGB->BGR
            frames.append(fr)
        if frames:
            return frames
    except Exception:
        pass  # fall back

    # helper: OpenCV attempt
    def _read_cv2(p: Path, tgt_fps: int) -> List[np.ndarray]:
        cap = cv2.VideoCapture(str(p))
        if not cap.isOpened():
            return []
        src_fps = cap.get(cv2.CAP_PROP_FPS) or tgt_fps
        if src_fps <= 0: src_fps = tgt_fps
        step = max(1, int(round(src_fps / tgt_fps)))
        idx = 0
        out: List[np.ndarray] = []
        while True:
            ok, img = cap.read()
            if not ok:
                break
            if idx % step == 0:
                out.append(img)
            idx += 1
        cap.release()
        return out

    # 2) Try OpenCV directly
    frames = _read_cv2(video_path, target_fps)
    if frames:
        return frames

    # 3) Remux with ffmpeg, then transcode if needed
    tmp_dir = Path(tempfile.gettempdir())
    tmp_mp4 = tmp_dir / f"{video_path.stem}_remux.mp4"
    try:
        cmd = [
            "ffmpeg", "-y", "-v", "warning", "-hide_banner",
            "-ignore_editlist", "1",
            "-i", str(video_path),
            "-c", "copy",
            "-movflags", "+faststart",
            str(tmp_mp4)
        ]
        subprocess.run(cmd, check=True)
        frames = _read_cv2(tmp_mp4, target_fps)
        if frames:
            return frames

        cmd = [
            "ffmpeg", "-y", "-v", "warning", "-hide_banner",
            "-i", str(video_path),
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-preset", "veryfast", "-crf", "23",
            "-an", "-movflags", "+faststart",
            str(tmp_mp4)
        ]
        subprocess.run(cmd, check=True)
        frames = _read_cv2(tmp_mp4, target_fps)
        if frames:
            return frames
    except Exception as e:
        print(f"[WARN] ffmpeg remux/transcode failed for {video_path}: {e}")

    raise RuntimeError(f"Failed to decode frames from {video_path}. Try manual ffmpeg remux/transcode.")

# --------- mouth ROI ---------
def _extract_mouth_roi(frame_bgr: np.ndarray, face_mesh, out_size: int) -> np.ndarray:
    h, w = frame_bgr.shape[:2]
    if face_mesh is not None:
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        res = face_mesh.process(rgb)
        if res.multi_face_landmarks:
            lm = res.multi_face_landmarks[0]
            pts = np.array([(p.x * w, p.y * h) for p in lm.landmark])
            mouth_idx = list(range(61, 88))  # outer lips approx
            mpts = pts[mouth_idx]
            x, y, ww, hh = cv2.boundingRect(mpts.astype(np.int32))
            cx = x + ww/2.0; cy = y + hh/2.0
            sz = int(max(ww, hh) * 2.0)
            x0 = max(0, int(cx - sz//2)); y0 = max(0, int(cy - sz//2))
            x1 = min(w, x0 + sz);        y1 = min(h, y0 + sz)
            crop = frame_bgr[y0:y1, x0:x1]
            if crop.size == 0: crop = frame_bgr
        else:
            sz = min(h, w); y0 = (h - sz)//2; x0 = (w - sz)//2
            crop = frame_bgr[y0:y0+sz, x0:x0+sz]
    else:
        sz = min(h, w); y0 = (h - sz)//2; x0 = (w - sz)//2
        crop = frame_bgr[y0:y0+sz, x0:x0+sz]

    crop = cv2.resize(crop, (out_size, out_size), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    return gray

def _temporal_norm(frames: List[np.ndarray], min_f: int, max_f: int) -> List[np.ndarray]:
    T = len(frames)
    if T < min_f:
        frames = frames + [frames[-1]] * (min_f - T)
    elif T > max_f:
        s = (T - max_f)//2
        frames = frames[s:s+max_f]
    return frames

# --------- lexicon & alignment handling ---------
_STRESS_RE = re.compile(r"\d+$")
def _strip_suffix_tag(p: str) -> Tuple[str, str]:
    p = p.strip()
    tag = ""
    if "_" in p:
        base, tag = p.rsplit("_", 1)
    else:
        base = p
    base = _STRESS_RE.sub("", base.lower())
    return base, tag.upper()

def _is_sil(p: str) -> bool:
    return p.strip().lower().startswith("sil")

def _load_reverse_lexicon(custom_path: Path | None) -> dict:
    rev = {}
    if custom_path and custom_path.is_file():
        try:
            with open(custom_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    rev.update({ " ".join(_STRESS_RE.sub("", t.lower()) for t in k.split()): str(v).lower()
                                for k, v in data.items() })
        except Exception as e:
            print(f"[WARN] failed to load lexicon {custom_path}: {e}")
    return rev

def _segment_phones_greedy(phones: list[str], rev_lex: dict) -> list[list[str]]:
    """Greedy longest-match segmentation using the reverse lexicon keys."""
    i, n = 0, len(phones)
    out = []
    lens = sorted({len(k.split()) for k in rev_lex.keys()}, reverse=True) or [1]
    while i < n:
        matched = None
        for L in lens:
            if i + L > n: continue
            cand = " ".join(phones[i:i+L])
            if cand in rev_lex:
                matched = phones[i:i+L]
                i += L
                break
        if matched is None:
            matched = [phones[i]]
            i += 1
        out.append(matched)
    return out

def _phones_to_words(phones_with_tags: list[str], rev_lex: dict) -> List[str]:
    """Group phones into words via tags; if no tags, segment by lexicon between silences."""
    has_tags = any(("_" in p and p.rsplit("_",1)[-1].upper() in {"B","I","E"}) for p in phones_with_tags)

    # split by silences into chunks
    chunks: list[list[str]] = []
    cur: list[str] = []
    for pt in phones_with_tags:
        if not pt:
            continue
        if _is_sil(pt):
            if cur:
                chunks.append(cur); cur = []
            continue
        cur.append(pt)
    if cur: chunks.append(cur)

    words: List[str] = []
    for ch in chunks:
        if has_tags:
            buf: List[str] = []
            def flush_buf():
                nonlocal buf
                if buf:
                    key = " ".join(buf)
                    words.append(rev_lex.get(key, "<unk>"))
                    buf = []
            for pt in ch:
                base, tag = _strip_suffix_tag(pt)
                if tag == "B":
                    flush_buf()
                    buf.append(base)
                elif tag == "I":
                    if not buf: buf.append(base)
                    else: buf.append(base)
                elif tag == "E":
                    if not buf: buf.append(base)
                    else: buf.append(base)
                    flush_buf()
                else:
                    # no tag inside a tagged chunk → treat as standalone word
                    flush_buf()
                    words.append(rev_lex.get(base, "<unk>"))
            flush_buf()
        else:
            bases = [_strip_suffix_tag(p)[0] for p in ch]
            seg = _segment_phones_greedy(bases, rev_lex)
            for wph in seg:
                key = " ".join(wph)
                words.append(rev_lex.get(key, "<unk>"))

    # optional clean-up: trim leading/trailing <unk>
    while words and words[0] == "<unk>": words.pop(0)
    while words and words[-1] == "<unk>": words.pop()
    return words

def _read_alignment_text(aln_json_path: Path, lexicon_path: Optional[Path], verbose: bool=False) -> str:
    """
    Parse Lombard JSON -> phones -> words using lexicon.
    Returns "" if parsing fails (caller decides fallback or skip).
    """
    # Resolve lexicon location
    if lexicon_path is None:
        # default: lombard_root/lombard_lexicon.json
        default_path = aln_json_path.parent.parent / "lombard_lexicon.json"
        lexicon_path = default_path

    rev_lex = _load_reverse_lexicon(lexicon_path)
    if not rev_lex and verbose:
        print(f"[WARN] Lexicon not loaded or empty: {lexicon_path}")

    try:
        with open(aln_json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        # direct transcript/words/tokens as a fast path
        if isinstance(data, dict):
            if isinstance(data.get("transcript"), str):
                txt = data["transcript"].strip().lower()
                if verbose:
                    print(f"[INFO] Using direct transcript for {aln_json_path.name}: {txt}")
                return txt
            if isinstance(data.get("words"), list):
                toks = []
                for w in data["words"]:
                    if isinstance(w, dict):
                        tok = w.get("word") or w.get("label") or w.get("text")
                        if tok: toks.append(str(tok))
                    elif isinstance(w, str):
                        toks.append(w)
                if toks:
                    txt = " ".join(toks).strip().lower()
                    if verbose:
                        print(f"[INFO] Using words[] transcript for {aln_json_path.name}: {txt}")
                    return txt
            if isinstance(data.get("tokens"), list):
                toks = [str(t) for t in data["tokens"]]
                if toks:
                    txt = " ".join(toks).strip().lower()
                    if verbose:
                        print(f"[INFO] Using tokens[] transcript for {aln_json_path.name}: {txt}")
                    return txt

        # Lombard 1-key JSON with phone entries
        if isinstance(data, dict) and len(data) == 1:
            (_, entries), = data.items()
            if isinstance(entries, list) and entries and isinstance(entries[0], dict) and "phone" in entries[0]:
                phones_with_tags = [str(e.get("phone", "")).strip() for e in entries]
                words = _phones_to_words(phones_with_tags, rev_lex)
                txt = " ".join(words).strip()
                if verbose:
                    print(f"[INFO] Reconstructed transcript for {aln_json_path.name}: {txt}")
                return txt

        if verbose:
            print(f"[WARN] Unexpected alignment JSON shape: {aln_json_path}")
    except Exception as e:
        if verbose:
            print(f"[WARN] Failed to parse {aln_json_path}: {e}")

    return ""

# --------- main processing ---------
def _process_track(args: Args, track: str, face_mesh, failed_paths: List[str]):
    root = Path(args.lombard_root)
    vroot = root / track
    aroot = root / "alignment"
    assert vroot.is_dir(), f"Track folder not found: {vroot}"
    assert aroot.is_dir(), f"Alignment folder not found: {aroot}"

    # gather videos (case-insensitive)
    vids = []
    for ext in ("*.mov","*.MOV","*.mp4","*.MP4","*.mpg","*.MPG","*.m4v","*.M4V","*.3gp","*.3GP","*.3g2","*.3G2","*.mj2","*.MJ2"):
        vids.extend(glob.glob(str(vroot / ext)))
    vids = sorted(vids)
    print(f"[INFO] Track='{track}', videos={len(vids)}")

    for vf in tqdm(vids, desc=f"Lombard-{track}"):
        out_spk = None
        try:
            vp = Path(vf)
            stem = vp.stem                     # e.g., s2_l_bbim3a
            spk = _speaker_from_name(stem)     # e.g., s2
            spk_variant = f"{spk}_{track}"     # e.g., s2_front or s2_side

            out_spk = Path(args.out_root) / spk_variant / stem
            if out_spk.is_dir():
                # already processed
                continue
            ensure_dir(out_spk)

            # alignment json with same stem
            aln = aroot / f"{stem}.json"
            transcript = ""
            if aln.is_file():
                lexp = Path(args.lexicon_path) if args.lexicon_path else None
                transcript = _read_alignment_text(aln, lexp, verbose=args.verbose)
            else:
                if args.verbose:
                    print(f"[WARN] Alignment not found for {stem}: {aln}")

            if not transcript:
                if args.skip_unk:
                    if args.verbose:
                        print(f"[SKIP] No transcript reconstructed for {stem} (skip_unk on)")
                    for p in out_spk.glob("*"):
                        p.unlink(missing_ok=True)
                    out_spk.rmdir()
                    continue
                else:
                    if args.verbose:
                        print(f"[FALLBACK] Using stem as transcript for {stem}")
                    transcript = stem

            # decode & resample
            frames_raw = _read_frames_resampled(vp, args.fps)
            if not frames_raw:
                raise RuntimeError("No frames decoded after robust read")

            # mouth crops → gray
            gray_seq = []
            for fr in frames_raw:
                g = _extract_mouth_roi(fr, face_mesh, out_size=args.out_size)
                gray_seq.append(g)

            # temporal normalize
            gray_seq = _temporal_norm(gray_seq, args.min_frames, args.max_frames)
            if not gray_seq:
                raise RuntimeError("Empty gray sequence after temporal norm")

            # Optionally skip examples with <unk> tokens
            if args.skip_unk and "<unk>" in transcript.split():
                # clean and skip
                for p in out_spk.glob("*"):
                    p.unlink(missing_ok=True)
                out_spk.rmdir()
                if args.verbose:
                    print(f"[SKIP-UNK] {stem} ({track}) -> {transcript}")
                continue

            # write frames + label
            for i, g in enumerate(gray_seq):
                cv2.imwrite(str(out_spk / f"frame_{i:04d}.png"), g)
            with open(out_spk / "label.txt", "w", encoding="utf-8") as f:
                f.write(transcript.strip() + "\n")

        except Exception as e:
            failed_paths.append(vf)
            print(f"[SKIP] {vf}: {e}")
            if args.verbose:
                traceback.print_exc(limit=1)
            # clean any partially created utterance dir
            try:
                if out_spk and out_spk.is_dir():
                    for p in out_spk.glob("*"):
                        p.unlink(missing_ok=True)
                    out_spk.rmdir()
            except Exception:
                pass
            continue

def preprocess_lombard(args: Args):
    root = Path(args.lombard_root)
    aroot = root / "alignment"
    assert aroot.is_dir(), f"Alignment folder not found: {aroot}"

    ensure_dir(args.out_root)

    # MediaPipe FaceMesh
    if MP_OK:
        face_mesh = mp.solutions.face_mesh.FaceMesh(static_image_mode=False, refine_landmarks=True)
    else:
        face_mesh = None

    failed_paths: List[str] = []

    tracks_to_do = []
    if args.tracks == "both":
        tracks_to_do = ["front", "side"]
    elif args.tracks in ("front", "side"):
        tracks_to_do = [args.tracks]
    else:
        raise ValueError("--tracks must be 'front', 'side', or 'both'")

    for trk in tracks_to_do:
        _process_track(args, trk, face_mesh, failed_paths)

    if face_mesh:
        face_mesh.close()

    # write failure log
    if failed_paths:
        log_dir = Path(args.out_root) / "_logs"
        ensure_dir(log_dir)
        log_path = log_dir / f"failed_{args.tracks}.txt"
        with open(log_path, "w", encoding="utf-8") as f:
            for p in failed_paths:
                f.write(str(p) + "\n")
        print(f"[WARN] {len(failed_paths)} files skipped. See: {log_path}")

    print("✅ Lombard preprocess complete (merged front/side into speaker-track folders).")

# --------- cli ---------
if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--lombard_root", required=True)
    ap.add_argument("--out_root", required=True)
    ap.add_argument("--lexicon_path", default=None,
                help="Path to lombard_lexicon.json. If omitted, defaults to <lombard_root>/lombard_lexicon.json")
    ap.add_argument("--tracks", choices=["front","side","both"], default="both",
                    help="Which tracks to process and merge into out_root")
    ap.add_argument("--fps", type=int, default=25)
    ap.add_argument("--out_size", type=int, default=96)
    ap.add_argument("--min_frames", type=int, default=48)
    ap.add_argument("--max_frames", type=int, default=80)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--skip_unk", action="store_true",
                    help="Skip utterances whose reconstructed transcript contains <unk>")
    args = ap.parse_args()
    preprocess_lombard(Args(**vars(args)))
