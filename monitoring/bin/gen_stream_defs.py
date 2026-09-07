#!/usr/bin/env python3
"""gen_stream_defs.py — regenerate the LIVE block of stream_defs.py.

Source of truth: the deployed EA bundle's *.set files
(e.g. pioneer-qf STRATEGIES/PHANTOM/EA/sets/v16-accelerated-cent/).
Short banner tags (--tag) are an EA convention verified against live
MQL5 banners; they live in TAG_BY_MAGIC below, NOT in the .set files.

Usage:
  gen_stream_defs.py --bundle-dir <dir> --trees <N> --label <name> [--frozen-legacy]

Only the LIVE block is rewritten. LEGACY_* blocks are frozen history.
"""
import argparse
import glob
import os
import re
import sys

# Banner short-tags observed in live MQL5 logs (V9|<tag>|<TF>|<magic2>).
TAG_BY_MAGIC = {
    992101: "asia", 992102: "pbbb", 992103: "sqbd", 992104: "sqh1",
    992105: "ny", 992106: "asia", 992107: "lon", 992108: "comp",
    992109: "mon",
}

SHORT_BASE = {"BTCUSDc": "BTC", "GBPJPYc": "GBP", "XAGUSDc": "XAG",
              "XAUUSDc": "XAU"}


def parse_set(path):
    kv, atom_full = {}, None
    m = re.search(r"MetaSystemV9_(\w+?)_(M\d+)_(.+)\.set$",
                  os.path.basename(path))
    if m:
        atom_full = m.group(3)
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
    tf_min = int(kv.get("ExpectedTimeframeMinutes", "15"))
    return {
        "magic": int(kv["MagicNumber"]),
        "symbol": m.group(1) if m else "?",
        "tf": f"M{tf_min // 60}" if tf_min % 60 == 0 else f"M{tf_min}",
        "atom": atom_full or "?",
        "threshold": float(kv.get("ScoreThreshold", "0")),
        "tp_r": float(kv.get("TP_R", "0")),
        "sl_atr": float(kv.get("SL_ATR", "0")),
        "risk_pct": float(kv.get("RiskPct", "0")),
        "atom_code": int(kv.get("AtomCode", "-1")),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle-dir", required=True)
    ap.add_argument("--trees", type=int, required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--deployed-utc", required=True)
    args = ap.parse_args()

    streams = []
    for path in sorted(glob.glob(os.path.join(args.bundle_dir, "*.set"))):
        s = parse_set(path)
        tag = TAG_BY_MAGIC.get(s["magic"], "?")
        base = SHORT_BASE.get(s["symbol"],
                              s["symbol"].replace("c", ""))
        s["tag"] = tag
        s["label"] = f"{base} {s['tf']} {tag}"
        streams.append(s)
    streams.sort(key=lambda s: s["magic"])
    assert streams, f"no .set files in {args.bundle_dir}"

    out = []
    out.append(f"# ── LIVE (generated {args.deployed_utc} — DO NOT HAND-EDIT) ──")
    out.append(f"# Source: {args.label} bundle (*.set). Regenerate with:")
    out.append(f"#   gen_stream_defs.py --bundle-dir <dir> --trees {args.trees}"
               f" --label {args.label} --deployed-utc <ts>")
    out.append(f'DEPLOY_LABEL = "{args.label}"')
    out.append(f'DEPLOYED_UTC = "{args.deployed_utc}"')
    out.append(f"MODEL_TREES = {args.trees}")
    out.append("LIVE_STREAMS = {")
    for s in streams:
        out.append(
            f"    {s['magic']}: {{\"symbol\": \"{s['symbol']}\", "
            f"\"tf\": \"{s['tf']}\", \"atom\": \"{s['atom']}\", "
            f"\"tag\": \"{s['tag']}\", \"label\": \"{s['label']}\", "
            f"\"threshold\": {s['threshold']!r}, \"tp_r\": {s['tp_r']!r}, "
            f"\"sl_atr\": {s['sl_atr']!r}, \"risk_pct\": {s['risk_pct']!r}, "
            f"\"atom_code\": {s['atom_code']}}},")
    out.append("}")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
