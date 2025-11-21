"""
verify_lombard_labels.py
------------------------
Checks all Lombard GRID preprocessed folders (e.g., data_lombard_processed/)
and reports how many label.txt files contain real words versus phone-like strings.

Usage:
  python scripts/verify_lombard_labels.py --root data_lombard_processed
"""

from pathlib import Path
import re
import argparse
from tqdm import tqdm

# Patterns to detect phone-like tokens (e.g. "b_B", "iy_E", "th_B")
PHONE_PAT = re.compile(r"\b[a-z]{1,3}_[BEI]\b", re.IGNORECASE)
WORD_PAT  = re.compile(r"[a-zA-Z]+")

def is_phone_string(txt: str) -> bool:
    """Heuristically classify as phone-based if it contains many phone-like tokens."""
    phones = PHONE_PAT.findall(txt)
    words  = WORD_PAT.findall(txt)
    if len(phones) > len(words) and len(phones) > 2:
        return True
    return False

def main(root: str):
    root = Path(root)
    if not root.exists():
        raise FileNotFoundError(root)

    total, phones, good = 0, 0, 0
    bad_examples, good_examples = [], []

    for lbl_path in tqdm(list(root.rglob("label.txt"))):
        total += 1
        txt = lbl_path.read_text(encoding="utf-8", errors="ignore").strip().lower()
        if not txt:
            continue
        if is_phone_string(txt):
            phones += 1
            if len(bad_examples) < 10:
                bad_examples.append((lbl_path.parent.name, txt))
        else:
            good += 1
            if len(good_examples) < 10:
                good_examples.append((lbl_path.parent.name, txt))

    print(f"\n[REPORT] Checked {total} label.txt files")
    print(f" Real word transcripts : {good}")
    print(f" Likely phone-based    : {phones}")
    print(f"  → {(good / max(1, total)) * 100:.1f}% appear valid\n")

    if bad_examples:
        print("Examples of likely phone-based labels:")
        for name, txt in bad_examples:
            print(f"  {name:20s} : {txt}")

    if good_examples:
        print("\nExamples of likely valid labels:")
        for name, txt in good_examples:
            print(f"  {name:20s} : {txt}")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="Root of preprocessed Lombard dataset")
    args = ap.parse_args()
    main(args.root)
