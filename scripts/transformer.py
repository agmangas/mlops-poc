import argparse
import logging
import pprint
from typing import Dict

import coloredlogs
import joblib
import kserve
from kserve.kfmodel_repository import KFModelRepository

_logger = logging.getLogger(__name__)


class SklearnTransformer(kserve.KFModel):
    def __init__(self, name: str, predictor_host: str, transformer_path: str):
        _logger.info("Initializing %s instance: %s", self.__class__, name)
        super().__init__(name)
        _logger.info("Predictor host: %s", predictor_host)
        self.predictor_host = predictor_host
        self.explainer_host = predictor_host
        _logger.info("Loading transformer: %s", transformer_path)
        self._transformer = joblib.load(transformer_path)

    def _transform(self, item):
        transformed = self._transformer.transform(item)

        try:
            return transformed.toarray().flatten().tolist()
        except:
            return transformed.flatten().tolist()

    def preprocess(self, inputs: Dict) -> Dict:
        _logger.debug(
            "Preprocess request:\n%s",
            pprint.pformat(inputs))

        return {
            "instances": [
                self._transform(item) for item in inputs["instances"]
            ]
        }


class TransformerModelRepository(KFModelRepository):
    def __init__(self, predictor_host: str):
        super().__init__()
        _logger.info("Initializing %s instance", self.__class__)
        self.predictor_host = predictor_host


def parse_options():
    parser = argparse.ArgumentParser(parents=[kserve.kfserver.parser])

    parser.add_argument("--predictor_host", required=True)
    parser.add_argument("--model_name", required=True)

    parser.add_argument(
        "--transformer-path",
        default="/mnt/models/transformer.joblib")

    parser.add_argument("--log-level", default="DEBUG")

    args, _ = parser.parse_known_args()

    return args


def main():
    args = parse_options()
    coloredlogs.install(level=args.log_level)

    _logger.debug("Arguments: %s", args)

    models = [
        SklearnTransformer(
            name=args.model_name,
            predictor_host=args.predictor_host,
            transformer_path=args.transformer_path)
    ]

    _logger.info("Starting KFserver with models: %s", models)

    registered_models = TransformerModelRepository(args.predictor_host)
    kf_server = kserve.KFServer(registered_models=registered_models)
    kf_server.start(models=models)


if __name__ == "__main__":
    main()
