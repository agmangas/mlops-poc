import argparse
import logging
import os
import random
import tempfile
import urllib.request

import boto3
import coloredlogs
import sh
import yaml
from botocore.client import Config

_REGION = "eu-west-1"
_SIGNATURE_VERSION = "s3v4"
_DEFAULT_MODEL_URL = "https://storage.googleapis.com/kfserving-samples/models/sklearn/iris/model.joblib"

_logger = logging.getLogger()


def parse_options():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--minio-endpoint-cluster",
        default="minio-service.tenant-tiny:9000")

    parser.add_argument(
        "--minio-endpoint",
        default="http://localhost:30100")

    parser.add_argument("--log-level", default="DEBUG")
    parser.add_argument("--access-key", default="minio")
    parser.add_argument("--secret-key", default="minio123")
    parser.add_argument("--model-path", default=None)
    parser.add_argument("--model-name", default=None)
    parser.add_argument("--bucket",  default=None)
    parser.add_argument("--namespace",  default=None)
    parser.add_argument("--transformer-path", default=None)
    parser.add_argument("--transformer-image", default=None)

    args = parser.parse_args()

    return args


def get_default_model():
    temp_dir = tempfile.mkdtemp()
    model_path = os.path.join(temp_dir, "model.joblib")

    _logger.info(
        "Downloading default model %s to %s",
        _DEFAULT_MODEL_URL, model_path)

    urllib.request.urlretrieve(_DEFAULT_MODEL_URL, model_path)

    return model_path


def build_s3_secrets(minio_endpoint, access_key, secret_key, secret_name="s3creds", sa_name="sa"):
    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {
            "name": secret_name,
            "annotations": {
                "serving.kserve.io/s3-endpoint": minio_endpoint,
                "serving.kserve.io/s3-usehttps": "0",
                "serving.kserve.io/s3-region": _REGION,
                "serving.kserve.io/s3-useanoncredential": "false"
            }
        },
        "type": "Opaque",
        "stringData": {
            "AWS_ACCESS_KEY_ID": access_key,
            "AWS_SECRET_ACCESS_KEY": secret_key
        }
    }

    service_account = {
        "apiVersion": "v1",
        "kind": "ServiceAccount",
        "metadata": {
            "name": sa_name
        },
        "secrets": [
            {"name": secret_name}
        ]
    }

    temp_dir = tempfile.mkdtemp()
    file_path = os.path.join(temp_dir, "s3-secrets.yaml")

    content = "{}---\n{}".format(
        yaml.dump(secret),
        yaml.dump(service_account))

    with open(file_path, "w") as fh:
        fh.write(content)

    _logger.debug("S3 secrets file %s:\n%s", file_path, content)

    return file_path


def build_inference_service(model_name, bucket_name, sa_name="sa", transformer_image=None):
    inference_service = {
        "apiVersion": "serving.kserve.io/v1beta1",
        "kind": "InferenceService",
        "metadata": {
            "name": model_name
        },
        "spec": {
            "predictor": {
                "serviceAccountName": sa_name,
                "sklearn": {
                    "storageUri": f"s3://{bucket_name}"
                }
            }
        }
    }

    if transformer_image:
        inference_service["spec"].update({
            "transformer": {
                "serviceAccountName": sa_name,
                "containers": [{
                    "image": transformer_image,
                    "name": f"{model_name}-transformer",
                    "env": [{
                        "name": "STORAGE_URI",
                        "value": f"s3://{bucket_name}/transformer.joblib"
                    }]
                }]
            }
        })

    temp_dir = tempfile.mkdtemp()
    file_path = os.path.join(temp_dir, "inference-service.yaml")
    content = yaml.dump(inference_service)

    with open(file_path, "w") as fh:
        fh.write(content)

    _logger.debug("Inference Service file %s:\n%s", file_path, content)

    return file_path


def main():
    args = parse_options()
    coloredlogs.install(level=args.log_level)

    _logger.debug("Arguments: %s", args)
    
    if args.transformer_path:
        assert args.transformer_image, "Undefined transformer image"

    s3 = boto3.resource(
        "s3",
        endpoint_url=args.minio_endpoint,
        aws_access_key_id=args.access_key,
        aws_secret_access_key=args.secret_key,
        config=Config(signature_version=_SIGNATURE_VERSION),
        region_name=_REGION)

    rand_key = int(random.random() * 1e6)

    model_path = args.model_path or get_default_model()
    model_name = args.model_name or f"model-{rand_key}"
    _logger.info("Using model %s from %s", model_name, model_path)

    bucket_name = args.bucket or model_name
    bucket = s3.create_bucket(Bucket=bucket_name)
    _logger.info("Created bucket: %s", bucket)

    bucket.upload_file(model_path, "model.joblib")
    _logger.info("Uploaded model: %s", model_path)

    if args.transformer_path:
        bucket.upload_file(args.transformer_path, "transformer.joblib")
        _logger.info("Uploaded transformer: %s", args.transformer_path)

    namespace = args.namespace or f"kserve-{rand_key}"

    sh.kubectl("create", "namespace", namespace)

    s3_secrets_config = build_s3_secrets(
        minio_endpoint=args.minio_endpoint_cluster,
        access_key=args.access_key,
        secret_key=args.secret_key)

    sh.kubectl("apply", "-n", namespace, "-f", s3_secrets_config)

    transformer_image = args.transformer_image if args.transformer_path else None

    inf_serv_config = build_inference_service(
        model_name=model_name,
        bucket_name=bucket_name,
        transformer_image=transformer_image)

    sh.kubectl("apply", "-n", namespace, "-f", inf_serv_config)


if __name__ == "__main__":
    main()
