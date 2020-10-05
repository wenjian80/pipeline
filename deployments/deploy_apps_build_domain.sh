#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/../common/pipeline_common.sh

START_TM=$(date +%s)

build_domain_img ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${domain_uid} ${current_dir} ${build_timestamp} ${existing_domain_image} ${SAMPLE_APP_DEPLOY} ${SAMPLE_APP_UNDEPLOY} ${new_domain_image} ${MODEL_ENCRYPT_PASSPHRASE} ${MODEL_PROPERTIES_FILE}

END_TM=$(date +%s)
echo "Domain image creation took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'