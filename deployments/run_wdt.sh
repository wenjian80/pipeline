#!/usr/bin/env bash
# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

# This script is executed as part of deloy-apps pipeline job docker image build process.
# It is used to invoke WDT deployApps.sh.
set -x
echo "Encrypt passphrase: $MODEL_ENCRYPT_PASSPHRASE"
echo "Archive: $WDT_ARCHIVE"
echo "Model yaml: $WDT_MODEL"
echo "Properties: $WDT_PROPERTIES"
echo "Domain: $DOMAIN"
echo "WDT home: $WDT_HOME"

if [[ -n ${MODEL_ENCRYPT_PASSPHRASE} ]]
then
    if [[ -s ${WDT_ARCHIVE} ]]
    then
        if [[ -s ${WDT_PROPERTIES} ]]
        then
            if [[ -s ${WDT_MODEL} ]]
            then
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -archive_file ${WDT_ARCHIVE} -variable_file ${WDT_PROPERTIES}
            else
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -archive_file ${WDT_ARCHIVE} -variable_file ${WDT_PROPERTIES}
            fi
        else
            if [[ -s ${WDT_MODEL} ]]
            then
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -archive_file ${WDT_ARCHIVE}
            else
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -archive_file ${WDT_ARCHIVE}
            fi
        fi
    else
        if [[ -s ${WDT_PROPERTIES} ]]
        then
            if [[ -s ${WDT_MODEL} ]]
            then
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/$DOMAIN -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -variable_file ${WDT_PROPERTIES}
            else
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/$DOMAIN -oracle_home /u01/app/oracle/middleware/ -variable_file ${WDT_PROPERTIES}
            fi
        else
            if [[ -s ${WDT_MODEL} ]]
            then
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/$DOMAIN -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL}
            else
                echo ${MODEL_ENCRYPT_PASSPHRASE} | ${WDT_HOME}/bin/updateDomain.sh -use_encryption -domain_home /u01/data/domains/$DOMAIN -oracle_home /u01/app/oracle/middleware/
            fi
        fi
    fi
else
    if [[ -s ${WDT_ARCHIVE} ]]
    then
        if [[ -s ${WDT_PROPERTIES} ]]
        then
            if [[ -s ${WDT_MODEL} ]]
            then
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -archive_file ${WDT_ARCHIVE} -variable_file ${WDT_PROPERTIES}
            else
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -archive_file ${WDT_ARCHIVE} -variable_file ${WDT_PROPERTIES}
            fi
        else
            if [[ -s ${WDT_MODEL} ]]
            then
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -archive_file ${WDT_ARCHIVE}
            else
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -archive_file ${WDT_ARCHIVE}
            fi
        fi
    else
        if [[ -s ${WDT_PROPERTIES} ]]
        then
            if [[ -s ${WDT_MODEL} ]]
            then
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL} -variable_file ${WDT_PROPERTIES}
            else
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -variable_file ${WDT_PROPERTIES}
            fi
        else
            if [[ -s ${WDT_MODEL} ]]
            then
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/ -model_file ${WDT_MODEL}
            else
                ${WDT_HOME}/bin/updateDomain.sh -domain_home /u01/data/domains/${DOMAIN} -oracle_home /u01/app/oracle/middleware/
            fi
        fi
    fi
fi
exit_code=$?
if [[ $exit_code -ne 0 ]]
then
  echo "FAILED to update-domain with exit_code: [$exit_code]"
  exit $exit_code
fi
set +x