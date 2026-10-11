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

    def test_noisy_bilingual_cccd_labels_preserve_values_from_ocr(self):
        result = engine.parse_tsv(
            tsv(
                [
                    "CĂN CƯỚC CÔNG DÂN",
                    "Số/Ao-. 000000000000",
                    "Họ và tên / Full name:",
                    "NGUYỄN VĂN MẪU",
                    "Ngày sinh / Dafe of birth: - 15/06/1995",
                ]
            )
        )
        self.assertEqual(
            result["fields"],
            {
                "fullName": "NGUYỄN VĂN MẪU",
                "dateOfBirth": "1995-06-15",
                "documentNumber": "000000000000",
            },
        )

    def test_missing_space_in_cccd_label_preserves_digit_spacing_and_zeros(self):
        result = engine.parse_tsv(tsv(["SốCCCD: 0001 23456789"]))
        self.assertEqual(result["fields"]["documentNumber"], "0001 23456789")

    def test_noise_before_labeled_birth_date_is_only_separator_punctuation(self):
        result = engine.parse_tsv(
            tsv(["Ngày sinh / Date of birth: - 15/06/1995"])
        )
        self.assertEqual(result["fields"]["dateOfBirth"], "1995-06-15")

    def test_noisy_birth_labels_do_not_accept_impossible_or_ambiguous_dates(self):
        for value in (
            "- 31/02/1995",
            "- 15/06/1995 16/06/1995",
            "- 15/06/1995 hoặc 16/06/1995",
            "- 15/06/2090",
            "- Có giá trị đến / Date of expiry: 15/06/1995",
        ):
            with self.subTest(value=value):
                result = engine.parse_tsv(
                    tsv([f"Ngày sinh / Dafe of birth: {value}"])
                )
                self.assertIsNone(result["fields"]["dateOfBirth"])

    def test_noisy_labels_do_not_guess_unlabeled_or_expiry_values(self):
        result = engine.parse_tsv(
            tsv(
                [
                    "Số điện thoại: 0901234567",
                    "Số nhà: 123456789012",
                    "Có giá trị đến / Date of expiry: 15/06/1995",
                    "000000000000",
                    "15/06/1995",
                ]
            )
        )
        self.assertEqual(result["fields"], engine.empty_fields())

    def test_noisy_number_label_does_not_repair_ocr_digit_characters(self):
        result = engine.parse_tsv(tsv(["Số/Ao-. 00012345678O"]))
        self.assertIsNone(result["fields"]["documentNumber"])

    def test_secondary_number_label_does_not_reinterpret_other_number_fields(self):
        for label in ("Phone", "Tel.", "Điện thoại", "House no.", "Account no."):
            with self.subTest(label=label):
                result = engine.parse_tsv(tsv([f"Số / {label}: 123456789012"]))
                self.assertIsNone(result["fields"]["documentNumber"])

    def test_empty_name_does_not_consume_recovered_field_on_next_line(self):
        for following in (
            "Số/Ao-. 000000000000",
            "Ngày sinh / Dafe of birth - 15/06/1995",
        ):
            with self.subTest(following=following):
                result = engine.parse_tsv(tsv(["Họ và tên:", following]))
                self.assertIsNone(result["fields"]["fullName"])

    def test_noisy_birth_label_does_not_repair_ocr_date_characters(self):
        result = engine.parse_tsv(
            tsv(["Ngày sinh / Dafe of birth: 15/O6/1995"])
        )
        self.assertIsNone(result["fields"]["dateOfBirth"])

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
        self.assertEqual(result["selfieFace"], {"status": "failed"})
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertNotIn("SECRET", stdout.getvalue())

    def test_jpeg_dimensions_checked_before_decode(self):
        safe = b"\xff\xd8\xff\xc0\x00\x0b\x08\x00\x64\x00\xc8\x01\x01\x11\x00\xff\xd9"
        self.assertEqual(engine.image_dimensions(safe), (200, 100))
        huge = safe.replace(b"\x00\x64\x00\xc8", b"\xff\xff\xff\xff")
        self.assertRaises(ValueError, engine.image_dimensions, huge)
        self.assertRaises(ValueError, engine.image_dimensions, b"not an image")


class FakeOperations:
    def __init__(
        self,
        ocr_error=False,
        face_error=False,
        document_faces=1,
        selfie_faces=1,
        document_error=False,
        selfie_error=False,
    ):
        self.ocr_error = ocr_error
        self.face_error = face_error
        self.document_faces = document_faces
        self.selfie_faces = selfie_faces
        self.document_error = document_error
        self.selfie_error = selfie_error
        self.detections = []
        self.comparisons = []

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

    def detect_faces(self, image):
        self.detections.append(image)
        selfie = image == b"selfie"
        error = self.selfie_error if selfie else self.document_error
        if error:
            raise RuntimeError("private face detector detail")
        count = self.selfie_faces if selfie else self.document_faces
        return image, [f"face-{number}" for number in range(count)]

    def compare_faces(self, document, selfie, threshold):
        self.comparisons.append((document, selfie))
        return self.compare(document, selfie, threshold)


class SelfiePresenceTests(unittest.TestCase):
    def test_single_selfie_remains_detected_when_document_has_no_face(self):
        operations = FakeOperations(document_faces=0)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "no_face")
        self.assertEqual(operations.comparisons, [])

    def test_single_selfie_remains_detected_when_document_cannot_decode(self):
        operations = FakeOperations()
        operations.decode = (
            lambda data: data
            if data == b"selfie"
            else (_ for _ in ()).throw(ValueError())
        )
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["ocr"]["status"], "failed")
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertEqual(operations.detections, [b"selfie"])

    def test_blank_selfie_reports_no_face_and_skips_document_detection(self):
        operations = FakeOperations(selfie_faces=0, document_error=True)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "no_face"})
        self.assertEqual(result["faceMatch"]["status"], "no_face")
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(operations.detections, [b"selfie"])
        self.assertEqual(operations.comparisons, [])

    def test_multiple_selfie_faces_report_multiple_faces_and_skip_comparison(self):
        operations = FakeOperations(selfie_faces=2, document_faces=0)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "multiple_faces"})
        self.assertEqual(result["faceMatch"]["status"], "multiple_faces")
        self.assertEqual(operations.detections, [b"selfie"])
        self.assertEqual(operations.comparisons, [])

    def test_document_detector_error_does_not_erase_valid_selfie(self):
        operations = FakeOperations(document_error=True)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertEqual(operations.detections, [b"selfie", b"doc"])

    def test_multiple_document_faces_preserve_valid_selfie_and_skip_comparison(self):
        operations = FakeOperations(document_faces=2)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "multiple_faces")
        self.assertEqual(operations.comparisons, [])

    def test_comparison_error_does_not_erase_valid_selfie(self):
        operations = FakeOperations(face_error=True)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertEqual(operations.detections, [b"selfie", b"doc"])

    def test_selfie_detector_error_preserves_ocr_and_skips_comparison(self):
        operations = FakeOperations(selfie_error=True)
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "failed"})
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(operations.detections, [b"selfie"])
        self.assertEqual(operations.comparisons, [])

    def test_success_detects_each_image_once(self):
        operations = FakeOperations()
        result = engine.verify_images(b"doc", b"selfie", 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "matched")
        self.assertEqual(operations.detections, [b"selfie", b"doc"])
        self.assertEqual(len(operations.comparisons), 1)


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
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "failed")

    def test_invalid_selfie_preserves_document_ocr(self):
        operations = FakeOperations()
        operations.decode = (
            lambda data: data if data == b"doc" else (_ for _ in ()).throw(ValueError())
        )
        result = engine.verify_images(b"doc", b"invalid", 36.3, operations)
        self.assertEqual(result["ocr"]["status"], "succeeded")
        self.assertEqual(result["selfieFace"], {"status": "failed"})
        self.assertEqual(result["faceMatch"]["status"], "failed")

    def test_independent_checks_run_concurrently_within_request_deadline(self):
        operations = FakeOperations()
        barrier = threading.Barrier(2)
        original_ocr, original_compare = operations.ocr, operations.compare_faces

        def ocr(image):
            barrier.wait(timeout=1)
            return original_ocr(image)

        def compare(document, selfie, threshold):
            barrier.wait(timeout=1)
            return original_compare(document, selfie, threshold)

        operations.ocr, operations.compare_faces = ocr, compare
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
        operations.detect_faces = lambda image: (image, ["face"])
        operations.compare_faces = (
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
        operations, sizes, crops = self.operations([["selfie-face"], ["document-face"]])
        document = SimpleNamespace(shape=(500, 800, 3))
        selfie = SimpleNamespace(shape=(800, 600, 3))
        result = engine.verify_faces(document, selfie, 36.3, operations)["faceMatch"]
        self.assertEqual(sizes, [(600, 800), (800, 500)])
        self.assertEqual(crops, [(document, "document-face"), (selfie, "selfie-face")])
        self.assertEqual(result["status"], "matched")
        self.assertEqual(result["similarity"], 80)

    def test_selfie_detection_survives_native_recognizer_creation_failure(self):
        operations, sizes, crops = self.operations([["selfie-face"], ["document-face"]])
        image = SimpleNamespace(shape=(500, 800, 3))
        with patch.object(
            operations.cv.FaceRecognizerSF,
            "create",
            side_effect=RuntimeError("private model path"),
        ):
            result = engine.verify_faces(image, image, 36.3, operations)
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "failed")
        self.assertEqual(len(sizes), 2)
        self.assertEqual(crops, [])

    def test_selfie_landmarks_are_copied_before_document_detection_reuses_buffer(self):
        shared_faces = ["selfie-face"]
        operations, sizes, crops = self.operations([shared_faces, shared_faces])
        detector = operations.cv.FaceDetectorYN.create()
        calls = 0

        def detect(image):
            nonlocal calls
            if calls:
                shared_faces[0] = "document-face"
            calls += 1
            return 1, shared_faces

        detector.detect = detect
        image = SimpleNamespace(shape=(500, 800, 3))
        with patch.object(
            operations.cv.FaceDetectorYN, "create", return_value=detector
        ) as create:
            result = engine.verify_faces(image, image, 36.3, operations)
            create.assert_called_once()
        self.assertEqual(result["selfieFace"], {"status": "detected"})
        self.assertEqual(result["faceMatch"]["status"], "matched")
        self.assertEqual(crops, [(image, "document-face"), (image, "selfie-face")])

    def test_multi_face_image_never_extracts_or_compares_embedding(self):
        operations, sizes, crops = self.operations([["face1", "face2"], ["face3"]])
        image = SimpleNamespace(shape=(500, 800, 3))
        result = engine.verify_faces(image, image, 36.3, operations)["faceMatch"]
        self.assertEqual(result["status"], "multiple_faces")
        self.assertEqual(crops, [])

    def test_missing_face_never_extracts_embedding(self):
        operations, sizes, crops = self.operations([None, ["face"]])
        image = SimpleNamespace(shape=(500, 800, 3))
        self.assertEqual(
            engine.verify_faces(image, image, 36.3, operations)["faceMatch"]["status"],
            "no_face",
        )
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
