#!/usr/bin/env python3
"""Record the real iOS main flow against isolated, synthetic demo services."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "demo"
RUNTIME = DEMO / ".runtime"
EXPECTED_STEPS = (
    "registration", "personal-details", "document-uploaded", "selfie-uploaded",
    "pending-review", "review-rejected", "applicant-rejected", "resubmitted",
    "review-approved", "verified", "submission-history", "logout",
)
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


class RecordingError(Exception):
    pass


class Processes:
    """Own process groups and continuously drain their output to a private log."""

    def __init__(self) -> None:
        self.log = (RUNTIME / "recording.log").open("w", encoding="utf-8")
        os.chmod(self.log.name, 0o600)
        self.lock = threading.Lock()
        self.children: list[subprocess.Popen[str]] = []
        self.readers: list[threading.Thread] = []

    def write(self, name: str, line: str) -> None:
        with self.lock:
            self.log.write(f"[{name}] {line.rstrip()}\n")
            self.log.flush()

    def start(self, name: str, command: list[str], *, cwd: Path = ROOT,
              env: dict[str, str] | None = None,
              events: queue.Queue[str | None] | None = None) -> subprocess.Popen[str]:
        process = subprocess.Popen(
            command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
            start_new_session=True,
        )
        self.children.append(process)

        def drain() -> None:
            assert process.stdout is not None
            try:
                for line in process.stdout:
                    line = ANSI.sub("", line.rstrip("\r\n"))
                    self.write(name, line)
                    if events is not None:
                        events.put(line)
            finally:
                process.stdout.close()
                if events is not None:
                    events.put(None)

        reader = threading.Thread(target=drain, name=name, daemon=True)
        reader.start()
        self.readers.append(reader)
        return process

    @staticmethod
    def stop(process: subprocess.Popen[str], first_signal: int = signal.SIGTERM,
             timeout: float = 8) -> None:
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, first_signal)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)

    def run(self, name: str, command: list[str], timeout: float = 300) -> None:
        process = self.start(name, command)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            self.stop(process)
            raise RecordingError(f"{name} timed out; inspect demo/.runtime/recording.log.") from error
        if code != 0:
            raise RecordingError(f"{name} failed ({code}); inspect demo/.runtime/recording.log.")

    def close(self) -> None:
        for process in reversed(self.children):
            self.stop(process)
        for reader in self.readers:
            reader.join(timeout=2)
        self.log.close()


def executable(name: str, fallback: Path | None = None) -> str:
    found = shutil.which(name)
    if found:
        return found
    if fallback and fallback.is_file() and os.access(fallback, os.X_OK):
        return str(fallback)
    raise RecordingError(f"Required executable is unavailable: {name}.")


def booted_simulator(device: str | None) -> dict[str, str]:
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"],
        check=True, capture_output=True, text=True, timeout=15,
    )
    devices = [item for runtime, entries in json.loads(result.stdout)["devices"].items()
               if ".iOS-" in runtime for item in entries
               if item.get("state") == "Booted" and item.get("isAvailable", True)]
    if device:
        devices = [item for item in devices if device in (item["udid"], item["name"])]
    if len(devices) != 1:
        raise RecordingError(
            "Boot one iOS simulator, or select a booted simulator with --device <UDID or name>."
        )
    return {key: devices[0][key] for key in ("udid", "name")}


def load_scenario() -> dict:
    scenario = json.loads((DEMO / "scenario.json").read_text(encoding="utf-8"))
    if scenario.get("syntheticOnly") is not True:
        raise RecordingError("demo/scenario.json must explicitly declare syntheticOnly: true.")
    for role in ("applicant", "reviewer"):
        values = scenario.get(role, {})
        if not re.fullmatch(r"[^@\s]+@kyc\.example", values.get("email", "")):
            raise RecordingError(f"The {role} email must use the fictional @kyc.example domain.")
        if not values.get("password"):
            raise RecordingError(f"Missing synthetic {role} password.")
    for key in ("fullName", "dateOfBirth", "nationality", "address", "documentNumber"):
        if not isinstance(scenario["applicant"].get(key), str) or not scenario["applicant"][key]:
            raise RecordingError(f"Missing synthetic applicant field: {key}.")
    return scenario


def require_free_ports() -> None:
    for port in (3300, 1125, 8125, 55462):
        with socket.socket() as listener:
            try:
                listener.bind(("127.0.0.1", port))
            except OSError as error:
                raise RecordingError(f"Demo port {port} is already occupied; stop its owner before recording.") from error


def wait_healthy(url: str, process: subprocess.Popen[str], timeout: float = 90) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RecordingError(f"Demo service exited before {url} became healthy; inspect the recording log.")
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.2)
    raise RecordingError(f"Timed out waiting for {url}.")


def video_duration(ffmpeg: str, movie: Path, fallback: float) -> float:
    probe = shutil.which("ffprobe") or str(Path(ffmpeg).with_name("ffprobe"))
    if Path(probe).is_file():
        result = subprocess.run(
            [probe, "-v", "error", "-show_entries", "format=duration", "-of",
             "default=noprint_wrappers=1:nokey=1", str(movie)],
            capture_output=True, text=True, timeout=20,
        )
        if result.returncode == 0:
            try:
                return float(result.stdout.strip())
            except ValueError:
                pass
    return fallback


def metadata_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", " ").replace("=", "\\=").replace(";", "\\;").replace("#", "\\#")


def subtitle_time(seconds: float) -> str:
    milliseconds = int(round(seconds * 1000))
    hours, milliseconds = divmod(milliseconds, 3_600_000)
    minutes, milliseconds = divmod(milliseconds, 60_000)
    seconds, milliseconds = divmod(milliseconds, 1000)
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"


def export_video(processes: Processes, ffmpeg: str, movie: Path,
                 markers: list[dict], duration: float, device: dict[str, str]) -> None:
    chapters = []
    for index, marker in enumerate(markers):
        start = 0 if index == 0 else min(marker["timestampSeconds"], duration)
        end = min(markers[index + 1]["timestampSeconds"], duration) if index + 1 < len(markers) else duration
        if end <= start:
            raise RecordingError("Recording chapter timings are invalid.")
        chapters.append({**marker, "startSeconds": round(start, 3), "endSeconds": round(end, 3)})
    metadata = [";FFMETADATA1", "title=KYC onboarding full main flow", "comment=Synthetic demo identities and documents only"]
    for chapter in chapters:
        metadata.extend(("[CHAPTER]", "TIMEBASE=1/1000",
                         f"START={round(chapter['startSeconds'] * 1000)}",
                         f"END={round(chapter['endSeconds'] * 1000)}",
                         f"title={metadata_escape(chapter['label'])}"))
    metadata_file = RUNTIME / "chapters.ffmetadata"
    metadata_file.write_text("\n".join(metadata) + "\n", encoding="utf-8")
    encoded = RUNTIME / "full-flow.mp4"
    for crf in (23, 28, 32):
        print(f"Encoding the simulator recording (CRF {crf})…", flush=True)
        processes.run("ffmpeg", [
            ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "warning", "-y",
            "-i", str(movie), "-i", str(metadata_file), "-map", "0:v:0",
            "-map_metadata", "1", "-map_chapters", "1", "-an",
            "-vf", "fps=30,scale=720:-2", "-c:v", "libx264", "-crf", str(crf),
            "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(encoded),
        ], timeout=600)
        if encoded.stat().st_size < 95_000_000:
            break
    else:
        raise RecordingError("Encoded video exceeds the GitHub file limit; keep the raw recording for a smaller export.")
    result = {
        "syntheticOnly": True,
        "recordedAt": dt.datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).isoformat(timespec="seconds"),
        "timezone": "Asia/Ho_Chi_Minh",
        "device": device,
        "video": "full-flow.mp4", "framesPerSecond": 30, "width": 720,
        "durationSeconds": round(duration, 3), "bytes": encoded.stat().st_size,
        "scenario": "scenario.json", "chapters": chapters,
        "notice": "Fictional identities, illustrated documents, and isolated local services only.",
    }
    json_file = RUNTIME / "full-flow.chapters.json"
    json_file.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    subtitles = []
    for index, chapter in enumerate(chapters, 1):
        subtitles.append(f"{index}\n{subtitle_time(chapter['startSeconds'])} --> {subtitle_time(chapter['endSeconds'])}\n{chapter['label']}\n")
    subtitle_file = RUNTIME / "full-flow.srt"
    subtitle_file.write_text("\n".join(subtitles), encoding="utf-8")
    for source in (encoded, json_file, subtitle_file):
        source.replace(DEMO / source.name)
        os.chmod(DEMO / source.name, 0o644)


def record(args: argparse.Namespace) -> None:
    scenario = load_scenario()
    flutter = executable("flutter")
    ffmpeg = executable("ffmpeg")
    executable("xcrun")
    mailpit = executable("mailpit", ROOT / "backend/.local/tools/mailpit/mailpit")
    tsx = executable("tsx", ROOT / "backend/node_modules/.bin/tsx")
    device = booted_simulator(args.device)
    require_free_ports()
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    os.chmod(RUNTIME, 0o700)
    for suffix in ("", "-wal", "-shm"):
        (RUNTIME / f"mailpit.db{suffix}").unlink(missing_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("MP_")}
    processes = Processes()
    try:
        print(f"Preparing isolated synthetic services for {device['name']}…", flush=True)
        mail = processes.start("mailpit", [
            mailpit, "--listen", "127.0.0.1:8125", "--smtp", "127.0.0.1:1125",
            "--database", str(RUNTIME / "mailpit.db"), "--disable-version-check",
            "--smtp-allowed-recipients", r".*@kyc\.example$", "--smtp-disable-rdns",
        ], env=env)
        wait_healthy("http://127.0.0.1:8125/api/v1/messages", mail)
        server = processes.start("api", [
            tsx, "--tsconfig", "backend/tsconfig.json", "demo/recording-server.mts",
        ], env=env)
        wait_healthy("http://127.0.0.1:3300/health", server)
        definitions = {
            "API_BASE_URL": "http://127.0.0.1:3300/api/v1",
            "MAILPIT_URL": "http://127.0.0.1:8125",
            "DEMO_EMAIL": scenario["applicant"]["email"],
            "DEMO_PASSWORD": scenario["applicant"]["password"],
            "DEMO_REVIEWER_EMAIL": scenario["reviewer"]["email"],
            "DEMO_REVIEWER_PASSWORD": scenario["reviewer"]["password"],
        }
        for dart_name, field in (
            ("DEMO_FULL_NAME", "fullName"), ("DEMO_DATE_OF_BIRTH", "dateOfBirth"),
            ("DEMO_NATIONALITY", "nationality"), ("DEMO_ADDRESS", "address"),
            ("DEMO_DOCUMENT_NUMBER", "documentNumber"),
        ):
            definitions[dart_name] = scenario["applicant"][field]
        events: queue.Queue[str | None] = queue.Queue()
        test = processes.start("flutter", [
            flutter, "test", "integration_test/recording_main_flow_test.dart",
            "-d", device["udid"], "--reporter", "expanded",
            *[f"--dart-define={key}={value}" for key, value in definitions.items()],
        ], cwd=ROOT / "mobile", env=env, events=events)
        print("Running and recording the complete application flow…", flush=True)
        deadline = time.monotonic() + args.timeout
        movie = DEMO / "full-flow.mov"
        recorder = None
        recording_start = None
        recording_duration = None
        markers = []
        while time.monotonic() < deadline:
            for service in (mail, server):
                if service.poll() is not None:
                    raise RecordingError("An isolated demo service stopped during the flow.")
            if recorder and recording_duration is None and recorder.poll() is not None:
                raise RecordingError("Simulator recording stopped before DEMO_FINISHED.")
            try:
                line = events.get(timeout=0.25)
            except queue.Empty:
                continue
            if line is None:
                break
            if re.search(r"\bDEMO_READY\b", line):
                if recorder is not None:
                    raise RecordingError("The test emitted DEMO_READY more than once.")
                recording_start = time.monotonic()
                recorder = processes.start("simctl", [
                    "xcrun", "simctl", "io", device["udid"], "recordVideo",
                    "--codec=h264", "--mask=black", "--force", str(movie),
                ])
                print("Simulator recording started.", flush=True)
            match = re.search(r"\bDEMO_STEP\|([^|\r\n]+)\|(.+)", line)
            if match:
                if recording_start is None or recording_duration is not None:
                    raise RecordingError("A flow step occurred outside the recording markers.")
                slug, label = match.groups()
                markers.append({"slug": slug.strip(), "label": label.strip(),
                                "timestampSeconds": round(time.monotonic() - recording_start, 3)})
                print(f"  {label.strip()}", flush=True)
            if re.search(r"\bDEMO_FINISHED\b", line):
                if recorder is None or recording_start is None or recording_duration is not None:
                    raise RecordingError("Invalid DEMO_FINISHED marker.")
                recording_duration = time.monotonic() - recording_start
                processes.stop(recorder, signal.SIGINT, timeout=20)
        else:
            raise RecordingError(f"Integration flow exceeded {args.timeout} seconds.")
        try:
            test_code = test.wait(timeout=30)
        except subprocess.TimeoutExpired as error:
            raise RecordingError("Flutter did not exit after the flow.") from error
        if test_code != 0:
            raise RecordingError(f"The integration test failed ({test_code}); inspect demo/.runtime/recording.log.")
        if recorder is None or recording_duration is None or not movie.is_file() or movie.stat().st_size < 1000:
            raise RecordingError("A complete simulator recording was not produced.")
        seen = [marker["slug"] for marker in markers]
        missing = [slug for slug in EXPECTED_STEPS if slug not in seen]
        if missing:
            raise RecordingError(f"Recording missed required flow markers: {', '.join(missing)}.")
        if [seen.index(slug) for slug in EXPECTED_STEPS] != sorted(seen.index(slug) for slug in EXPECTED_STEPS):
            raise RecordingError("Required flow markers were emitted out of order.")
        duration = video_duration(ffmpeg, movie, recording_duration)
        export_video(processes, ffmpeg, movie, markers, duration, device)
        print("Created demo/full-flow.mp4, demo/full-flow.chapters.json, and demo/full-flow.srt.", flush=True)
    finally:
        processes.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="Booted iOS simulator UDID or exact name")
    parser.add_argument("--timeout", type=float, default=1200,
                        help="Maximum integration-test duration in seconds (default: 1200)")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    def interrupted(*_args: object) -> None:
        raise KeyboardInterrupt()

    signal.signal(signal.SIGTERM, interrupted)
    try:
        record(args)
    except KeyboardInterrupt:
        print("Recording cancelled; owned services were stopped.", file=sys.stderr)
        return 130
    except (RecordingError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Recording failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
