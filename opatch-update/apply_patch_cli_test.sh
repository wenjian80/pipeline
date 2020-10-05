#!/usr/bin/env bash
# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
# This is a wrapper script for pipeline_common.sh.
# Executes all pipeline stages from command line. It uses -c option for running pipeline_common.sh in CLI mode and sets the
# BUILD_TS environment variable (so -b <timestamp> option is not required to be passed).
#
# This script can be run from admin host as well. Admin host does not include JDK so user will need to install JDK and
# set the JAVA_HOME env var.
# Download JDK 8 and unpack it on admin host. This is not needed on Jenkins pod where JAVA_HOME is set already.
#
# export JAVA_HOME=/u01/shared/tools/jdk1.8.0_241
#
#
# To apply WLS patch:
# This requires passing patches in "<patch1> <patch2>" format
#
# /u01/shared/scripts/pipeline/opatch-update/apply_patch_cli_test.sh -p <ocir_auth_token> -w <patch1> <patch2>
#

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

export BUILD_TS=$(date +"%y-%m-%d_%H-%M-%S")

${scripts_dir}/../common/pipeline_common.sh -c -b ${BUILD_TS} "$@"
