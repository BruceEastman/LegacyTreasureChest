"""Generate synthetic provenance recordings for audio cases using macOS `say` + `afconvert`.

  python3 -I harness/make_synthetic_audio.py suites/core_v1/suite.json

Writes each case's `audio` path (under ai_eval/generated/, which Git ignores).
m4a is AAC in an MPEG-4 container, matching what the iOS app records and sends as audio/mp4.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import load_suite  # noqa: E402

FORMATS = {
    "m4a": ["-f", "m4af", "-d", "aac"],
    "wav": ["-f", "WAVE", "-d", "LEI16@16000"],
}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    suite = load_suite(Path(sys.argv[1]))
    voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    for c in suite["cases"]:
        syn = c.get("synthetic")
        if c["type"] != "audio" or not syn:
            continue
        out = Path(c["_audio_path"])
        out.parent.mkdir(parents=True, exist_ok=True)
        voice = syn.get("voice")
        voice_args = ["-v", voice] if voice and voice in voices else []
        with tempfile.TemporaryDirectory() as td:
            aiff = Path(td) / "speech.aiff"
            subprocess.run(["say", *voice_args, "-o", str(aiff), syn["script"]], check=True)
            subprocess.run(["afconvert", *FORMATS[syn.get("format", "m4a")], str(aiff), str(out)], check=True)
        info = subprocess.run(["afinfo", str(out)], capture_output=True, text=True).stdout
        dur = next((l.split(":")[1].strip() for l in info.splitlines() if "estimated duration" in l), "?")
        print(f"{c['id']}: {out.name} ({dur}, voice {voice if voice_args else 'default'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
