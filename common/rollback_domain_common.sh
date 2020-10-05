#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/pipeline_common.sh


if [[ ${ROLLBACK_ENABLED} = true ]]
then
    START_TM=$(date +%s)

    rollback_domain "${domain_uid}" "${build_timestamp}" "${domain_ns}" "${current_dir}" "${existing_domain_image}" "${OCIR_USER}" "${OCIR_AUTH_TOKEN}" "${new_domain_image}"

    END_TM=$(date +%s)
    echo "Rollback took:"
    echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'
fi