FROM python:3-alpine

WORKDIR /app

COPY app.py .

RUN adduser -D -u 1001 appuser
USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
