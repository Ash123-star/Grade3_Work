"""Synthetic Chinese fixtures; local OCR evidence only, never claims model acceptance."""
import base64
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

root = Path(__file__).resolve().parents[1]
folder = root / "output/ai-work-samples"
folder.mkdir(exist_ok=True)
font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 38)
image = Image.new("RGB", (1080, 650), "white")
draw = ImageDraw.Draw(image)
lines = ["请小李在2026年11月1日17:00交付成本表", "交付要求：提供成本明细和总价", "金额：1250.00元"]
for index, line in enumerate(lines):
    draw.text((40, 70 + index * 100), line, font=font, fill="black")
path = folder / "clear-task.png"
image.save(path)
payload = base64.b64encode(path.read_bytes())
program = """
import base64,sys,json,time,urllib.request
data=base64.b64decode(sys.stdin.buffer.read())
t=time.perf_counter()
r=urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8000/extract',data=data,headers={'Content-Type':'application/octet-stream'}),timeout=40)
d=json.load(r);d['elapsedSeconds']=round(time.perf_counter()-t,3)
print(json.dumps(d,ensure_ascii=True))
"""
result = subprocess.run(["docker", "exec", "-i", "workpanel-ai-ocr", "python", "-c", program], input=payload, capture_output=True, timeout=45, check=True)
data = json.loads(result.stdout)
data["fixture"] = lines
data["exactText"] = "".join(p["text"] for p in data["parts"]) == "".join(lines)
(folder / "ocr-smoke.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"exactText": data["exactText"], "unverifiable": data["unverifiable"], "elapsedSeconds": data["elapsedSeconds"]}))
