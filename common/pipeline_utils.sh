#!/usr/bin/env bash
# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.


# This script defines functions that are called across different pipeline stages.

script="${BASH_SOURCE[0]}"
scriptDir="$( cd "$( dirname "${script}" )" && pwd )"

# Function: Get metadata attribute.
# metadata_file: path to metadata file
# attribute: metadata attribute
get_metadata_attribute() {
    local metadata_file=$1
    local attribute=$2

    result=$(cat $metadata_file | python -c "import sys, json; print json.load(sys.stdin)['$attribute']")

    echo ${result}
}

# Function: Get OCIR Username
# ocir_url: OCIR url e.g. phx.ocir.io
# domain_ns: domain namespace
# ocirsecret_name: Name of imagePullSecrets[0] defined in domain.yaml
get_ocir_user() {
    local ocir_url=$1
    local domain_ns=$2
    local ocirsecret_name=$3

    local auths_json=$(kubectl get secret ${ocirsecret_name} -n ${domain_ns} -o jsonpath="{.data.\.dockerconfigjson}" | base64 -d)

    result=$(echo ${auths_json} | python3 ${scriptDir}/domain_builder_utils.py 'get-ocir-user' ${ocir_url})

    echo ${result}
}

# Function: Get OCIR Auth Token
# ocir_url: OCIR url e.g. phx.ocir.io
# domain_ns: domain namespace
# ocirsecret_name: Name of imagePullSecrets[0] defined in domain.yaml
get_ocir_auth_token() {
    local ocir_url=$1
    local domain_ns=$2
    local ocirsecret_name=$3

    local auths_json=$(kubectl get secret ${ocirsecret_name} -n ${domain_ns} -o jsonpath="{.data.\.dockerconfigjson}" | base64 -d)

    result=$(echo ${auths_json} | python3 ${scriptDir}/domain_builder_utils.py 'get-ocir-auth-token' ${ocir_url})

    echo ${result}
}

# Function: Generate updated domain image tag.
# metadata_file: metadata file
# timestamp: build timestamp to be used for image tagging
generate_domain_img_tag() {
    local metadata_file=$1
    local timestamp=$2

    # Generate a tag for new domain image
    #phx.ocir.io/mytenancy/myserv/mydomain/wls-domain-base/12214:12.2.1.4.191220-200203
    local ocir_domain_image_repo=$(get_metadata_attribute ${metadata_file} 'ocir_domain_image_repo')
    # repo_path=phx.ocir.io/mytenancy/myserv/mydomain/wls-domain-base/12214
    local repo_path=$(echo ${ocir_domain_image_repo} | cut -d ":" -f 1)
    # repo_path=phx.ocir.io/mytenancy/myserv/mydomain/wls-domain-base
    repo_path=$(dirname ${repo_path})
    # wls_base_version = 12.2.1.4.191220-200203
    local wls_base_version=$( echo ${ocir_domain_image_repo} | cut -d ":" -f 2)
    # tag = phx.ocir.io/mytenancy/myserv/mydomain/wls-domain-base:12.2.1.4.191220-200203-<timestamp>
    local tag=$repo_path":"${wls_base_version}-${timestamp}

    echo ${tag}
}

# Function: Create test domain yaml file.
# metadata_file:
# test_domain_yaml: path to the test domain.yaml file to be created
# weblogic_running_domain_img: image used by running domain
# weblogic_new_domain_img: the new image to be tested
# build_timestamp: timestamp used for the new image  tag
create_test_domain_yaml() {
    local metadata_file=$1
    local test_domain_yaml=$2
    local weblogic_running_domain_img=$3
    local weblogic_new_domain_img=$4
    local build_timestamp=$5
    local domain_uid=$(get_metadata_attribute $metadata_file 'wls_domain_uid')
    local domain_ns=$(get_metadata_attribute $metadata_file 'wls_domain_namespace')

    local running_domain_yaml=/tmp/running-domain-${build_timestamp}.yaml

    # Get running domain yaml
    kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > ${running_domain_yaml}

    #docker container run --rm ${weblogic_running_domain_img} /bin/bash -c 'cat /domain_info/base/domain.yaml' > ${running_domain_yaml}

    # Copy running domain yaml to create a test domain yaml file
    cp ${running_domain_yaml} ${test_domain_yaml}

    # Update test domain yaml for test domain
    python3 ${scriptDir}/domain_builder_utils.py 'create-test-domain-yaml' ${running_domain_yaml} ${test_domain_yaml} ${metadata_file} ${weblogic_new_domain_img}
}

# Function: Check pod status is ready
check_pods_ready() {
    result=$(python3 ${scriptDir}/domain_builder_utils.py 'check-pods-ready')
    echo ${result}
}

# Function: Wait for pods to be ready
# domain_yaml: domain yaml
# max_wait_time: timeout duration for pods in the domain to come to ready state
# domain_ns: domain namespace
# num_pods_to_run: how many pods are there in the domain
wait_for_pods() {
    set +x
    local domain_yaml=$1
    local max_wait_time=$2
    local domain_ns=$3
    local num_pods_to_run=$4

    local count=0
    local interval=30
    let max_retry=${max_wait_time}/${interval}

    # Ensure the check_pods_ready count remains consistent over 4*30secs = 2mins
    # This is needed for the case when we are doing rolling restart of the domain (default case)
    #
    local consistent_result_count=0
    local max_consistency_count=4

    echo "Waiting for domain server pods [$num_pods_to_run] to be ready (max_retries: $max_retry at interval: $interval seconds) ..."

    local START=$(date +%s)

    count_pods_ready=$(kubectl get pods -n ${domain_ns} -o json | check_pods_ready)
    while [[ ( ${count_pods_ready} -ne ${num_pods_to_run} || ${consistent_result_count} -ne ${max_consistency_count} ) && $count -lt ${max_retry} ]] ; do
        sleep ${interval}s
        count_pods_ready=$(kubectl get pods -n ${domain_ns} -o json | check_pods_ready)

        # Check if all pods are ready then the result remains consistent for sometime
        while [[ ${consistent_result_count} -ne ${max_consistency_count} ]] && [[ ${count_pods_ready} -eq ${num_pods_to_run} ]] ; do
            let consistent_result_count=consistent_result_count+1

            echo "Consistent result count: ${consistent_result_count}"
            echo "[$count_pods_ready of $num_pods_to_run] are ready"

            sleep ${interval}s
            count_pods_ready=$(kubectl get pods -n ${domain_ns} -o json | check_pods_ready)
        done
        if [[ ${consistent_result_count} -eq ${max_consistency_count} ]] && [[ ${count_pods_ready} -eq ${num_pods_to_run} ]] ; then
            break
        else
            let consistent_result_count=0
        fi
        let count=count+1
    done

    echo "Exiting wait_for_pods: [$count_pods_ready of $num_pods_to_run] are ready"
    echo "consistent_result_count: [$consistent_result_count] of [$max_consistency_count]"
    echo "retries: [$count] of [$max_retry]"

    local END=$(date +%s)
    echo "Domain startup took:"
    echo $((END-START)) | awk '{print int($1/60)"m:"int($1%60)"s"}'

    if [[ ${count_pods_ready} -eq ${num_pods_to_run} ]]
    then
        return 0
    else
        return 1
    fi
    set -x
}

# Function: Login to OCIR.
# metadata_file: provisioning metadata file
# ocir_user: OCIR username
# ocir_auth_token: OCIR user auth token
ocir_login() {
    set +x
    local metadata_file=$1
    local ocir_url=$(get_metadata_attribute ${metadata_file} 'ocir_url')
    local ocir_user=$2
    local ocir_auth_token=$3

    echo "Logging in to OCIR [$ocir_url] as user [$ocir_user]"
    echo ${ocir_auth_token} | docker login ${ocir_url} --username ${ocir_user} --password-stdin
    exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "Failed to login to OCIR [$ocir_url]"
        exit 1
    fi
    set -x
}