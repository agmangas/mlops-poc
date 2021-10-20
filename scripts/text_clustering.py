# Based on the following scikit-learn example:
# https://scikit-learn.org/stable/auto_examples/text/plot_document_clustering.html#sphx-glr-auto-examples-text-plot-document-clustering-py

import argparse
import logging
import os
import pprint
from time import time

import coloredlogs
import joblib
import numpy as np
from sklearn import metrics
from sklearn.cluster import KMeans, MiniBatchKMeans
from sklearn.datasets import fetch_20newsgroups
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import Normalizer

_N_FEATURES = 10000

_logger = logging.getLogger()


def load_dataset(categories=None):
    _logger.info("Loading dataset categories: %s", categories)

    dataset = fetch_20newsgroups(
        subset="all",
        categories=categories,
        shuffle=True,
        random_state=42)

    _logger.info("%d documents" % len(dataset.data))
    _logger.info("Categories: %s", dataset.target_names)

    return dataset


def extract_features(dataset):
    t0 = time()

    _logger.info("Extracting features")

    vectorizer = TfidfVectorizer(
        max_df=0.5,
        max_features=_N_FEATURES,
        min_df=2,
        stop_words="english",
        use_idf=True)

    X = vectorizer.fit_transform(dataset.data)

    _logger.info("Done in %fs" % (time() - t0))

    try:
        _logger.debug("Feature names: %s", vectorizer.get_feature_names())
    except:
        pass

    _logger.info("n_samples: %d, n_features: %d" % X.shape)

    return X, vectorizer


def perform_dimensionality_reduction(X, n_components):
    t0 = time()

    _logger.info("Performing dimensionality reduction")

    # Vectorizer results are normalized, which makes KMeans behave as
    # spherical k-means for better results. Since LSA/SVD results are
    # not normalized, we have to redo the normalization.
    svd = TruncatedSVD(n_components)
    normalizer = Normalizer(copy=False)
    lsa = make_pipeline(svd, normalizer)

    X = lsa.fit_transform(X)

    _logger.info("Done in %fs" % (time() - t0))

    explained_variance = svd.explained_variance_ratio_.sum()

    _logger.info(
        "Explained variance of the SVD step: %s%%",
        int(explained_variance * 100))

    return X, svd


def fit_clustering(X, n_clusters, labels, minibatch, verbose):
    if minibatch:
        km = MiniBatchKMeans(
            n_clusters=n_clusters,
            init="k-means++",
            n_init=1,
            init_size=1000,
            batch_size=1000,
            verbose=verbose)
    else:
        km = KMeans(
            n_clusters=n_clusters,
            init="k-means++",
            max_iter=100,
            n_init=1,
            verbose=verbose)

    _logger.info("Clustering sparse data with %s" % km)

    t0 = time()
    km.fit(X)

    _logger.info("Done in %0.3fs" % (time() - t0))

    _logger.info(
        "Homogeneity: %0.3f" %
        metrics.homogeneity_score(labels, km.labels_))

    _logger.info(
        "Completeness: %0.3f" %
        metrics.completeness_score(labels, km.labels_))

    _logger.info(
        "V-measure: %0.3f" %
        metrics.v_measure_score(labels, km.labels_))

    _logger.info(
        "Adjusted Rand-Index: %.3f"
        % metrics.adjusted_rand_score(labels, km.labels_))

    _logger.info(
        "Silhouette Coefficient: %0.3f"
        % metrics.silhouette_score(X, km.labels_, sample_size=1000))

    return km


def parse_options():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--lsa",
        dest="n_components", type=int,
        help="Preprocess documents with latent semantic analysis.")

    parser.add_argument(
        "--no-minibatch",
        action="store_false", dest="minibatch", default=True,
        help="Use ordinary k-means algorithm (in batch mode).")

    parser.add_argument(
        "--verbose",
        action="store_true", dest="verbose", default=False,
        help="Print progress reports inside k-means algorithm.")

    parser.add_argument("--log-level", default="DEBUG")
    parser.add_argument("--output-dir", default=None)

    args = parser.parse_args()

    return args


def log_cluster_top_terms(args, svd, km, vectorizer, n_clusters, n_terms=10):
    if args.n_components and svd:
        original_space_centroids = svd.inverse_transform(
            km.cluster_centers_)

        order_centroids = original_space_centroids.argsort()[:, ::-1]
    else:
        order_centroids = km.cluster_centers_.argsort()[:, ::-1]

    terms = vectorizer.get_feature_names()

    top_terms = {
        "Cluster {:02d}".format(i): " ".join([
            terms[ind] for ind in order_centroids[i, :n_terms]
        ]) for i in range(n_clusters)
    }

    _logger.debug("Top terms per cluster:\n%s", pprint.pformat(top_terms))


def main():
    args = parse_options()
    coloredlogs.install(level=args.log_level)

    _logger.debug("Arguments: %s", args)

    dataset = load_dataset()
    labels = dataset.target
    n_clusters = np.unique(labels).shape[0]
    X, vectorizer = extract_features(dataset=dataset)
    svd = None

    if args.n_components:
        X, svd = perform_dimensionality_reduction(
            X=X,
            n_components=args.n_components)

    km = fit_clustering(
        X=X,
        n_clusters=n_clusters,
        labels=labels,
        minibatch=args.minibatch,
        verbose=args.verbose)

    transformer = make_pipeline(vectorizer, svd) if svd else vectorizer

    if args.output_dir:
        model_path = os.path.join(args.output_dir, "model.joblib")
        _logger.info("Saving model: %s", model_path)
        joblib.dump(km, model_path)
        transformer_path = os.path.join(args.output_dir, "transformer.joblib")
        _logger.info("Saving vectorizer: %s", transformer_path)
        joblib.dump(transformer, transformer_path)

    log_cluster_top_terms(args, svd, km, vectorizer, n_clusters)

    test_doc = "mac apple rom scsi disk windows pc"
    features = transformer.transform([test_doc])
    prediction = km.predict(features)
    _logger.debug("Example: '%s' -> Cluster %s", test_doc, prediction)


if __name__ == "__main__":
    main()
