"""Regression checks for safe, repeatable local model installation."""

import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "local_setup", Path(__file__).with_name("setup-local-verification.py")
)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class AssetInstallationTest(unittest.TestCase):
    def test_virtualenv_python_symlink_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "system-python"
            target.touch()
            link = Path(directory) / "venv/bin/python"
            link.parent.mkdir(parents=True)
            link.symlink_to(target)
            self.assertEqual(setup.absolute_path(link), link)
            self.assertNotEqual(setup.absolute_path(link), link.resolve())

    def test_verified_cached_asset_does_not_require_network(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.onnx"
            path.write_bytes(b"valid model")
            with patch.object(setup, "urlopen") as request:
                setup.install_asset(
                    path,
                    "https://example.test/model",
                    hashlib.sha256(b"valid model").hexdigest(),
                )
            request.assert_not_called()

    def test_corrupt_download_does_not_replace_existing_asset(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.onnx"
            path.write_bytes(b"previous model")
            with patch.object(setup, "urlopen", return_value=io.BytesIO(b"corrupt")):
                with self.assertRaises(ValueError):
                    setup.install_asset(
                        path,
                        "https://example.test/model",
                        hashlib.sha256(b"valid model").hexdigest(),
                    )
            self.assertEqual(path.read_bytes(), b"previous model")
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_verified_download_is_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested/model.onnx"
            with patch.object(
                setup, "urlopen", return_value=io.BytesIO(b"valid model")
            ):
                setup.install_asset(
                    path,
                    "https://example.test/model",
                    hashlib.sha256(b"valid model").hexdigest(),
                )
            self.assertEqual(path.read_bytes(), b"valid model")


if __name__ == "__main__":
    unittest.main()
