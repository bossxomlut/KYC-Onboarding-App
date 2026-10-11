"""Install verified public models and an isolated Python runtime; no API keys."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.request import urlopen
import venv

ROOT = Path(__file__).resolve().parent.parent
BACKEND = ROOT / "backend"
ASSETS = (
    (
        "face_detection_yunet_2023mar.onnx",
        "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
        "8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4",
    ),
    (
        "face_recognition_sface_2021dec.onnx",
        "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx",
        "0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79",
    ),
    (
        "tessdata/eng.traineddata",
        "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/eng.traineddata",
        "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2",
    ),
    (
        "tessdata/vie.traineddata",
        "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/vie.traineddata",
        "79df64caf7bcfb2a27df5042ecb6121e196eada34da774956995747636d5bfa1",
    ),
)


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def absolute_path(value):
    # Resolving a venv's Python symlink selects the system interpreter instead.
    return Path(os.path.abspath(value))


def install_asset(path, url, expected_sha256):
    """Never replace a good asset with partial, corrupt or unexpected bytes."""
    if path.is_file() and digest(path) == expected_sha256:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            with urlopen(url, timeout=45) as response:
                shutil.copyfileobj(response, output)
        if digest(temporary) != expected_sha256:
            raise ValueError(f"Checksum failed for {path.name}; no asset was replaced.")
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check an existing install without downloads or changes",
    )
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        raise SystemExit("Python 3.11+ is required.")
    tesseract = os.environ.get("TESSERACT_CMD") or shutil.which("tesseract")
    if not tesseract:
        raise SystemExit(
            "Install Tesseract first: macOS: brew install tesseract; Debian/Ubuntu: sudo apt install tesseract-ocr"
        )
    models = Path(
        os.environ.get("KYC_LOCAL_MODELS_DIR", BACKEND / ".local/identity-models")
    ).resolve()
    python = absolute_path(
        os.environ.get("KYC_LOCAL_PYTHON", BACKEND / ".local/identity-venv/bin/python")
    )
    if not args.check:
        if not python.exists():
            if os.environ.get("KYC_LOCAL_PYTHON"):
                raise SystemExit(
                    "KYC_LOCAL_PYTHON must point to an existing Python interpreter."
                )
            venv.EnvBuilder(with_pip=True).create(python.parent.parent)
        subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "-r",
                str(BACKEND / "local-verification/requirements.txt"),
            ],
            check=True,
        )
        for name, url, checksum in ASSETS:
            install_asset(models / name, url, checksum)
            print(f"Verified {name}", flush=True)
    env = dict(
        os.environ,
        KYC_LOCAL_MODELS_DIR=str(models),
        TESSDATA_PREFIX=str(models / "tessdata"),
        TESSERACT_CMD=tesseract,
    )
    check = subprocess.run(
        [str(python), str(BACKEND / "local-verification/engine.py"), "--check"],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
        check=True,
    )
    result = json.loads(check.stdout)
    if not result.get("ready"):
        raise SystemExit(
            "Local identity engine is not ready. Check models, Python packages and Tesseract."
        )
    print(
        "Local identity engine is ready (Vietnamese/English OCR data, YuNet, SFace). No cloud API is used."
    )
    print("Set KYC_VERIFICATION_PROVIDER=local in backend/.env, then restart the API.")
    print("Do not reuse the AWS threshold 90; local defaults to 36.3.")


if __name__ == "__main__":
    main()
