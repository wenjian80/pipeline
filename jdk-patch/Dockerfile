# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
# ORACLE DOCKERFILES PROJECT
# --------------------------
# This Dockerfile extends the Oracle WebLogic domain in home image, and applies new JDK PSU
#
# REQUIRED FILES TO BUILD THIS IMAGE
# ----------------------------------
# (1) jdk tar.gz bundle (Example: jdk-8u231-linux-x64.tar.gz)
#     Download the bundle from http://support.oracle.com
#
# REQUIRED BUILD ARGS TO BUILD THIS IMAGE
# ----------------------------------
# (1) BASE_IMAGE_PATH - The fully qualified name of the Docker image with the domain to extend
# (2) JDK_PATCH - The name of the jdk tar.gz bundle (for example jdk-8u231-linux-x64.tar.gz)
#
# HOW TO BUILD THIS IMAGE
# -----------------------
# Put all downloaded files in the same directory as this Dockerfile
# Example:
#      $ docker build -t <tag> --build-arg BASE_IMAGE_PATH=<value> --build-arg JDK_PATCH=<value> .
#

ARG BASE_IMAGE_PATH
FROM $BASE_IMAGE_PATH as builder

# Environment variables required for this build
ARG JDK_PATCH
ENV JDK_PATCH=$JDK_PATCH \
     TMP_DIR=/tmp \
     TMP_JAVA_HOME=/tmp/jdk \
     JAVA_HOME=/u01/jdk

COPY --chown=oracle:oracle $JDK_PATCH $TMP_DIR
RUN mkdir -p "$TMP_JAVA_HOME" && \
    tar --extract --file $TMP_DIR/$JDK_PATCH --directory "$TMP_JAVA_HOME" --strip-components 1

FROM $BASE_IMAGE_PATH

# Copy the uncompressed Java from the builder image

ENV TMP_DIR=/tmp \
    JAVA_HOME=/u01/jdk \
    TMP_JAVA_HOME=/tmp/jdk

RUN rm -Rf $JAVA_HOME && \
    mkdir $JAVA_HOME
COPY --chown=oracle:oracle --from=builder $TMP_JAVA_HOME $JAVA_HOME
