#!/usr/bin/env python3
"""Benchmarks Murmur's recognition engines against each other on the same
audio, following the accuracy/latency/memory/robustness dimensions from the
"Open-Source Speech-to-Text Landscape" report's benchmarking-responsibly
section.

Test audio is synthetic (macOS `say`), so this measures "can the engine
transcribe clear, noise-free speech" — not real-world accuracy under accent,
noise, or far-field conditions. Treat it as a first screening pass, the same
caution the report itself gives about leaderboard numbers: useful for
narrowing candidates, not for a final call.

Usage:
    ./scripts/benchmark_engines.py [--app path/to/Murmur.app]
"""
import argparse
import re
import subprocess
import time
from pathlib import Path
from typing import List, Optional

TEST_SENTENCES = [
    "Testing the new Parakeet speech recognition engine for Murmur.",
    "Please schedule a follow-up meeting with the design team for "
    "Thursday afternoon, and send everyone the updated agenda beforehand.",
    "The quarterly revenue increased by twelve percent, driven mostly by "
    "the enterprise segment and a handful of renewals we almost lost.",
]

ENGINE_CONFIGS = [
    ("apple", None),
    ("whisper", "small"),
    ("whispercpp", "small"),
    ("parakeet", "v3"),
]

WORD_RE = re.compile(r"[a-z0-9']+")


def normalize(text: str) -> List[str]:
    return WORD_RE.findall(text.lower())


def word_error_rate(reference: str, hypothesis: str) -> float:
    ref = normalize(reference)
    hyp = normalize(hypothesis)
    if not ref:
        return 0.0 if not hyp else 1.0
    # Standard Levenshtein edit distance at the word level.
    dp = list(range(len(hyp) + 1))
    for i in range(1, len(ref) + 1):
        prev, dp[0] = dp[0], i
        for j in range(1, len(hyp) + 1):
            cur = dp[j]
            dp[j] = prev if ref[i - 1] == hyp[j - 1] else 1 + min(prev, dp[j], dp[j - 1])
            prev = cur
    return dp[len(hyp)] / len(ref)


def run_once(binary: Path, audio_file: Path, engine: str, model: Optional[str]):
    cmd = [str(binary), "--transcribe", str(audio_file), "--engine", engine]
    if model:
        cmd += ["--whisper-model", model]
    started = time.monotonic()
    result = subprocess.run(
        ["/usr/bin/time", "-l"] + cmd,
        capture_output=True, text=True, timeout=180)
    elapsed = time.monotonic() - started

    formatted = ""
    for line in result.stdout.splitlines():
        if line.startswith("FORMATTED: "):
            formatted = line[len("FORMATTED: "):]
    peak_rss_mb = None
    match = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
    if match:
        peak_rss_mb = int(match.group(1)) / (1024 * 1024)
    return formatted, elapsed, peak_rss_mb


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--app", default="build/Murmur.app",
        help="Path to the built Murmur.app (default: build/Murmur.app)")
    args = parser.parse_args()

    binary = Path(args.app) / "Contents/MacOS/Murmur"
    if not binary.exists():
        raise SystemExit(f"Binary not found at {binary} — run make_app.sh first")

    tmp_dir = Path("/tmp/murmur_benchmark")
    tmp_dir.mkdir(exist_ok=True)
    audio_files = []
    for i, sentence in enumerate(TEST_SENTENCES):
        f = tmp_dir / f"sentence_{i}.aiff"
        # Explicit voice: a first run with no `-v` (system default) made
        # every engine — including Apple's own — mangle the same sentence
        # the same way, which points at the input audio rather than any one
        # engine. This machine's system locale isn't US English, so the
        # unnamed default voice is likely a non-English or novelty voice.
        subprocess.run(["say", "-v", "Samantha", "-o", str(f), sentence], check=True)
        audio_files.append(f)

    rows = []
    for engine, model in ENGINE_CONFIGS:
        label = f"{engine}" + (f"/{model}" if model else "")
        print(f"\n=== {label} ===")

        # Warm up first (may trigger a one-time model download) so the
        # timed runs below measure steady-state speed, not a cold download
        # that would otherwise skew whichever sentence happened to run first.
        print("  warming up (downloads the model on first run)...")
        cmd = [str(binary), "--transcribe", str(audio_files[0]), "--engine", engine]
        if model:
            cmd += ["--whisper-model", model]
        subprocess.run(cmd, capture_output=True, text=True, timeout=600)

        wers, latencies, rss_values = [], [], []
        for sentence, audio_file in zip(TEST_SENTENCES, audio_files):
            formatted, elapsed, peak_rss_mb = run_once(binary, audio_file, engine, model)
            wer = word_error_rate(sentence, formatted)
            wers.append(wer)
            latencies.append(elapsed)
            if peak_rss_mb is not None:
                rss_values.append(peak_rss_mb)
            print(f"  {elapsed:5.2f}s  WER {wer*100:5.1f}%  -> {formatted!r}")
        rows.append({
            "label": label,
            "avg_wer": sum(wers) / len(wers) * 100,
            "avg_latency": sum(latencies) / len(latencies),
            "avg_rss_mb": sum(rss_values) / len(rss_values) if rss_values else None,
        })

    print("\n" + "=" * 72)
    print(f"{'Engine':<16}{'Avg WER':>10}{'Avg latency':>14}{'Avg peak RSS':>16}")
    print("-" * 72)
    for row in rows:
        rss = f"{row['avg_rss_mb']:.0f} MB" if row["avg_rss_mb"] else "n/a"
        print(f"{row['label']:<16}{row['avg_wer']:>9.1f}%{row['avg_latency']:>13.2f}s{rss:>16}")


if __name__ == "__main__":
    main()
