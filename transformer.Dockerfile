FROM python:3.7-slim
ENV PATH_APP /app
RUN apt-get update -y && apt-get install -y --no-install-recommends git
RUN pip install --no-cache-dir --upgrade pip
RUN mkdir -p ${PATH_APP}
WORKDIR ${PATH_APP}
COPY . .
RUN pip install -r ./scripts/requirements.txt
ENTRYPOINT ["python", "/app/scripts/transformer.py"]
