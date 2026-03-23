"""
Resident dictation helper for macOS.

Behavior:
  - stays idle under launchd
  - records only while active.state == "on"
  - transcribes the captured session when toggled off
  - copies the result to the clipboard and pastes into the focused app
"""
from __future__ import annotations

import collections
import logging
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Deque

import numpy as np
import sounddevice as sd

_fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
_stdout = logging.StreamHandler(sys.stdout)
_stdout.setFormatter(_fmt)
logging.basicConfig(level=logging.INFO, handlers=[_stdout])
log = logging.getLogger("ultra_dictation")

BASE_DIR = Path.home() / ".local" / "ultra_dictation"
CONFIG_PATH = Path.home() / ".config" / "ultra_dictation" / "config"
STATE_FILE = BASE_DIR / "active.state"

if CONFIG_PATH.exists():
    for line in CONFIG_PATH.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())

SAMPLERATE = 16_000
FRAME_SAMPLES = 512
CHANNELS = 1
MODEL = os.environ.get("ULTRA_DICTATION_MODEL", "mlx-community/whisper-large-v3-turbo")
INPUT_DEVICE = os.environ.get("ULTRA_DICTATION_INPUT_DEVICE", "").strip()
SESSION_BUFFER_FRAMES = int(os.environ.get("ULTRA_DICTATION_SESSION_BUFFER_FRAMES", "3000"))
SHUTDOWN_RMS_THRESHOLD = float(os.environ.get("ULTRA_DICTATION_SHUTDOWN_RMS_THRESHOLD", "0.01"))
NOTIFY = os.environ.get("ULTRA_DICTATION_NOTIFY", "0") == "1"
IDLE_POLL_SECONDS = 0.10

INITIAL_PROMPT = (
    "Python, NumPy, pandas, PyTorch, transformer, tokenizer, embedding, "
    "GitHub PR, code review, unit test, JSON, YAML, async, inference, latency."
)

_HALLUCINATION_RE = re.compile(
    r"^\s*[\(\[]|Thank you[\.\!]*\s*$|you$|^\s*$",
    re.IGNORECASE,
)
_STRIP_TOKENS = re.compile(r"\[.*?\]|\(.*?\)")


def _clean(text: str) -> str:
    text = _STRIP_TOKENS.sub("", text).strip()
    text = " ".join(text.split())
    if _HALLUCINATION_RE.search(text):
        return ""
    if len(text.split()) < 2 and len(text) < 6:
        return ""
    return text


_whisper_lock = threading.Lock()
_whisper_loaded = False


def _ensure_model() -> None:
    global _whisper_loaded
    with _whisper_lock:
        if not _whisper_loaded:
            log.info("Loading MLX Whisper model: %s", MODEL)
            import mlx_whisper  # noqa: F401

            _whisper_loaded = True
            log.info("Model ready")


def _audio_rms(audio: np.ndarray) -> float:
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim != 1 or audio.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(audio * audio)))


def _input_device_name(device_idx: int | None) -> str:
    if device_idx is None:
        default_input = sd.default.device[0]
        try:
            return str(sd.query_devices(default_input)["name"])
        except Exception:
            return f"default({default_input})"
    try:
        return str(sd.query_devices(device_idx)["name"])
    except Exception:
        return str(device_idx)


def _resolve_input_device() -> tuple[int | None, str]:
    if not INPUT_DEVICE:
        return None, _input_device_name(None)

    if INPUT_DEVICE.isdigit():
        idx = int(INPUT_DEVICE)
        return idx, _input_device_name(idx)

    matches: list[int] = []
    for idx, device in enumerate(sd.query_devices()):
        if device.get("max_input_channels", 0) > 0 and INPUT_DEVICE.lower() in str(device["name"]).lower():
            matches.append(idx)

    if matches:
        return matches[0], _input_device_name(matches[0])

    fallback = _input_device_name(None)
    log.warning("Input device %r not found; using default input %s", INPUT_DEVICE, fallback)
    return None, fallback


_transcribe_sem = threading.Semaphore(1)
_paste_queue: queue.Queue[str | None] = queue.Queue()


def transcribe(audio: np.ndarray) -> str:
    _ensure_model()
    import mlx_whisper

    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim != 1 or audio.size == 0:
        return ""

    with _transcribe_sem:
        t0 = time.perf_counter()
        result = mlx_whisper.transcribe(
            audio,
            path_or_hf_repo=MODEL,
            language="en",
            initial_prompt=INITIAL_PROMPT,
            without_timestamps=True,
        )
        dt = time.perf_counter() - t0
        text = _clean(result.get("text", ""))
        if text:
            log.info("transcribed (%.2fs): %s", dt, text)
        else:
            log.info("no usable speech (%.2fs)", dt)
        return text


def paste_text(text: str) -> None:
    if text:
        _paste_queue.put(text)


def _notify(subtitle: str, msg: str = "") -> None:
    cmd = (
        f'display notification "{msg}" with title "Ultra Dictation" '
        f'subtitle "{subtitle}"'
    )
    subprocess.run(["osascript", "-e", cmd], check=False)


def _paste_worker() -> None:
    while True:
        text = _paste_queue.get()
        if text is None:
            _paste_queue.task_done()
            break
        try:
            subprocess.run(["pbcopy"], input=text.encode(), check=True)
            subprocess.run(
                ["osascript", "-e", 'tell application "System Events" to keystroke "v" using command down'],
                check=False,
            )
            if NOTIFY:
                _notify("Pasted", text[:80])
        except Exception as exc:
            log.warning("paste failed: %s", exc)
        finally:
            _paste_queue.task_done()


def _desired_active() -> bool:
    try:
        return STATE_FILE.read_text().strip().lower() == "on"
    except FileNotFoundError:
        return False


def _ensure_state_file() -> None:
    BASE_DIR.mkdir(parents=True, exist_ok=True)
    if not STATE_FILE.exists():
        STATE_FILE.write_text("off\n")


audio_queue: queue.Queue[np.ndarray] = queue.Queue()
stop_requested = False


def _drain_audio_queue() -> None:
    while True:
        try:
            audio_queue.get_nowait()
        except queue.Empty:
            break


def _audio_callback(indata, frames, time_info, status) -> None:
    if status:
        log.debug("sounddevice: %s", status)
    audio_queue.put(indata.copy().reshape(-1))


def main() -> None:
    global stop_requested

    def _handle_signal(signum, frame) -> None:
        global stop_requested
        log.info("Signal %d received — shutting down", signum)
        stop_requested = True

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    _ensure_state_file()
    paste_thread = threading.Thread(target=_paste_worker, daemon=True)
    paste_thread.start()
    threading.Thread(target=_ensure_model, daemon=True).start()

    log.info("Dictation helper idle — model=%s", MODEL)

    while not stop_requested:
        if not _desired_active():
            time.sleep(IDLE_POLL_SECONDS)
            continue

        _drain_audio_queue()
        input_device, input_device_name = _resolve_input_device()
        session_audio: Deque[np.ndarray] = collections.deque(maxlen=SESSION_BUFFER_FRAMES)
        log.info("Dictation active — recording session on input=%s", input_device_name)

        with sd.InputStream(
            samplerate=SAMPLERATE,
            blocksize=FRAME_SAMPLES,
            channels=CHANNELS,
            device=input_device,
            dtype="float32",
            callback=_audio_callback,
        ):
            while not stop_requested and _desired_active():
                try:
                    chunk = audio_queue.get(timeout=0.25)
                except queue.Empty:
                    continue

                if chunk.size < FRAME_SAMPLES:
                    chunk = np.pad(chunk, (0, FRAME_SAMPLES - chunk.size))
                elif chunk.size > FRAME_SAMPLES:
                    chunk = chunk[:FRAME_SAMPLES]

                session_audio.append(chunk)

        if session_audio:
            audio = np.concatenate(session_audio)
            rms = _audio_rms(audio)
            if rms >= SHUTDOWN_RMS_THRESHOLD:
                log.info(
                    "Transcribing audio synchronously on session-stop (samples=%d rms=%.4f)",
                    audio.size, rms,
                )
                paste_text(transcribe(audio))
                log.info("Waiting for final pasted text to flush")
                _paste_queue.join()
            else:
                log.info(
                    "Skipping session transcription due to low RMS (samples=%d rms=%.4f)",
                    audio.size, rms,
                )
        else:
            log.info("No session audio captured before stop")

        _drain_audio_queue()
        if not stop_requested:
            log.info("Dictation helper idle")

    _paste_queue.put(None)
    paste_thread.join(timeout=2)
    log.info("Dictation engine stopped")


if __name__ == "__main__":
    main()
