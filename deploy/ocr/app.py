"""Private OCR adapter. Model assets are prepared at image build, inference has no network access."""
import asyncio
import io
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor
from fastapi import FastAPI, Request, HTTPException
from PIL import Image
from paddleocr import PaddleOCR

Image.MAX_IMAGE_PIXELS = 20_000_000
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
engine = PaddleOCR(lang="ch", use_doc_orientation_classify=False,
                   use_doc_unwarping=False, use_textline_orientation=False)
pool = ThreadPoolExecutor(max_workers=1)
gate = asyncio.Semaphore(1)


def recognize(data: bytes):
    with Image.open(io.BytesIO(data)) as image:
        if image.format not in ("PNG", "JPEG") or image.width * image.height > 20_000_000:
            raise ValueError("unsupported")
        image.verify()
    path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as file:
            path = file.name
            with Image.open(io.BytesIO(data)) as image:
                image.convert("RGB").save(file, format="PNG")
        parts = []
        uncertain = False
        for result in engine.predict(path):
            texts = result.get("rec_texts", [])
            scores = result.get("rec_scores", [])
            boxes = result.get("rec_boxes", [])
            for index, text in enumerate(texts):
                score = float(scores[index])
                uncertain |= score < .92
                box = [int(v) for v in boxes[index]] if index < len(boxes) else []
                parts.append({"locator": "图片第1页", "text": text,
                              "box": box, "confidence": score, "unverifiable": score < .92})
        return {"parts": parts, "unverifiable": uncertain or not parts, "parserVersion": "paddle-3.0.3"}
    finally:
        if path and os.path.exists(path):
            os.unlink(path)


@app.post("/extract")
async def extract(request: Request):
    if gate.locked():
        raise HTTPException(429, "busy")
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > 10 * 1024 * 1024:
            raise HTTPException(413, "limit")
    async with gate:
        try:
            return await asyncio.wait_for(asyncio.get_running_loop().run_in_executor(pool, recognize, bytes(data)), 28)
        except asyncio.TimeoutError:
            # Native inference cannot be safely interrupted in a thread; supervisor restarts the isolated worker.
            os._exit(70)
        except Exception:
            raise HTTPException(422, "unreadable")


@app.get("/health")
async def health():
    return {"status": "ready"}
