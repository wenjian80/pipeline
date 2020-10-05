#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/pipeline_common.sh
START_TM=$(date +%s)

if [[ -z ${existing_domain_image} ]]
then
    echo "There is no running domain. Please start the domain and retry."
    kubectl get domain  -n ${domain_ns}
    exit 3
fi

#Validate that domain pods are running
validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}

# Validate test domain pods are not running
#ensure_test_domain_down ${domain_ns} ${current_dir} ${build_timestamp}

END_TM=$(date +%s)
echo "Precheck took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'