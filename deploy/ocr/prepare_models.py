"""Fetch official Paddle resources only while building, with bounded retries."""
import time
import requests

original_get = requests.get


def model_get(*args, **kwargs):
    kwargs["timeout"] = (20, 120)
    return original_get(*args, **kwargs)


requests.get = model_get
for attempt in range(3):
    try:
        from paddleocr import PaddleOCR
        PaddleOCR(lang="ch", use_doc_orientation_classify=False,
                  use_doc_unwarping=False, use_textline_orientation=False)
        break
    except (requests.RequestException, RuntimeError):
        if attempt == 2:
            raise
        time.sleep(2)
