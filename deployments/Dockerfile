# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
#
# ORACLE DOCKERFILES PROJECT
# --------------------------
# This Dockerfile extends the Oracle WebLogic domain in home image, and installs the specified applications and libraries.
# Note: At this moment, deploying exploted archives is not supported.
#
# REQUIRED FILES TO BUILD THIS IMAGE
# ----------------------------------
# (1) An archive with the binaries of the deployments (shared libraries and applications) named archive.zip
# (2) A model file named model.yaml
#
# REQUIRED BUILD ARGS TO BUILD THIS IMAGE
# ----------------------------------
# (1) BASE_IMAGE_PATH - The fully qualified name of the Docker image with the domain to extend
# (2) DOMAIN - WebLogic domain UID.
#
# HOW TO BUILD THIS IMAGE
# -----------------------
# Put all required files in the same directory as this Dockerfile
# Example:
#      $ docker build --build-arg BASE_IMAGE_PATH=<value> \
#                     --build-arg DOMAIN=<domain UID> \
#                     -t <tag> \
#                     -f Dockerfile .
#

ARG BASE_IMAGE_PATH
FROM $BASE_IMAGE_PATH

ARG DOMAIN="${DOMAIN}"
ARG MODEL_ENCRYPT_PASSPHRASE="${MODEL_ENCRYPT_PASSPHRASE}"

ENV DOMAIN="${DOMAIN}" \
    DOMAIN_HOME="/u01/data/domains/${DOMAIN}" \
    WLSDEPLOY_PROPERTIES="-Doracle.jdbc.fanEnabled=false" \
    WDT_MODEL="/u01/oracle/model.yaml" \
    WDT_ARCHIVE="/u01/oracle/archive.zip" \
    WDT_HOME="/u01/oracle/weblogic-deploy" \
    WDT_PROPERTIES="/u01/oracle/variables.properties" \
    MODEL_ENCRYPT_PASSPHRASE="${MODEL_ENCRYPT_PASSPHRASE}"


RUN mkdir -p ${WDT_HOME}
COPY --chown=oracle:oracle ./weblogic-deploy  /u01/oracle/weblogic-deploy/
COPY --chown=oracle:oracle ./archive.zip ./model.yaml ./variables.properties ./deployments/run_wdt.sh /u01/oracle/

RUN ls -al /u01/oracle/weblogic-deploy && \
    /u01/oracle/run_wdt.sh && \
    rm -f $WDT_MODEL && \
    rm -f $WDT_ARCHIVE && \
    rm -f $WDT_PROPERTIES && \
    rm -rf $WDT_HOME


