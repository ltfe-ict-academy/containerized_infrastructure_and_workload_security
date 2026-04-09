FROM python:3.12-slim-bookworm AS builder

ENV PATH=/opt/venv/bin:$PATH

WORKDIR /build

RUN python -m venv /opt/venv

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim-bookworm

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY app.py ./app.py

RUN groupadd --system app \
    && useradd --system --gid app --create-home --home-dir /home/app app \
    && chown -R app:app /app

USER app

EXPOSE 8000

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "4", "app:app"]
