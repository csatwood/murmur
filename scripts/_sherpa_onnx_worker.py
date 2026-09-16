#!/usr/bin/env python3
"""Runs a k2-fsa sherpa-onnx offline recognizer (SenseVoice small, Alibaba's
Apache-2.0 multilingual model) over one or more audio files. Invoked by
benchmark_engines.py as a subprocess in a separate venv — see that script's
module docstring for setup. Not part of Murmur; this only exists to screen
accuracy before deciding whether it's worth a real Swift engine.

Downloads and caches the model archive under scripts/.sherpa_models/ on
first run (~450MB compressed).

Prints one line per input: `TEXT: <transcription><TAB>LATENCY: <seconds>`
"""
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

import sherpa_onnx
import soundfile as sf

MODEL_NAME = "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
MODEL_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
    f"{MODEL_NAME}.tar.bz2"
)
MODELS_DIR = Path(__file__).resolve().parent / ".sherpa_models"


def ensure_model() -> Path:
    model_dir = MODELS_DIR / MODEL_NAME
    if model_dir.exists():
        return model_dir
    MODELS_DIR.mkdir(exist_ok=True)
    archive = MODELS_DIR / f"{MODEL_NAME}.tar.bz2"
    print(f"  downloading {MODEL_NAME} from {MODEL_URL} ...", file=sys.stderr)
    urllib.request.urlretrieve(MODEL_URL, archive)
    with tarfile.open(archive) as tar:
        tar.extractall(MODELS_DIR)
    archive.unlink()
    return model_dir


def main():
    audio_paths = sys.argv[1:]
    if not audio_paths:
        raise SystemExit("usage: _sherpa_onnx_worker.py AUDIO_FILE...")

    model_dir = ensure_model()
    recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=str(model_dir / "model.int8.onnx"),
        tokens=str(model_dir / "tokens.txt"),
        num_threads=4,
        language="en",
        use_itn=True,
    )

    for path in audio_paths:
        started = time.monotonic()
        audio, sample_rate = sf.read(path, dtype="float32", always_2d=False)
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, audio)
        recognizer.decode_stream(stream)
        elapsed = time.monotonic() - started
        text = stream.result.text.strip().replace("\n", " ").replace("\t", " ")
        print(f"TEXT: {text}\tLATENCY: {elapsed:.4f}")


if __name__ == "__main__":
    main()
