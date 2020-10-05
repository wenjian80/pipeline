#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/pipeline_common.sh

START_TM=$(date +%s)

ocir_push_domain_img ${build_timestamp} ${ocir_url} ${current_dir} ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}

END_TM=$(date +%s)
echo "OCIR Push domain image took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'