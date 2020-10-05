#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/pipeline_common.sh

START_TM=$(date +%s)

test_domain_img ${existing_domain_image} ${build_timestamp} ${metadata_file} ${current_dir} ${new_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN}
END_TM=$(date +%s)
echo "Test Domain took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'