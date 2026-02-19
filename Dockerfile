FROM python:3.11-slim

WORKDIR /app

# Install backend dependencies
COPY ai/backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copy backend code
COPY ai/backend /app

ENV PYTHONUNBUFFERED=1

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port $PORT"]
