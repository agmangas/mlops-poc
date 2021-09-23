# Based on the following scikit-learn example:
# https://scikit-learn.org/stable/auto_examples/text/plot_document_clustering.html#sphx-glr-auto-examples-text-plot-document-clustering-py

import logging
import pprint
import sys
from optparse import OptionParser
from time import time

import coloredlogs
import numpy as np
from sklearn import metrics
from sklearn.cluster import KMeans, MiniBatchKMeans
from sklearn.datasets import fetch_20newsgroups
from sklearn.decomposition import TruncatedSVD
from sklearn.feature_extraction.text import (HashingVectorizer,
                                             TfidfTransformer, TfidfVectorizer)
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import Normalizer

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


def extract_features(dataset, use_hashing, use_idf, n_features):
    t0 = time()

    _logger.info("Extracting features")

    if use_hashing:
        if use_idf:
            # Perform an IDF normalization on the output of HashingVectorizer
            hasher = HashingVectorizer(
                n_features=n_features,
                stop_words="english",
                alternate_sign=False,
                norm=None)

            vectorizer = make_pipeline(hasher, TfidfTransformer())
        else:
            vectorizer = HashingVectorizer(
                n_features=n_features,
                stop_words="english",
                alternate_sign=False,
                norm="l2")
    else:
        vectorizer = TfidfVectorizer(
            max_df=0.5,
            max_features=n_features,
            min_df=2,
            stop_words="english",
            use_idf=use_idf)

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
    op = OptionParser()

    op.add_option(
        "--lsa",
        dest="n_components", type="int",
        help="Preprocess documents with latent semantic analysis.")

    op.add_option(
        "--no-minibatch",
        action="store_false", dest="minibatch", default=True,
        help="Use ordinary k-means algorithm (in batch mode).")

    op.add_option(
        "--no-idf",
        action="store_false", dest="use_idf", default=True,
        help="Disable Inverse Document Frequency feature weighting.")

    op.add_option(
        "--use-hashing",
        action="store_true", default=False,
        help="Use a hashing feature vectorizer")

    op.add_option(
        "--n-features", type=int, default=10000,
        help="Maximum number of features (dimensions)"
        " to extract from text.")

    op.add_option(
        "--verbose",
        action="store_true", dest="verbose", default=False,
        help="Print progress reports inside k-means algorithm.")

    op.add_option(
        "--log-level",
        default="DEBUG",
        help="Log level.")

    (opts, args) = op.parse_args(sys.argv[1:])

    if len(args) > 0:
        op.error("This script takes no arguments.")
        sys.exit(1)

    return opts


def main():
    opts = parse_options()
    coloredlogs.install(level=opts.log_level)
    dataset = load_dataset()
    labels = dataset.target
    n_clusters = np.unique(labels).shape[0]

    X, vectorizer = extract_features(
        dataset=dataset,
        use_hashing=opts.use_hashing,
        use_idf=opts.use_idf,
        n_features=opts.n_features)

    svd = None

    if opts.n_components:
        X, svd = perform_dimensionality_reduction(
            X=X,
            n_components=opts.n_components)

    km = fit_clustering(
        X=X,
        n_clusters=n_clusters,
        labels=labels,
        minibatch=opts.minibatch,
        verbose=opts.verbose)

    if not opts.use_hashing:
        if opts.n_components and svd:
            original_space_centroids = svd.inverse_transform(
                km.cluster_centers_)

            order_centroids = original_space_centroids.argsort()[:, ::-1]
        else:
            order_centroids = km.cluster_centers_.argsort()[:, ::-1]

        terms = vectorizer.get_feature_names()

        top_terms = {
            "Cluster {:02d}".format(i): [terms[ind] for ind in order_centroids[i, :10]]
            for i in range(n_clusters)
        }

        _logger.debug("Top terms per cluster:\n%s", pprint.pformat(top_terms))


if __name__ == "__main__":
    main()
