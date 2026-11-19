FROM python:3.11-slim

WORKDIR /app
RUN pip install --no-cache-dir flask
COPY app.py usage.py ./

EXPOSE 5055
CMD ["python", "app.py"]
