import importlib.util
import io
import json
import math
from pathlib import Path
import subprocess
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "identity_engine", Path(__file__).with_name("engine.py")
)
engine = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(engine)


def tsv(lines):
    result = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n"
    for number, line in enumerate(lines, 1):
        for word, text in enumerate(line.split(), 1):
            result += f"5\t1\t1\t1\t{number}\t{word}\t0\t0\t1\t1\t91.5\t{text}\n"
    return result


class OcrParsingTests(unittest.TestCase):
    def test_vietnamese_bilingual_document_labels(self):
        result = engine.parse_tsv(
            tsv(
                [
                    "CĂN CƯỚC CÔNG DÂN",
                    "Số / No.: 001090000001",
                    "Họ và tên / Full name:",
                    "NGUYỄN VĂN AN",
                    "Ngày, tháng, năm sinh / Date of birth: 05/06/1990",
                ]
            )
        )
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(
            result["fields"],
            {
                "fullName": "NGUYỄN VĂN AN",
                "dateOfBirth": "1990-06-05",
                "documentNumber": "001090000001",
            },
        )
        self.assertEqual(result["confidence"], 91.5)

    def test_no_guessing_unlabelled_values_or_parents_name(self):
        result = engine.parse_tsv(
            tsv(
                [
                    "Họ và tên cha: NGUYỄN VĂN BÌNH",
                    "001090000001",
                    "05/06/1990",
                    "NGUYỄN VĂN AN",
                ]
            )
        )
        self.assertEqual(result["fields"], engine.empty_fields())

    def test_empty_label_does_not_consume_other_label(self):
        result = engine.parse_tsv(
            tsv(
                [
                    "Họ và tên:",
                    "Ngày sinh: 31/02/1990",
                    "Số: 123456789012",
                ]
            )
        )
        self.assertIsNone(result["fields"]["fullName"])
        self.assertIsNone(result["fields"]["dateOfBirth"])

    def test_birth_date_requires_real_calendar_date(self):
        self.assertEqual(engine.birth_date("29/02/2000"), "2000-02-29")
        self.assertEqual(engine.birth_date("1990-12-05"), "1990-12-05")
        self.assertIsNone(engine.birth_date("29/02/2001"))
        self.assertIsNone(engine.birth_date("05/06/1890"))
        self.assertIsNone(engine.birth_date("05/06/2090"))

    def test_no_text_is_semantic_success(self):
        self.assertEqual(engine.parse_tsv(tsv([]))["status"], "no_text")

    def test_vietnamese_cccd_abbreviation(self):
        result = engine.parse_tsv(tsv(["Số CCCD: 001090000001"]))
        self.assertEqual(result["fields"]["documentNumber"], "001090000001")

    def test_bounds_persisted_text_and_ignores_nonfinite_confidence(self):
        result = engine.parse_tsv(tsv(["A" * 600] * 300).replace("91.5", "nan"))
        self.assertLessEqual(len(result["text"]), 20_000)
        self.assertLessEqual(len(result["text"].splitlines()), 200)
        self.assertIsNone(result["confidence"])


class RequestTests(unittest.TestCase):
    def test_request_requires_two_images_and_finite_valid_threshold(self):
        self.assertRaises(ValueError, engine.validate_request, {"document": "x"})
        for threshold in (True, 0, 101, "36.3", math.nan):
            self.assertRaises(
                ValueError,
                engine.validate_request,
                {
                    "document": "eA==",
                    "selfie": "eA==",
                    "threshold": threshold,
                },
            )

    def test_default_threshold_and_base64_validation(self):
        document, selfie, threshold = engine.validate_request(
            {
                "document": "eA==",
                "selfie": "eQ==",
            }
        )
        self.assertEqual((document, selfie, threshold), (b"x", b"y", 36.3))
        self.assertRaises(
            ValueError, engine.validate_request, {"document": "??", "selfie": "eA=="}
        )

    def test_cli_never_exposes_errors_or_input(self):
        stdin = io.StringIO('{"document":"SECRET"}')
        stdout = io.StringIO()
        engine.main(stdin=stdin, stdout=stdout)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result["ocr"]["status"], "failed")
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertNotIn("SECRET", stdout.getvalue())

    def test_jpeg_dimensions_checked_before_decode(self):
        safe = b"\xff\xd8\xff\xc0\x00\x0b\x08\x00\x64\x00\xc8\x01\x01\x11\x00\xff\xd9"
        self.assertEqual(engine.image_dimensions(safe), (200, 100))
        huge = safe.replace(b"\x00\x64\x00\xc8", b"\xff\xff\xff\xff")
        self.assertRaises(ValueError, engine.image_dimensions, huge)
        self.assertRaises(ValueError, engine.image_dimensions, b"not an image")


class FakeOperations:
    def __init__(self, ocr_error=False, face_error=False):
        self.ocr_error = ocr_error
        self.face_error = face_error

    def decode(self, data):
        return data

    def ocr(self, image):
        if self.ocr_error:
            raise subprocess.TimeoutExpired("hidden", 10)
        return engine.parse_tsv(tsv(["Họ và tên: NGUYỄN VĂN AN"]))

    def compare(self, document, selfie, threshold):
        if self.face_error:
            raise RuntimeError("private path or provider detail")
        return {"status": "matched", "similarity": 87.2, "threshold": threshold}


class PartialFailureTests(unittest.TestCase):
    def test_ocr_timeout_preserves_face_result(self):
        result = engine.verify_images(
            b"doc", b"selfie", 36.3, FakeOperations(ocr_error=True)
        )
        self.assertEqual(result["ocr"]["status"], "failed")
        self.assertEqual(result["faceMatch"]["status"], "matched")

    def test_face_failure_preserves_ocr_result(self):
        result = engine.verify_images(
            b"doc", b"selfie", 36.3, FakeOperations(face_error=True)
        )
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(result["faceMatch"]["status"], "failed")

    def test_invalid_selfie_preserves_document_ocr(self):
        operations = FakeOperations()
        operations.decode = (
            lambda data: data if data == b"doc" else (_ for _ in ()).throw(ValueError())
        )
        result = engine.verify_images(b"doc", b"invalid", 36.3, operations)
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(result["faceMatch"]["status"], "failed")

    def test_independent_checks_run_concurrently_within_request_deadline(self):
        operations = FakeOperations()
        barrier = threading.Barrier(2)
        original_ocr, original_compare = operations.ocr, operations.compare

        def ocr(image):
            barrier.wait(timeout=1)
            return original_ocr(image)

        def compare(document, selfie, threshold):
            barrier.wait(timeout=1)
            return original_compare(document, selfie, threshold)

        operations.ocr, operations.compare = ocr, compare
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(result["faceMatch"]["status"], "matched")


class NativeBoundaryTests(unittest.TestCase):
    def test_default_ocr_language_preserves_vietnamese_diacritics(self):
        with patch.dict(engine.os.environ, {}, clear=True):
            self.assertEqual(engine.ocr_languages(), "vie")

    def test_only_installed_ocr_language_options_are_allowed(self):
        for languages in ("vie", "eng", "vie+eng", "eng+vie"):
            with patch.dict(engine.os.environ, {"KYC_LOCAL_OCR_LANGUAGES": languages}):
                self.assertEqual(engine.ocr_languages(), languages)
        for languages in ("", "fra", "vie+fra", "../eng", "eng --psm 6"):
            with patch.dict(engine.os.environ, {"KYC_LOCAL_OCR_LANGUAGES": languages}):
                self.assertRaises(ValueError, engine.ocr_languages)

    def test_invalid_language_preserves_face_and_does_not_start_tesseract(self):
        operations = object.__new__(engine.LocalOperations)
        operations.cv = SimpleNamespace(
            imencode=lambda extension, image: (
                True,
                SimpleNamespace(tobytes=lambda: b"encoded image"),
            )
        )
        image = SimpleNamespace(shape=(100, 100, 3))
        operations.decode = lambda data: image
        operations.compare = (
            lambda document, selfie, threshold: engine.face_score_result(0.8, threshold)
        )
        with patch.dict(engine.os.environ, {"KYC_LOCAL_OCR_LANGUAGES": "invalid"}):
            with patch.object(engine.subprocess, "run") as run:
                result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
                run.assert_not_called()
        self.assertEqual(result["ocr"]["status"], "failed")
        self.assertEqual(result["faceMatch"]["status"], "matched")

    def operations(self, detections, cosine=0.8):
        sizes, crops = [], []
        pending = iter(detections)
        detector = SimpleNamespace(
            setInputSize=lambda size: sizes.append(size),
            detect=lambda image: (1, next(pending)),
        )

        def crop(image, face):
            crops.append((image, face))
            return image

        recognizer = SimpleNamespace(
            alignCrop=crop,
            feature=lambda image: SimpleNamespace(copy=lambda: image),
            match=lambda a, b, metric: cosine,
        )
        operations = object.__new__(engine.LocalOperations)
        operations.cv = SimpleNamespace(
            FaceDetectorYN=SimpleNamespace(create=lambda *args: detector),
            FaceRecognizerSF=SimpleNamespace(create=lambda *args: recognizer),
            FaceRecognizerSF_FR_COSINE=0,
        )
        return operations, sizes, crops

    def test_landmark_aligned_faces_only_after_exactly_one_detection(self):
        operations, sizes, crops = self.operations([["document-face"], ["selfie-face"]])
        document = SimpleNamespace(shape=(500, 800, 3))
        selfie = SimpleNamespace(shape=(800, 600, 3))
        result = operations.compare(document, selfie, 36.3)
        self.assertEqual(sizes, [(800, 500), (600, 800)])
        self.assertEqual(crops, [(document, "document-face"), (selfie, "selfie-face")])
        self.assertEqual(result["status"], "matched")
        self.assertEqual(result["similarity"], 80)

    def test_multi_face_image_never_extracts_or_compares_embedding(self):
        operations, sizes, crops = self.operations([["face1", "face2"], ["face3"]])
        image = SimpleNamespace(shape=(500, 800, 3))
        result = operations.compare(image, image, 36.3)
        self.assertEqual(result["status"], "multiple_faces")
        self.assertEqual(crops, [])

    def test_missing_face_never_extracts_embedding(self):
        operations, sizes, crops = self.operations([None, ["face"]])
        image = SimpleNamespace(shape=(500, 800, 3))
        self.assertEqual(operations.compare(image, image, 36.3)["status"], "no_face")
        self.assertEqual(crops, [])

    def test_tesseract_exec_has_deadline_and_uses_memory_only(self):
        operations = object.__new__(engine.LocalOperations)
        operations.cv = SimpleNamespace(
            imencode=lambda extension, image: (
                True,
                SimpleNamespace(tobytes=lambda: b"fake encoded image"),
            )
        )
        image = SimpleNamespace(shape=(100, 100, 3))

        def run(command, **kwargs):
            self.assertEqual(command[1], "stdin")
            self.assertEqual(command[command.index("--psm") + 1], "3")
            self.assertIn("tessedit_create_tsv=1", command)
            self.assertNotEqual(command[-1], "tsv")
            self.assertEqual(kwargs["input"], b"fake encoded image")
            self.assertEqual(kwargs["timeout"], 4)
            self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
            return SimpleNamespace(stdout=tsv(["Họ và tên: NGUYỄN VĂN AN"]).encode())

        with patch.object(engine.subprocess, "run", side_effect=run):
            result = operations.ocr(image)
        self.assertEqual(result["status"], "succeeded")


class FaceResultTests(unittest.TestCase):
    def test_exactly_one_face_in_each_input(self):
        self.assertEqual(engine.face_count_status([1, 2]), "multiple_faces")
        self.assertEqual(engine.face_count_status([0, 1]), "no_face")
        self.assertEqual(engine.face_count_status([0, 2]), "multiple_faces")
        self.assertIsNone(engine.face_count_status([1, 1]))

    def test_cosine_score_is_not_probability(self):
        self.assertEqual(engine.face_score_result(0.363, 36.3)["status"], "matched")
        self.assertEqual(engine.face_score_result(0.2, 36.3)["status"], "not_matched")
        self.assertEqual(engine.face_score_result(-0.5, 36.3)["similarity"], 0)
        self.assertEqual(engine.face_score_result(1.2, 36.3)["similarity"], 100)
        self.assertRaises(ValueError, engine.face_score_result, math.nan, 36.3)

    def test_rounding_never_turns_below_threshold_match_into_positive(self):
        result = engine.face_score_result(0.36299999, 36.3)
        self.assertLess(result["similarity"], 36.3)
        self.assertEqual(result["status"], "not_matched")


if __name__ == "__main__":
    unittest.main()
