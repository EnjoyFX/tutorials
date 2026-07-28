FROM python:3.13-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY app.py .

RUN addgroup -S -g 1001 appuser \
    && adduser -S -D -H -u 1001 -G appuser appuser
USER 1001:1001

EXPOSE 8080

CMD ["python", "app.py"]
