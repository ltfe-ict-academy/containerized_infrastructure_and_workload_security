# syntax=docker/dockerfile:1

FROM python:3.14-slim AS build
WORKDIR /app

COPY requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

FROM python:3.14-slim AS runtime
WORKDIR /app

ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY --from=build /opt/venv /opt/venv
COPY app.py .

EXPOSE 8000
CMD ["python", "app.py"]
