#!/usr/bin/env python3
"""Add timed Vietnamese narration to the existing synthetic main-flow video."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import sys
import wave


DEMO = Path(__file__).resolve().parent
RUNTIME = DEMO / ".runtime" / "voiceover"
SAMPLE_RATE = 44100


def run(command: list[str]) -> None:
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"Command failed: {command[0]}")


def duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        check=True, capture_output=True, text=True, timeout=20,
    )
    return float(result.stdout.strip())


def subtitle_time(seconds: float) -> str:
    milliseconds = round(seconds * 1000)
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    seconds, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"


def chapter_time(anchor: dict, chapters: list[dict], video_duration: float) -> float:
    if anchor.get("videoEnd") is True:
        base = video_duration
    else:
        matches = [chapter for chapter in chapters if chapter["slug"] == anchor["chapter"]]
        occurrence = anchor.get("occurrence", 1)
        if not isinstance(occurrence, int) or not 1 <= occurrence <= len(matches):
            raise ValueError(f"Missing chapter anchor: {anchor}")
        base = matches[occurrence - 1]["startSeconds"]
    return round(base + anchor.get("offsetSeconds", 0), 3)


def resolve_segments(plan: dict, video_duration: float) -> list[dict]:
    if not plan.get("timingSource"):
        return plan["segments"]
    timing_file = DEMO / plan["timingSource"]
    if timing_file.parent != DEMO:
        raise ValueError("Narration chapter timings must be in demo/.")
    chapters = json.loads(timing_file.read_text(encoding="utf-8"))["chapters"]
    return [
        {**segment,
         "startSeconds": chapter_time(segment["start"], chapters, video_duration),
         "endSeconds": chapter_time(segment["end"], chapters, video_duration)}
        for segment in plan["segments"]
    ]


def main() -> None:
    for name in ("ffmpeg", "ffprobe"):
        if shutil.which(name) is None:
            raise RuntimeError(f"Required executable is unavailable: {name}")
    plan = json.loads((DEMO / "voiceover.vi.json").read_text(encoding="utf-8"))
    if plan.get("syntheticOnly") is not True or plan.get("language") != "vi-VN":
        raise ValueError("Use the Vietnamese synthetic demo narration plan.")
    engine = plan.get("engine", "macos-say")
    if engine == "edge-tts":
        tts = shutil.which("edge-tts")
        fallback = DEMO / ".runtime" / "tts-venv" / "bin" / "edge-tts"
        if not tts and fallback.is_file():
            tts = str(fallback)
        if not tts:
            raise RuntimeError("Install demo/tts-requirements.txt in demo/.runtime/tts-venv first.")
    elif engine == "macos-say":
        tts = shutil.which("say")
        if not tts:
            raise RuntimeError("The macOS say command is unavailable.")
    else:
        raise ValueError(f"Unsupported narration engine: {engine}")
    video = DEMO / plan["video"]
    output = DEMO / plan["outputVideo"]
    if video.parent != DEMO or output.parent != DEMO or video == output:
        raise ValueError("Input and output must be distinct video files in demo/.")
    video_duration = duration(video)
    segments = resolve_segments(plan, video_duration)
    previous_end = 0.0
    for segment in segments:
        start, end = segment["startSeconds"], segment["endSeconds"]
        if not (previous_end <= start < end <= video_duration):
            raise ValueError(f"Invalid narration interval: {segment['id']}")
        if not segment["text"].strip():
            raise ValueError(f"Empty narration: {segment['id']}")
        previous_end = end
    RUNTIME.mkdir(parents=True, exist_ok=True)
    track = bytearray(round(video_duration * SAMPLE_RATE) * 2)
    report = []
    subtitle_blocks = []
    for index, segment in enumerate(segments, 1):
        print(f"Voicing {index}/{len(segments)}: {segment['id']}", flush=True)
        base = RUNTIME / f"segment-{index:02}"
        text_file = base.with_suffix(".txt")
        source_audio = base.with_suffix(".mp3" if engine == "edge-tts" else ".aiff")
        wav_file = base.with_suffix(".wav")
        text_file.write_text(segment["text"], encoding="utf-8")
        if engine == "edge-tts":
            run([tts, "--voice", plan["voice"],
                 f"--rate={plan.get('speechRate', '+0%')}",
                 "--file", str(text_file), "--write-media", str(source_audio)])
        else:
            run([tts, "-v", plan.get("voice", "Linh"), "-r",
                 str(plan.get("speakingRate", 175)), "-f", str(text_file),
                 "-o", str(source_audio)])
        original_duration = duration(source_audio)
        available = segment["endSeconds"] - segment["startSeconds"] - 0.2
        speed = max(1.0, original_duration / available)
        if speed > 1.20:
            raise ValueError(
                f"Narration '{segment['id']}' is too long ({original_duration:.2f}s "
                f"for {available:.2f}s). Shorten its text or enlarge its interval."
            )
        filters = f"atempo={speed:.6f},loudnorm=I=-18:LRA=7:TP=-1.5"
        run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-i", str(source_audio), "-af", filters, "-ar", str(SAMPLE_RATE),
             "-ac", "1", "-c:a", "pcm_s16le", str(wav_file)])
        with wave.open(str(wav_file), "rb") as clip:
            if (clip.getframerate(), clip.getnchannels(), clip.getsampwidth()) != (SAMPLE_RATE, 1, 2):
                raise ValueError("Unexpected synthesized audio format.")
            voice_duration = clip.getnframes() / SAMPLE_RATE
            payload = clip.readframes(clip.getnframes())
        start_frame = round(segment["startSeconds"] * SAMPLE_RATE)
        end_frame = start_frame + len(payload) // 2
        if voice_duration > segment["endSeconds"] - segment["startSeconds"]:
            raise ValueError(f"Narration overlaps its next screen: {segment['id']}")
        track[start_frame * 2:end_frame * 2] = payload
        voice_end = segment["startSeconds"] + voice_duration
        report.append({**segment, "audioDurationSeconds": round(voice_duration, 3),
                       "audioEndSeconds": round(voice_end, 3), "speedFactor": round(speed, 4)})
        subtitle_blocks.append(
            f"{index}\n{subtitle_time(segment['startSeconds'])} --> "
            f"{subtitle_time(voice_end)}\n{segment['text']}\n"
        )
    wav_track = RUNTIME / "full-flow-voiceover.wav"
    with wave.open(str(wav_track), "wb") as destination:
        destination.setnchannels(1)
        destination.setsampwidth(2)
        destination.setframerate(SAMPLE_RATE)
        destination.writeframes(track)
    encoded = RUNTIME / output.name
    run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
         "-i", str(video), "-i", str(wav_track), "-map", "0:v:0", "-map", "1:a:0",
         "-map_metadata", "0", "-map_chapters", "0", "-c:v", "copy", "-c:a", "aac",
         "-b:a", "128k", "-ar", str(SAMPLE_RATE), "-t", f"{video_duration:.6f}",
         "-metadata", "title=KYC main flow with Vietnamese narration",
         "-metadata:s:a:0", "language=vie", "-movflags", "+faststart", str(encoded)])
    encoded.replace(output)
    (DEMO / "full-flow.vi.srt").write_text("\n".join(subtitle_blocks), encoding="utf-8")
    (DEMO / "voiceover.vi.report.json").write_text(
        json.dumps({"syntheticOnly": True, "engine": engine,
                    "voice": plan.get("voice", "Linh"),
                    "voiceGender": plan.get("voiceGender"),
                    "language": "vi-VN", "video": output.name,
                    "durationSeconds": video_duration, "segments": report},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    print(f"Created {output.name} with Vietnamese narration.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Voiceover failed: {error}", file=sys.stderr)
        sys.exit(1)
