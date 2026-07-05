FROM python:3.13-slim
RUN useradd --system --no-create-home hello
COPY src/app.py /app/app.py
USER hello
EXPOSE 8000
CMD ["python", "/app/app.py"]
