#!/usr/bin/env python3
"""Offline document OCR and consented one-to-one face comparison.

The subprocess contract is one JSON request on stdin and one JSON response on
stdout. No photographs, recognized text, paths, or errors are logged. Models
and OCR language data are installed separately; no runtime network is used.
"""

import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import date
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import unicodedata


DEFAULT_THRESHOLD = 36.3
MAX_REQUEST_BYTES = 30 * 1024 * 1024
MAX_IMAGE_BYTES = 11 * 1024 * 1024
MAX_IMAGE_PIXELS = 24_000_000
MAX_IMAGE_SIDE = 10_000
OCR_TIMEOUT_SECONDS = 4
MODEL_NAMES = (
    "face_detection_yunet_2023mar.onnx",
    "face_recognition_sface_2021dec.onnx",
)


def empty_fields():
    return {"fullName": None, "dateOfBirth": None, "documentNumber": None}


def failed_ocr():
    return {
        "status": "failed",
        "text": "",
        "fields": empty_fields(),
        "confidence": None,
    }


def failed_face(threshold):
    return {"status": "failed", "similarity": None, "threshold": threshold}


def validate_request(request):
    if not isinstance(request, dict):
        raise ValueError("Invalid request")
    threshold = request.get("threshold", DEFAULT_THRESHOLD)
    if (
        isinstance(threshold, bool)
        or not isinstance(threshold, (int, float))
        or not math.isfinite(threshold)
        or not 1 <= threshold <= 100
    ):
        raise ValueError("Invalid threshold")
    images = []
    for key in ("document", "selfie"):
        value = request.get(key)
        if (
            not isinstance(value, str)
            or not value
            or len(value) > MAX_IMAGE_BYTES * 4 // 3 + 4
        ):
            raise ValueError("Invalid image")
        try:
            data = base64.b64decode(value, validate=True)
        except Exception:
            raise ValueError("Invalid image") from None
        if not data or len(data) > MAX_IMAGE_BYTES:
            raise ValueError("Invalid image")
        images.append(data)
    return (*images, float(threshold))


def image_dimensions(data):
    """Check dimensions before OpenCV allocation; only JPEG/PNG are accepted."""
    if (
        data.startswith(b"\x89PNG\r\n\x1a\n")
        and len(data) >= 24
        and data[12:16] == b"IHDR"
    ):
        width, height = struct.unpack(">II", data[16:24])
    elif data.startswith(b"\xff\xd8"):
        position = 2
        width = height = 0
        while position < len(data):
            if data[position] != 0xFF:
                raise ValueError("Invalid image")
            while position < len(data) and data[position] == 0xFF:
                position += 1
            if position >= len(data):
                break
            marker = data[position]
            position += 1
            if marker in (0xD9, 0xDA):
                break
            if marker == 0x01 or 0xD0 <= marker <= 0xD8:
                continue
            if position + 2 > len(data):
                raise ValueError("Invalid image")
            size = struct.unpack(">H", data[position : position + 2])[0]
            if size < 2 or position + size > len(data):
                raise ValueError("Invalid image")
            if marker in (
                0xC0,
                0xC1,
                0xC2,
                0xC3,
                0xC5,
                0xC6,
                0xC7,
                0xC9,
                0xCA,
                0xCB,
                0xCD,
                0xCE,
                0xCF,
            ):
                if size < 8:
                    raise ValueError("Invalid image")
                height, width = struct.unpack(">HH", data[position + 3 : position + 7])
                break
            position += size
        if not width or not height:
            raise ValueError("Invalid image")
    else:
        raise ValueError("Invalid image")
    if (
        not 1 <= width <= MAX_IMAGE_SIDE
        or not 1 <= height <= MAX_IMAGE_SIDE
        or width * height > MAX_IMAGE_PIXELS
    ):
        raise ValueError("Invalid image")
    return width, height


def normalize_label(value):
    value = unicodedata.normalize("NFD", value.lower().replace("đ", "d"))
    return "".join(
        character for character in value if not unicodedata.combining(character)
    )


_NAME = r"(?:ho\s+va\s+ten(?:\s+khai\s+sinh)?|ho\s+ten|full\s+name|name)"
_BIRTH = r"(?:ngay\s*,?\s*thang\s*,?\s*nam\s+sinh|ngay\s+sinh|date\s+of\s+birth|birth\s+date|dob)"
_NUMBER = r"(?:so(?:\s+(?:can\s+cuoc(?:\s+cong\s+dan)?|dinh\s+danh\s+ca\s+nhan|cmnd|cccd))?|no\.?|(?:document|passport|id|identity)\s*(?:number|no\.?|#))"
LABELS = {
    "fullName": re.compile(
        rf"^{_NAME}(?:\s*/\s*{_NAME})?\s*(?::\s*(.*)|$)", re.IGNORECASE
    ),
    "dateOfBirth": re.compile(
        rf"^{_BIRTH}(?:\s*/\s*{_BIRTH})?\s*(?::\s*(.*)|$)", re.IGNORECASE
    ),
    "documentNumber": re.compile(
        rf"^{_NUMBER}(?:\s*/\s*{_NUMBER})?\s*(?::\s*(.*)|$)", re.IGNORECASE
    ),
}


def labeled_value(lines, label):
    for index, original in enumerate(lines):
        line = unicodedata.normalize("NFC", original)
        match = label.match(normalize_label(line))
        if not match:
            continue
        # Vietnamese NFC characters remain one character after accent removal,
        # so the label's capture offset preserves the original value's accents.
        candidate = line[match.start(1) :].strip() if match.group(1) else ""
        if not candidate and index + 1 < len(lines):
            candidate = lines[index + 1].strip()
        normalized = normalize_label(candidate)
        if (
            candidate
            and ":" not in candidate
            and not any(pattern.match(normalized) for pattern in LABELS.values())
        ):
            return candidate
    return None


def birth_date(value):
    if not value:
        return None
    match = re.fullmatch(r"(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{4})", value)
    iso = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", value)
    if match:
        day, month, year = map(int, match.groups())
    elif iso:
        year, month, day = map(int, iso.groups())
    else:
        return None
    try:
        result = date(year, month, day)
    except ValueError:
        return None
    return result.isoformat() if 1900 <= year and result <= date.today() else None


def parse_tsv(value):
    if not isinstance(value, str) or len(value) > 4 * 1024 * 1024:
        raise ValueError("Invalid OCR result")
    rows = value.splitlines()
    if not rows or rows[0].split("\t")[:6] != [
        "level",
        "page_num",
        "block_num",
        "par_num",
        "line_num",
        "word_num",
    ]:
        raise ValueError("Invalid OCR result")
    lines = {}
    confidence = []
    for row in rows[1:]:
        fields = row.split("\t", 11)
        if len(fields) != 12 or fields[0] != "5":
            continue
        text = fields[11].strip()
        if not text:
            continue
        key = tuple(fields[1:5])
        if key not in lines:
            if len(lines) >= 200:
                break
            lines[key] = []
        if sum(len(word) + 1 for word in lines[key]) < 500:
            lines[key].append(text[:500])
        try:
            score = float(fields[10])
            if math.isfinite(score) and 0 <= score <= 100:
                confidence.append(score)
        except ValueError:
            pass
    text_lines = [" ".join(words)[:500] for words in lines.values()]
    text = "\n".join(text_lines)[:20_000]
    if not text:
        return {
            "status": "no_text",
            "text": "",
            "fields": empty_fields(),
            "confidence": None,
        }
    name = labeled_value(text_lines, LABELS["fullName"])
    number = labeled_value(text_lines, LABELS["documentNumber"])
    return {
        "status": "succeeded",
        "text": text,
        "fields": {
            "fullName": name
            if name
            and 2 <= len(name) <= 120
            and any(character.isalpha() for character in name)
            else None,
            "dateOfBirth": birth_date(labeled_value(text_lines, LABELS["dateOfBirth"])),
            "documentNumber": number
            if number and re.fullmatch(r"[A-Za-z0-9 -]{4,40}", number)
            else None,
        },
        "confidence": round(sum(confidence) / len(confidence), 2)
        if confidence
        else None,
    }


def face_count_status(counts):
    if any(count > 1 for count in counts):
        return "multiple_faces"
    if any(count == 0 for count in counts):
        return "no_face"
    return None


def face_score_result(cosine, threshold):
    if not math.isfinite(cosine):
        raise ValueError("Invalid face score")
    score = max(0.0, min(100.0, cosine * 100))
    return {
        "status": "matched" if score >= threshold else "not_matched",
        "similarity": score,
        "threshold": threshold,
    }


def models_directory():
    return Path(
        os.environ.get(
            "KYC_LOCAL_MODELS_DIR",
            Path(__file__).resolve().parent.parent / ".local" / "identity-models",
        )
    )


def ocr_languages():
    # Prefer Vietnamese for CCCD diacritics; mixing English may remove accents
    # from names. English documents can explicitly select another installed set.
    languages = os.environ.get("KYC_LOCAL_OCR_LANGUAGES", "vie")
    if languages not in ("vie", "eng", "vie+eng", "eng+vie"):
        raise ValueError("Invalid OCR languages")
    return languages


class LocalOperations:
    def __init__(self):
        # Lazy import keeps malformed request handling independent of optional
        # native packages and makes the subprocess's output contract stable.
        import cv2
        import numpy

        cv2.setNumThreads(1)
        self.cv = cv2
        self.np = numpy

    def decode(self, data):
        expected = image_dimensions(data)
        image = self.cv.imdecode(
            self.np.frombuffer(data, dtype=self.np.uint8), self.cv.IMREAD_COLOR
        )
        if image is None or (image.shape[1], image.shape[0]) != expected:
            raise ValueError("Invalid image")
        return image

    def resize(self, image, maximum):
        height, width = image.shape[:2]
        scale = min(1.0, maximum / max(height, width))
        if scale == 1:
            return image
        return self.cv.resize(
            image,
            (max(1, round(width * scale)), max(1, round(height * scale))),
            interpolation=self.cv.INTER_AREA,
        )

    def ocr(self, image):
        image = self.resize(image, 2400)
        success, encoded = self.cv.imencode(".png", image)
        if not success:
            raise ValueError("Invalid image")
        completed = subprocess.run(
            # A direct setting works with isolated traineddata directories
            # which intentionally do not contain Tesseract's configs/tsv file.
            [
                os.environ.get("TESSERACT_CMD", "tesseract"),
                "stdin",
                "stdout",
                "-l",
                ocr_languages(),
                "--psm",
                "3",
                "-c",
                "tessedit_create_tsv=1",
            ],
            input=encoded.tobytes(),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=OCR_TIMEOUT_SECONDS,
        )
        return parse_tsv(completed.stdout.decode("utf-8", errors="replace"))

    def detect_faces(self, image):
        detector = getattr(self, "_face_detector", None)
        if detector is None:
            detector = self.cv.FaceDetectorYN.create(
                str(models_directory() / MODEL_NAMES[0]),
                "",
                (320, 320),
                0.8,
                0.3,
                5000,
            )
            self._face_detector = detector
        image = self.resize(image, 1600)
        height, width = image.shape[:2]
        detector.setInputSize((width, height))
        _, detected = detector.detect(image)
        # A later detector inference can reuse its output buffer. Keep the
        # selfie landmarks valid for comparison after document detection.
        return image, detected.copy() if detected is not None else []

    def compare_faces(self, document, selfie, threshold):
        cv = self.cv
        recognizer = cv.FaceRecognizerSF.create(
            str(models_directory() / MODEL_NAMES[1]), ""
        )
        # OpenCV Net output buffers may be reused by the next inference.
        features = [
            recognizer.feature(recognizer.alignCrop(image, detected[0])).copy()
            for image, detected in (document, selfie)
        ]
        cosine = float(
            recognizer.match(features[0], features[1], cv.FaceRecognizerSF_FR_COSINE)
        )
        return face_score_result(cosine, threshold)


def verify_faces(document, selfie, threshold, operations):
    result = {
        "selfieFace": {"status": "failed"},
        "faceMatch": failed_face(threshold),
    }
    if selfie is None:
        return result
    try:
        selfie_faces = operations.detect_faces(selfie)
        status = face_count_status([len(selfie_faces[1])])
        result["selfieFace"] = {"status": status or "detected"}
    except Exception:
        return result
    # A missing or ambiguous selfie face prevents comparison regardless of
    # document quality. Detect it once and share its landmarks with matching.
    if status:
        result["faceMatch"] = {
            "status": status,
            "similarity": None,
            "threshold": threshold,
        }
        return result
    if document is None:
        return result
    try:
        document_faces = operations.detect_faces(document)
        status = face_count_status([len(document_faces[1])])
        result["faceMatch"] = (
            {"status": status, "similarity": None, "threshold": threshold}
            if status
            else operations.compare_faces(document_faces, selfie_faces, threshold)
        )
    except Exception:
        pass
    return result


def verify_images(document_bytes, selfie_bytes, threshold, operations=None):
    result = {
        "ocr": failed_ocr(),
        "selfieFace": {"status": "failed"},
        "faceMatch": failed_face(threshold),
    }
    try:
        operations = operations or LocalOperations()
    except Exception:
        return result
    try:
        document = operations.decode(document_bytes)
    except Exception:
        document = None
    try:
        selfie = operations.decode(selfie_bytes)
    except Exception:
        selfie = None

    def ocr():
        try:
            return operations.ocr(document) if document is not None else failed_ocr()
        except Exception:
            return failed_ocr()

    with ThreadPoolExecutor(max_workers=2) as executor:
        ocr_task = executor.submit(ocr)
        face_task = executor.submit(
            verify_faces, document, selfie, threshold, operations
        )
        result["ocr"] = ocr_task.result()
        result.update(face_task.result())
    return result


def prerequisite_check():
    """A setup probe; reports capabilities without exposing runtime paths."""
    result = {"ready": False, "ocr": False, "faces": False}
    try:
        operations = LocalOperations()
        cv = operations.cv
        directory = models_directory()
        cv.FaceDetectorYN.create(str(directory / MODEL_NAMES[0]), "", (320, 320))
        cv.FaceRecognizerSF.create(str(directory / MODEL_NAMES[1]), "")
        result["faces"] = True
    except Exception:
        pass
    try:
        required_languages = set(ocr_languages().split("+"))
        completed = subprocess.run(
            [os.environ.get("TESSERACT_CMD", "tesseract"), "--list-langs"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=4,
        )
        languages = set(completed.stdout.decode("utf-8", errors="replace").splitlines())
        result["ocr"] = required_languages.issubset(languages)
    except Exception:
        pass
    result["ready"] = result["ocr"] and result["faces"]
    return result


def main(stdin=None, stdout=None):
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    result = {
        "ocr": failed_ocr(),
        "selfieFace": {"status": "failed"},
        "faceMatch": failed_face(DEFAULT_THRESHOLD),
    }
    try:
        value = stdin.read(MAX_REQUEST_BYTES + 1)
        if len(value.encode("utf-8")) > MAX_REQUEST_BYTES:
            raise ValueError("Invalid request")
        request = json.loads(value)
        document, selfie, threshold = validate_request(request)
        result = verify_images(document, selfie, threshold)
    except Exception:
        pass
    stdout.write(
        json.dumps(result, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
        + "\n"
    )
    stdout.flush()


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        print(json.dumps(prerequisite_check(), separators=(",", ":")))
    else:
        main()
