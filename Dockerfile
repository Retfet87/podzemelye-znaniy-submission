FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
LABEL org.opencontainers.image.source="https://github.com/Retfet87/podzemelye-znaniy-submission"
LABEL org.opencontainers.image.base.source="https://github.com/Retfet87/podzemelye-znaniy/tree/e03fdd4f7beb65329b99891cdab1eb4f1d448d1a"
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
COPY migrations/ ./migrations/
COPY certificates/ ./certificates/
COPY assets/ ./assets/
COPY main.py manage.py ./
USER 10001:10001
CMD ["python", "main.py"]
