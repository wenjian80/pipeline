#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/../common/pipeline_common.sh

START_TM=$(date +%s)

apply_jdk "${JDK_INSTALLER}" ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${current_dir} ${build_timestamp} ${existing_domain_image} ${new_domain_image}

END_TM=$(date +%s)
echo "Apply JDK patch took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'
