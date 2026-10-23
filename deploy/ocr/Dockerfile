FROM python:3.11-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 OMP_NUM_THREADS=2
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock && pip check
# Download official Paddle models while building; runtime is an internal-only network.
COPY prepare_models.py .
RUN python prepare_models.py
COPY app.py .
RUN useradd --uid 10001 --create-home worker && cp -a /root/.paddlex /home/worker/.paddlex && chown -R worker:worker /home/worker
USER worker
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log"]
