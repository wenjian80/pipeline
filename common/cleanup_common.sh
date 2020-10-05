#!/usr/bin/env bash

# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scripts_dir}/pipeline_common.sh

START_TM=$(date +%s)
# Always exit with 0 status as we only call it at the end of the pipeline.
exit_code=0

exit_with_cleanup ${exit_code} ${current_dir} ${build_timestamp}

END_TM=$(date +%s)
echo "Deploy Domain took:"
echo $((END_TM-START_TM)) | awk '{print int($1/60)"m:"int($1%60)"s"}'