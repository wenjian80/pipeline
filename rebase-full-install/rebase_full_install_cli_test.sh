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
# To get new installed image:
# This requires passing fmw bundle in jar format,patches in "<patch1> <patch2>" format, and jdk in tar.gz format
#
# /u01/shared/scripts/pipeline/rebase-full-install/rebase_full_install_cli_test.sh -p <ocir_auth_token> -f <fmw-12.2.1.4.0-infrastructure.jar> -w "<patch1> <patch2>" -j <jdk tar.gz bundle location>
#

script="${BASH_SOURCE[0]}"
scripts_dir="$( cd "$( dirname "${script}" )" && pwd )"

export BUILD_TS=$(date +"%y-%m-%d_%H-%M-%S")

${scripts_dir}/../common/pipeline_common.sh -c -b ${BUILD_TS} "$@"
