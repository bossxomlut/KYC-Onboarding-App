# Local identity engine dependencies

Models and trained language data are downloaded by the setup script into Git-ignored `backend/.local/identity-models`; they are not bundled with the mobile app or committed here. Preserve the source licenses if redistributing these assets.

| Component | Source | License |
| --- | --- | --- |
| YuNet face detector, `face_detection_yunet_2023mar.onnx` | [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) | [MIT; Copyright (c) 2020 Shiqi Yu](https://github.com/opencv/opencv_zoo/blob/main/models/face_detection_yunet/LICENSE) |
| SFace recognizer, `face_recognition_sface_2021dec.onnx` | [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) | [Apache 2.0](https://github.com/opencv/opencv_zoo/blob/main/models/face_recognition_sface/LICENSE) |
| Tesseract OCR and `tessdata_fast` `vie`/`eng` | [Tesseract](https://github.com/tesseract-ocr/tesseract), [trained data](https://github.com/tesseract-ocr/tessdata_fast) | [Apache 2.0](https://github.com/tesseract-ocr/tessdata_fast/blob/main/LICENSE) |
| OpenCV Python headless / NumPy | Versions pinned in `requirements.txt` | [OpenCV package notes](https://github.com/opencv/opencv-python#licensing), [NumPy BSD license](https://github.com/numpy/numpy/blob/main/LICENSE.txt) |

The default SFace threshold uses cosine0.363 from the [OpenCV tutorial](https://docs.opencv.org/4.x/d0/dd4/tutorial_dnn_face.html). It is a development starting value, not a calibrated KYC approval policy. Models are used for a single requested document/selfie comparison; the engine stores no face collection or embeddings.
