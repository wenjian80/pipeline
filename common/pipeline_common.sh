#!/bin/bash
# Copyright (c) 2020, Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

# This script defines functions that define a pipeline stage.

script="${BASH_SOURCE[0]}"
scriptDir="$( cd "$( dirname "${script}" )" && pwd )"

source ${scriptDir}/pipeline_utils.sh

# Function: Perform cleanup on exit
exit_with_cleanup() {
    set -x
    local exit_code=$1
    local current_dir=$2
    local build_timestamp=$3

    # Get out of the build context directory so we can delete it
    cd ${current_dir}
    # Remove the temp domain image build directory
    rm -rf /tmp/deploy-apps
    # Temp domain yaml files created
    rm -f /tmp/test-domain-${build_timestamp}.yaml
    rm -f /tmp/running-domain-${build_timestamp}.yaml
    # Remove patching files created
    rm -f /tmp/apply_opatches.log
    rm -f /tmp/jdk_version_new.log
    rm -f /tmp/jdk_version.log
    rm -f /tmp/finalbuild.txt
    rm -f /tmp/oraInst.loc
    # Scan image cleanup
    docker stop ${build_timestamp}-clair
    docker stop ${build_timestamp}-db
    rm -f /tmp/clair-${build_timestamp}.log
    exit ${exit_code}
}

# Function: Scan image for vulnerabilities.
scan_image() {
    set -x
    local INTERNAL_ID=$1
    local CURRENT_DIR=$2
    local IMAGE=$3
    local SCAN_IMAGE_ENABLED=$4
    local OUTPUT="scanning-report.json"

    if [[ $SCAN_IMAGE_ENABLED = true ]]
    then
        echo "Starting clair scanner to scan domain image [$IMAGE]"

        rm -f ${INTERNAL_ID}-${OUTPUT}
        rm -f ${INTERNAL_ID}-clair.log

        docker container run \
          -d \
          --rm \
          --name ${INTERNAL_ID}-db \
          arminc/clair-db:latest

        docker container run \
          -p 6060:6060 \
          --rm \
          --link ${INTERNAL_ID}-db:postgres \
          -d \
          --name ${INTERNAL_ID}-clair \
          arminc/clair-local-scan:v2.0.8_0ed98e9ead65a51ba53f7cc53fa5e80c92169207

        curl -L -s -O https://github.com/arminc/clair-scanner/releases/download/v12/clair-scanner_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64
        mv clair-scanner_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64 clair-scanner
        chmod +x clair-scanner
        sleep 5

        inspectretries=0
        CLAIR_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${INTERNAL_ID}-clair)
        re="^([0-9]{1,3}.?){4}$"

        echo "Clair Docker Container IP $CLAIR_CONTAINER_IP"
        while [[ ! $CLAIR_CONTAINER_IP =~ $re ]]; do
          sleep 1;
          echo "Waiting.";
          if [ $inspectretries -eq 10 ]; then
            echo " Timeout, aborting.";
            docker inspect ${INTERNAL_ID}-clair > dinspect.out;
            cat dinspect.out;
            cleanup;
            exit 1;
          fi;
          CLAIR_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${INTERNAL_ID}-clair);
          inspectretries=$(($inspectretries+1));
        done

        echo "Waiting for clair daemon to start ..."
        echo "Clair Docker Container IP $CLAIR_CONTAINER_IP"
        timeout 2m bash -c "until curl http://${CLAIR_CONTAINER_IP}:6060/v1/namespaces; do sleep 2; done"

        echo "Starting clair image scanning, Using paths to upload clair report ..."
        ./clair-scanner \
          -c http://${CLAIR_CONTAINER_IP}:6060 \
          --ip "$(awk 'END{print $1}' /etc/hosts)" \
          -r ${INTERNAL_ID}-${OUTPUT} \
          -l ${INTERNAL_ID}-clair.log \
          $IMAGE || true
        cat ${INTERNAL_ID}-${OUTPUT}

        export UNAPPROVED_COUNT=$(cat ${INTERNAL_ID}-clair.log | grep " contains .* unapproved vulnerabilities" | sed -r 's|(.*)(contains )(.*)( unapproved vulnerabilities)|\3|g')
        echo $UNAPPROVED_COUNT

        #Cleanup
        docker container stop ${INTERNAL_ID}-clair
        docker container stop ${INTERNAL_ID}-db
        docker container ls -a
        rm -f ${INTERNAL_ID}-clair.log

        echo "Completed image scanning for $IMAGE!"
        if [[ -n $UNAPPROVED_COUNT ]] && [[ $UNAPPROVED_COUNT != "NO" ]]; then
          echo "$IMAGE image has $UNAPPROVED_COUNT unapproved vulnerabilities";
          exit_with_cleanup 4 ${CURRENT_DIR} ${INTERNAL_ID}
        fi
    else
      echo "Scan image is disabled."
    fi
    set +x
}

# Function: Push domain image to OCIR.
ocir_push_domain_img() {
    set -x
    local build_timestamp=$1
    local ocir_url=$2
    local current_dir=$3
    local metadata_file=$4
    local ocir_user=$5
    local ocir_auth_token=$6
    local tag=$7
    # Don't log the auth token
    set +x

    ocir_login ${metadata_file} ${ocir_user} ${ocir_auth_token}

    set -x

    echo "Pushing domain image [$tag] to OCIR [$ocir_url]"

    docker image push $tag
    if [[ $? -eq 0 ]]
    then
       echo "Successfully pushed domain image [$tag] to OCIR [$ocir_url]"
       return 0
    else
       echo "Failed to push domain image [$tag] to OCIR [$ocir_url]"
       exit_with_cleanup 4 ${current_dir} ${build_timestamp}
    fi
    set +x
}

# Function: Rebase source image to base FMW image to reduce the image size.
rebase_domain() {
    set -x
    local build_timestamp=$1
    local base_domain_img=$2
    local current_dir=$3
    local tag=$4

    echo "Rebase source image [$tag] to [$base_domain_img]"
    local is_java_home_set=$(echo ${JAVA_HOME})
    if [[ -z ${is_java_home_set} ]]
    then
        echo "JAVA_HOME environment variable is not set"
        exit_with_cleanup 4 ${current_dir} ${build_timestamp}
    fi
    /u01/shared/tools/imagetool/bin/imagetool.sh rebase --tag $tag --sourceImage=$tag --targetImage=$base_domain_img

    if [[ $? -eq 0 ]]
    then
       echo "Successfully rebased source image [$tag] to [$base_domain_img]"
    else
       echo "Failed to rebase source image [$tag] to [$base_domain_img]"
       exit_with_cleanup 4 ${current_dir} ${build_timestamp}
    fi
    set +x
}

# Function: Build domain image with deployed apps/libraries or resources
build_domain_img() {
    set -x
    local metadata_file=$1
    local OCIR_USER=$2
    local OCIR_AUTH_TOKEN=$3
    local domain_uid=$4
    local current_dir=${5}
    local build_timestamp=${6}
    local running_domain_image=${7}
    local SAMPLE_APP_DEPLOY=${8}
    local SAMPLE_APP_UNDEPLOY=${9}
    local tag=${10}
    local MODEL_ENCRYPT_PASSPHRASE=${11}
    local MODEL_PROPERTIES_FILE=${12}

    #create temp directory to run docker build
    mkdir -p /tmp/deploy-apps

    # Copy required artifacts to the docker build location
    # Copy WDT
    cp -r /u01/shared/tools/weblogic-deploy /tmp/deploy-apps/
    # Copy pipeline deployments scripts
    cp -r /u01/shared/scripts/pipeline/deployments /tmp/deploy-apps/

    cd /tmp/deploy-apps

    if [[ -n ${WDT_ARCHIVE} ]]
    then
        # Copy WDT archive.zip containing applications and libraries
        cp ${WDT_ARCHIVE} ./archive.zip
    else
        # Create an empty archive.zip so in Dockerfile we ignore passing WDT archive to deployApps
        touch ./archive.zip
    fi

    # Copy WDT model yaml describing the applications, libraries and resources to add to the domain image.
    if [[ -n ${WDT_MODEL} ]]
    then
        cp ${WDT_MODEL} ./model.yaml
    else
        touch ./model.yaml
    fi

    if [[ -n ${MODEL_PROPERTIES_FILE} ]]
    then
        cp ${MODEL_PROPERTIES_FILE} ./variables.properties
    else
        touch ./variables.properties
    fi

    cluster_name=$(get_metadata_attribute $metadata_file 'wls_cluster_name')

    # For sample-app model yaml update cluster name.
    if [[ ${SAMPLE_APP_DEPLOY} = true ]] || [[ ${SAMPLE_APP_UNDEPLOY} = true ]]
    then
        sed -i -e "s:%CLUSTER_NAME%:${cluster_name}:g" ./model.yaml
    fi

    # Login to OCIR
    ocir_login ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

    # Build the new domain image
    docker build -f deployments/Dockerfile --network=host --force-rm=true --no-cache=true --build-arg BASE_IMAGE_PATH=${running_domain_image} --build-arg DOMAIN=${domain_uid} --build-arg MODEL_ENCRYPT_PASSPHRASE=${MODEL_ENCRYPT_PASSPHRASE} -t ${tag} .

    if [[ $? -ne 0 ]]
    then
        echo "Failed to build domain image [$tag]"
        exit_with_cleanup 5 ${current_dir} ${build_timestamp}
    else
        echo "Successfully built domain image"
    fi
    set +x
}

# Function: Apply opatches
apply_opatch() {
    set -x
    local OPATCH_PATCH_LIST=${1}
    local metadata_file=${2}
    local OCIR_USER=${3}
    local OCIR_AUTH_TOKEN=${4}
    local current_dir=${5}
    local build_timestamp=${6}
    local running_domain_image=${7}
    local tag=${8}

    local WLS_VERSION=$(get_metadata_attribute $metadata_file 'wls_version')

    export TMP_DIR=/tmp
    export WLSIMG_CACHEDIR=${TMP_DIR}/cache
    export WLSIMG_BLDDIR=${TMP_DIR}/wlsbuild

    # Login to OCIR
    ocir_login ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

    local FINALBUILD_FILE=${TMP_DIR}/finalbuild.txt
    local domain_name=$(get_metadata_attribute $metadata_file 'wls_domain_uid')

    echo "[final-build-commands]" > ${FINALBUILD_FILE}
    echo "ENV DOMAIN_HOME=/u01/data/domains/${domain_name}" >> ${FINALBUILD_FILE}

    local is_java_home_set=$(echo ${JAVA_HOME})
    if [[ -z ${is_java_home_set} ]]
    then
        echo "JAVA_HOME environment variable is not set"
        exit_with_cleanup 7 ${current_dir} ${build_timestamp}
    fi

    rm -Rf $WLSIMG_CACHEDIR

    if [[ ! -d "$WLSIMG_BLDDIR" ]]
    then
       echo "$WLSIMG_BLDDIR doesn't exist so creating one"
       mkdir -p $WLSIMG_BLDDIR
    fi

    local counter=0
    for OPATCH_PATCH in ${OPATCH_PATCH_LIST}
    do
        echo "`date` - Applying OPATCH patch ${OPATCH_PATCH}"
        BASE_PATCH=$(basename $OPATCH_PATCH)
        PATCH_NEW=${BASE_PATCH:1:8}
	patch_array[counter++]=${PATCH_NEW}_${WLS_VERSION};
        /u01/shared/tools/imagetool/bin/imagetool.sh cache addPatch --patchId ${PATCH_NEW}_${WLS_VERSION} --path ${OPATCH_PATCH}
        if [[ $? -ne 0 ]]
        then
           echo "imagetool adding patch $PATCH_NEW to cache failed [$tag]"
           exit_with_cleanup 7 ${current_dir} ${build_timestamp}
        fi
    done

    #List the patches that are in cache
    /u01/shared/tools/imagetool/bin/imagetool.sh cache listItems

    PATCH_STR=`echo ${patch_array[@]} | sed 's/ /,/g'`

    echo "Applying patches ${PATCH_STR}"

    #Create docker image with all the patches and installers
    /u01/shared/tools/imagetool/bin/imagetool.sh update --tag ${tag} --fromImage=${running_domain_image} --patches=${PATCH_STR} --additionalBuildCommands=${FINALBUILD_FILE} --skipOpatchUpdate
    if [[ $? -ne 0 ]]
    then
      echo "imagetool create wls docker image with pacthes failed [$tag]"
      exit_with_cleanup 8 ${current_dir} ${build_timestamp}
    fi

    #Choose opatch lsinventory instead of lspatches due to bug no. and patch no. doesn't match in some of the patches.
    echo "Listing opatch inventory checking the patches"
    docker run $tag /bin/bash /u01/app/oracle/middleware/OPatch/opatch lsinventory | tee /tmp/apply_opatches.log

    for OPATCH_PATCH in ${patch_array[@]}
    do
	PATCH_NEW=${OPATCH_PATCH:0:8}
        if grep -q ${PATCH_NEW} "/tmp/apply_opatches.log";
        then
           echo "patch $PATCH_NEW was applied successfully"
        else
           echo "patch $PATCH_NEW was not added successfully [$tag]"
           exit_with_cleanup 9 ${current_dir} ${build_timestamp}
        fi
    done

    set +x
}

# Function: Apply jdk patch
apply_jdk()
{
    set -x
    local JDK_INSTALLER=${1}
    local metadata_file=${2}
    local OCIR_USER=${3}
    local OCIR_AUTH_TOKEN=${4}
    local current_dir=${5}
    local build_timestamp=${6}
    local running_domain_image=${7}
    local tag=${8}

    # Login to OCIR
    ocir_login ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

    BASE_JDK_INSTALLER=$(basename $JDK_INSTALLER)

    # Build the new domain image with new jdk installer
    docker build -f /u01/shared/scripts/pipeline/jdk-patch/Dockerfile --network=host --force-rm=true --no-cache=true --build-arg BASE_IMAGE_PATH=${running_domain_image} --build-arg JDK_PATCH=${BASE_JDK_INSTALLER} -t ${tag} .
    if [[ $? -ne 0 ]]
    then
        echo "Failed to build domain image with new jdk installer[$tag]"
        exit_with_cleanup 10 ${current_dir} ${build_timestamp}
    else
        echo "Successfully built domain image with new jdk installer"
    fi

    echo "Checking the jdk version"
    docker run $tag /u01/jdk/bin/java -version | tee /tmp/jdk_version_new.log

    tar xvzf ${JDK_INSTALLER} -C /tmp/
    
    local EXTRACT_JDK=`tar -tz -f ${JDK_INSTALLER} | head -n1`

    /tmp/$EXTRACT_JDK/bin/java -version  | tee /tmp/jdk_version.log
    
    if cmp -s "/tmp/jdk_version_new.log"  "/tmp/jdk_version.log";
    then
       echo "jdk ${EXTRACT_JDK} was applied successfully"
    else
       echo "jdk ${EXTRACT_JDK} was not applied successfully [$tag]"
       rm -Rf /tmp/$EXTRACT_JDK
       exit_with_cleanup 11 ${current_dir} ${build_timestamp}
    fi

    rm -Rf /tmp/$EXTRACT_JDK
    set +x
}

# Function: rebase for full install
rebase_full_install() {
    set -x
    local FMW_INSTALLER=${1}
    local JDK_VERSION=${2}
    local JDK_INSTALLER=${3}
    local OPATCH_PATCH_LIST=${4}
    local SKIP_OPATCH_UPDATE=${5}
    local metadata_file=${6}
    local OCIR_USER=${7}
    local OCIR_AUTH_TOKEN=${8}
    local current_dir=${9}
    local build_timestamp=${10}
    local running_domain_image=${11}
    local tag=${12}
    local INVENTORY_BASE_DIR=/u01/app/oraInventory

    local TMP_DIR=/tmp
    local IMAGE_TOOL_PARAMS=""

    # Login to OCIR
    ocir_login ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

    local WLS_VERSION=$(get_metadata_attribute $metadata_file 'wls_version')
    local INVENTORY_FILE=${TMP_DIR}/oraInst.loc
    local PRIMARYGROUP=dba

    echo "inventory_loc=${INVENTORY_BASE_DIR}" > ${INVENTORY_FILE}
    echo "inst_group=$PRIMARYGROUP" >> ${INVENTORY_FILE}

    local FINALBUILD_FILE=${TMP_DIR}/finalbuild.txt
    local domain_name=$(get_metadata_attribute $metadata_file 'wls_domain_uid')

    echo "[final-build-commands]" > ${FINALBUILD_FILE}
    echo "ENV DOMAIN_HOME=/u01/data/domains/${domain_name}" >> ${FINALBUILD_FILE}

    local FROM_IMAGE=$(get_metadata_attribute $metadata_file 'ocir_slimlinux_repo')

    local BASE_JDK_INSTALLER=$(basename $JDK_INSTALLER)

    export WLSIMG_CACHEDIR=${TMP_DIR}/cache
    export WLSIMG_BLDDIR=${TMP_DIR}/wlsbuild

    if [[ ${SKIP_OPATCH_UPDATE}  == false ]]
    then
       if [[ ${OPATCH_PATCH_LIST} != *"p28186730"* ]]
       then
            echo "imagetool requires latest opatch patch present to be able to apply the patches.Please download latest opatch(p28186730*zip) and pass it along with other patches. [ $tag]"
            exit_with_cleanup 12 ${current_dir} ${build_timestamp}
       fi
    fi

    local is_java_home_set=$(echo ${JAVA_HOME})
    if [[ -z ${is_java_home_set} ]]
    then
        echo "JAVA_HOME environment variable is not set"
        exit_with_cleanup 13 ${current_dir} ${build_timestamp}
    fi

    rm -Rf $WLSIMG_CACHEDIR

    if [[ ! -d "$WLSIMG_BLDDIR" ]]
    then
       echo "$WLSIMG_BLDDIR doesn't exist so creating one"
       mkdir -p $WLSIMG_BLDDIR
    fi

    #Add jdk installer to cache
    /u01/shared/tools/imagetool/bin/imagetool.sh cache addInstaller --type=jdk --version=$JDK_VERSION --path=${JDK_INSTALLER}
    if [[ $? -ne 0 ]]
    then
       echo "imagetool adding jdk installer to cache failed ..... (exiting)"
       exit_with_cleanup 13 ${current_dir} ${build_timestamp}
    fi

    #Add WLS installer to cache
    /u01/shared/tools/imagetool/bin/imagetool.sh cache addInstaller --type=wls --version=$WLS_VERSION --path=${FMW_INSTALLER}
    if [[ $? -ne 0 ]]
    then
       echo "imagetool adding wls installer to cache failed ..... (exiting)"
       exit_with_cleanup 14 ${current_dir} ${build_timestamp}
    fi

    #List items that are in cache
    /u01/shared/tools/imagetool/bin/imagetool.sh cache listItems

    local counter=0

    # Add patches to cache
    for OPATCH_PATCH in ${OPATCH_PATCH_LIST}
    do
        echo "`date` - Applying OPATCH patch ${OPATCH_PATCH}"
        BASE_PATCH=$(basename $OPATCH_PATCH)
        PATCH_NEW=${BASE_PATCH:1:8}

	if [[ $OPATCH_PATCH != *"p28186730"* ]]
        then
           patch_array[counter++]=${PATCH_NEW}_${WLS_VERSION};
        fi
        /u01/shared/tools/imagetool/bin/imagetool.sh cache addPatch --patchId ${PATCH_NEW}_${WLS_VERSION} --path ${OPATCH_PATCH}
        if [[ $? -ne 0 ]]
        then
           echo "imagetool adding patch $PATCH_NEW to cache failed [$tag]"
           exit_with_cleanup 14 ${current_dir} ${build_timestamp}
        fi
    done

    #List the patches that are in cache
    /u01/shared/tools/imagetool/bin/imagetool.sh cache listItems

    PATCH_STR=`echo ${patch_array[@]} | sed 's/ /,/g'`

    echo "Applying patches ${PATCH_STR}"

    # KNOWNISSUE: currently imagetool rebase doesn't work on dev tenancy due to accessing yum repo issues
    # Test on production tenancy with regional OCI yum repo.
    #Create docker image with all the patches and installers
    if [[ ${SKIP_OPATCH_UPDATE} == true ]]
    then
      IMAGE_TOOL_PARAMS="--fromImage ${FROM_IMAGE} --buildNetwork=host --tag ${tag} --version=${WLS_VERSION} --jdkVersion=${JDK_VERSION} --installerResponseFile=/u01/shared/scripts/pipeline/common/install_wls_response.txt --sourceImage=${running_domain_image} --inventoryPointerFile=${INVENTORY_FILE} --patches=${PATCH_STR} --additionalBuildCommands=${FINALBUILD_FILE} --skipOpatchUpdate"
    else 
      IMAGE_TOOL_PARAMS="--fromImage ${FROM_IMAGE} --buildNetwork=host --tag ${tag} --version=${WLS_VERSION} --jdkVersion=${JDK_VERSION} --installerResponseFile=/u01/shared/scripts/pipeline/common/install_wls_response.txt --sourceImage=${running_domain_image} --inventoryPointerFile=${INVENTORY_FILE} --patches=${PATCH_STR} --additionalBuildCommands=${FINALBUILD_FILE}"
    fi

    /u01/shared/tools/imagetool/bin/imagetool.sh rebase ${IMAGE_TOOL_PARAMS}
    if [[ $? -ne 0 ]]
    then
      echo "imagetool create wls docker image with rebase failed [$tag]"
      exit_with_cleanup 15 ${current_dir} ${build_timestamp}
    fi

    #Choose opatch lsinventory instead of lspatches due to bug no. and patch no. doesn't match in some of the patches.
    echo "Listing opatch inventory and checking the patches"
    docker run $tag /bin/bash /u01/app/oracle/middleware/OPatch/opatch lsinventory | tee /tmp/apply_opatches.log

    for OPATCH_PATCH in ${patch_array[@]}
    do
        PATCH_NEW=${OPATCH_PATCH:0:8}
        if grep -q ${PATCH_NEW} "/tmp/apply_opatches.log";
        then
           echo "patch $PATCH_NEW was applied successfully"
        else
           echo "patch $PATCH_NEW was not added successfully [$tag]"
           exit_with_cleanup 9 ${current_dir} ${build_timestamp}
        fi
    done

    set +x
}

# Function: Test Domain with the newly built image
test_domain_img() {
    set -x
    local running_domain_image=$1
    local build_timestamp=$2
    local metadata_file=$3
    local current_dir=$4
    local tag=$5
    local OCIR_USER=$6
    local OCIR_AUTH_TOKEN=$7

    # Login to OCIR
    ocir_login ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

    local domain_ns=$(get_metadata_attribute $metadata_file 'wls_domain_namespace')
    domain_ns=${domain_ns}-test

    # Test the domain image
    local test_domain_yaml=/tmp/test-domain-${build_timestamp}.yaml

    create_test_domain_yaml ${metadata_file} ${test_domain_yaml} ${running_domain_image} ${tag} ${build_timestamp}
    if [[ $? -eq 0 ]]
    then
        echo "Test domain yaml created successfully"
    else
        echo "Failed to create test domain"
        exit_with_cleanup 6 ${current_dir} ${build_timestamp}
    fi

    # Wait for test domain yaml file to be written to before calling kubectl on it.
    while [[ ! -f ${test_domain_yaml} ]]
    do
        sleep 1s
    done

    kubectl apply -f ${test_domain_yaml}
    set +x
}

# Function: Validate Test Domain is running and server pods are in ready state
validate_running_test_domain() {
    set -x
    local domain_ns=$1
    local current_dir=$2
    local build_timestamp=$3
    local test_domain_yaml=/tmp/test-domain-${build_timestamp}.yaml

    # Max wait time 60 mins for pods to be ready
    let max_wait_time=60*60

    # Get replica count in test domain yaml
    local replica_count=$(python3 /u01/shared/scripts/pipeline/common/domain_builder_utils.py 'get-replica-count' ${test_domain_yaml})
    let num_pods_to_run=replica_count+1

    wait_for_pods ${test_domain_yaml} ${max_wait_time} ${domain_ns}-test  ${num_pods_to_run}

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Test domain server pods are not ready."
        exit_with_cleanup 7 ${current_dir} ${build_timestamp}
    else
        echo "Test domain server pods started successfully"
    fi

    # Clean up test domain
    kubectl delete -f ${test_domain_yaml}
    set +x
}

# Function: Deploy updated domain image to the running domain.
deploy_domain_img() {
    set -x
    local domain_uid=$1
    local build_timestamp=$2
    local domain_ns=$3
    local tag=$4
    local current_dir=$5

    # Apply the domain image to running domain if publish is selected
    echo "Publishing image [$tag] to domain..."
    local running_domain_yaml=/tmp/running-domain-${build_timestamp}.yaml

    # Get running domain yaml
    kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > ${running_domain_yaml}
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Domain ${domain_uid} in namespace ${domain_ns} does not exist."
        exit_with_cleanup 3 ${current_dir} ${build_timestamp}
    fi

    # Back it up
    mkdir -p /u01/shared/weblogic-domains/${domain_uid}/backups/${build_timestamp}
    cp ${running_domain_yaml} /u01/shared/weblogic-domains/${domain_uid}/backups/${build_timestamp}/prev-domain.yaml

    # Update domain.yaml with the new image.
    sed -i -e "s|\(image: \).*|\1 \"${tag}\"|g" ${running_domain_yaml}

    # Apply the changes
    kubectl apply -f ${running_domain_yaml}

    # Replace the domain.yaml file in shared filesystem
    cp ${running_domain_yaml} /u01/shared/weblogic-domains/${domain_uid}/domain.yaml

    # Back up the new domain.yaml in backup directory
    cp ${running_domain_yaml} /u01/shared/weblogic-domains/${domain_uid}/backups/${build_timestamp}/domain.yaml

    set +x
}

# Function: Validate that the test domain is not existing.
#ensure_test_domain_down() {
#  set -x
#  local domain_ns=$1
#  local current_dir=$2
#  local build_timestamp=$3
#
#  test_domain=$(kubectl get domain -n ${domain_ns}-test -o jsonpath="{.items[*].metadata.name}")
#
#  if [[ -n ${test_domain} ]]
#  then
#      echo "Test domain exits: [${test_domain}]. Deleting test domain..."
#      kubectl delete domain ${test_domain} -n ${domain_ns}-test
#      test_domain=$(kubectl get domain -n ${domain_ns}-test -o jsonpath="{.items[*].metadata.name}")
#      if [[ -z  ${test_domain} ]]
#      then
#        echo "Successfully deleted test domain: [${test_domain}]"
#      else
#        echo "Unable to delete test domain: [${test_domain}]. Please delete test domain and retry."
#      fi
#  fi
#  set +x
#}

# Function: Validate Domain is running and server pods are in ready state.
validate_running_domain() {
    set -x
    local domain_ns=$1
    local current_dir=$2
    local build_timestamp=$3
    local domain_uid=$4

    local running_domain_yaml=/tmp/running-domain-${build_timestamp}.yaml

    # Get running domain yaml
    kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > ${running_domain_yaml}
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: Domain ${domain_uid} in namespace ${domain_ns} does not exist."
        exit_with_cleanup 7 ${current_dir} ${build_timestamp}
    fi

    # Get replica count in test domain yaml
    local replica_count=$(python3 /u01/shared/scripts/pipeline/common/domain_builder_utils.py 'get-replica-count' ${running_domain_yaml})
    let num_pods_to_run=replica_count+1
    # Max wait time 120 mins for pods to be ready
    let max_wait_time=120*60

    wait_for_pods ${running_domain_yaml} ${max_wait_time} ${domain_ns} ${num_pods_to_run}

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Domain server pods are not ready."
        exit_with_cleanup 7 ${current_dir} ${build_timestamp}
    else
        echo "Domain server pods are in running & ready state."
    fi
    set +x
}

# Function: Rollback domain
rollback_domain() {
    set -x
    local domain_uid=$1
    local build_timestamp=$2
    local domain_ns=$3
    local current_dir=$4
    local old_domain_image=$5
    local ocir_user=$6
    local ocir_auth_token=$7
    local new_domain_image=$8

    local running_domain_yaml=/tmp/running-domain-${build_timestamp}.yaml
    local prev_domain_yaml=/u01/shared/weblogic-domains/${domain_uid}/backups/${build_timestamp}/prev-domain.yaml

    mkdir -p /u01/shared/weblogic-domains/${domain_uid}/backups/${build_timestamp}
    # Get running domain yaml
    kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > ${running_domain_yaml}
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        cp ${running_domain_yaml} ${prev_domain_yaml}
        # Update domain.yaml with the old domain image
        sed -i -e "s|\(image: \).*|\1 \"${old_domain_image}\"|g" ${prev_domain_yaml}
        echo "Created file: ${prev_domain_yaml}. Updated image to [${old_domain_image}]"
        cat ${prev_domain_yaml}
        # Apply the domain yaml with old domain image
        kubectl apply -f ${prev_domain_yaml}
        validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}
        # Replace current domain.yaml with most current domain
        kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > /u01/shared/weblogic-domains/${domain_uid}/domain.yaml
    else
        #In case there is no domain (which should not happen) we will try to apply the file that was backup when the new domain image was applied
        echo "Failed to get current domain ${domain_uid} in namespace ${domain_ns}. Trying to rollback to domain ${prev_domain_yaml}."
        if [[ ! -f ${prev_domain_yaml} ]]; then
            echo "The domain backup file ${prev_domain_yaml} does not exist. Cannot determine which domain to use to rollback. Use kubectl apply to rollback to one of the domains backed up in /u01/shared/weblogic-domains/${domain_uid}/backups"
        else
            # Apply the domain yaml backed up when the image was applied.
            kubectl apply -f ${prev_domain_yaml}
            validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}
            # Replace current domain.yaml with most current domain
            kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > /u01/shared/weblogic-domains/${domain_uid}/domain.yaml
        fi
    fi
    # Cleanup the earlier image from OCIR repo. TODO: automate this step
    echo "You can delete image [${new_domain_image}] from OCIR"
    set +x
}

# Function: Rollback to specified domain image.
rollback_domain_to_image() {
  set -x
  local rollback_to_image=$1
  local current_dir=$2

  timestamp=$(date +"%y-%m-%d_%H-%M-%S")
  local running_domain_yaml=/tmp/running-domain-${timestamp}.yaml
  local domain_uid=$(get_metadata_attribute $metadata_file 'wls_domain_uid')
  local domain_ns=$(get_metadata_attribute $metadata_file 'wls_domain_namespace')

  # Get running domain yaml
  kubectl get domain ${domain_uid} -n ${domain_ns} -o yaml > ${running_domain_yaml}
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
      echo "ERROR: Domain ${domain_uid} in namespace ${domain_ns} does not exist."
      exit_with_cleanup 2 ${current_dir} ${timestamp}
  fi

  # Update domain.yaml with the old domain image
  sed -i -e "s|\(image: \).*|\1 \"${rollback_to_image}\"|g" ${running_domain_yaml}
  echo "Created file: ${running_domain_yaml}. Updated image to [${rollback_to_image}]"
  cat ${running_domain_yaml}

  # Apply the domain yaml with old domain image
  kubectl apply -f ${running_domain_yaml}
  validate_running_domain ${domain_ns} ${current_dir} ${timestamp} ${domain_uid}

  # Remove the temp running domain yaml
  rm -f ${running_domain_yaml}
  set +x
}

# Function: Print a help message.
usage() {
  echo "Usage: $0 [ -a WDT_ARCHIVE ] [ -m WDT_MODEL ] [ -p WDT_PROPERTIES_FILE ] [ -e ENCRYPT_PASSPHRASE] [ -w OPATCH_PATCH_LIST ] [ -j JDK_INSTALLER ] [ -f FMW_INSTALLER ] [ -v JDK_VERSION ][ -b ] [ -o ] [ -r ] [ -t ] [ -T ] [ -i ] [ -h ]" 1>&2
  echo "-a  WDT archive zip file (Optional, only required when deploying apps or libraries and not using -t option)" 1>&2
  echo "-m  WDT model file (Optional, only required when deploying apps, libraries or resources and not using -t option.)" 1>&2
  echo "-p  WDT properties file (Optional)" 1>&2
  echo "-e  Encryption passphrase used to encrypt the passwords in WDT model file (Optional)" 1>&2
  echo "-w  WLS opatches (Optional, only required when applying patches)" 1>&2
  echo "-j  JDK Installer (Optional, only required when applying new jdk patch)" 1>&2
  echo "-f  FMW Installer (Optional, only required when running rebase command)" 1>&2
  echo "-v  JDK version (Optional, only required when running rebase command)" 1>&2
  echo "-b  Build Timestamp or Tag suffix. Required, if environment variable BUILD_TS is not set. Either BUILD_TS env var should be set or -b option should be used." 1>&2
  #echo "-c  CLI mode (Optional. Default=false)" 1>&2
  echo "-r  Rollback enabled. Default = true" 1>&2
  echo "-T  Undeploy test sample-app. Optional, Default = false" 1>&2
  echo "-t  Test deployment with sample-app (Optional. If specified, WDT archive and model files dont need to be specified. Default=false)" 1>&2
  echo "-s  Scan Image for security vulnerabilities. Default = false" 1>&2
  echo "-o  Update opatch version Default = false" 1>&2
  echo "-i  Rollback to specified domain image" 1>&2
  echo "-h  Print this help" 1>&2
}

# Function: Exit with error.
exit_abnormal() {
  usage
  exit 1
}

######### Body of script ##############
metadata_file=$(find /u01/shared -name provisioning_metadata.json 2>/dev/null)
if [[ $? -ne 0 ]] || [[ ! -f ${metadata_file} ]]
then
    echo "Failed to find metadata file."
    exit_abnormal
fi
ocir_url=$(get_metadata_attribute ${metadata_file} 'ocir_url')
domain_ns=$(get_metadata_attribute ${metadata_file} 'wls_domain_namespace')
domain_uid=$(get_metadata_attribute $metadata_file 'wls_domain_uid')
ocirsecret_name=$(kubectl get domain ${domain_uid} -n ${domain_ns} -o jsonpath="{..imagePullSecrets[0].name}")
echo "Using ocirsecret [${ocirsecret_name}] from domain [${domain_uid}]"
OCIR_USER=$(get_ocir_user ${ocir_url} ${domain_ns} ${ocirsecret_name})
OCIR_AUTH_TOKEN=$(get_ocir_auth_token ${ocir_url} ${domain_ns} ${ocirsecret_name})

if [[ -z ${OCIR_AUTH_TOKEN} ]]
then
    echo "Failed to read OCIR Auth Token from ocirsecrets in [${domain_ns}]." 1>&2
    exit_abnormal
fi

if [[ -z ${OCIR_USER} ]]
then
    echo "Failed to read OCIR User from ocirsecrets in [${domain_ns}]." 1>&2
    exit_abnormal
else
    echo "Using OCIR user: [${OCIR_USER}]" 1>&2
fi

WDT_ARCHIVE=""
WDT_MODEL=""
MODEL_ENCRYPT_PASSPHRASE=""
MODEL_PROPERTIES_FILE=""
SAMPLE_APP_DEPLOY=false
SAMPLE_APP_UNDEPLOY=false
CLI_MODE=false
ROLLBACK_ENABLED=true
SCAN_IMAGE_ENABLED=false
SKIP_OPATCH_UPDATE=false
# Build timestamp is set via environment variable BUILD_TS
build_timestamp="${BUILD_TS}"
rollback_to_image=""

while getopts ":a:m:e:p:w:j:f:v:b:i:rsoctTh" options; do
  case "${options}" in
    a)
      WDT_ARCHIVE=${OPTARG}
      if [[ $WDT_ARCHIVE = "" ]]; then
          echo "Error: -a requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    m)
      WDT_MODEL=${OPTARG}
      if [[ $WDT_MODEL = "" ]]; then
          echo "Error: -m requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    e)
      MODEL_ENCRYPT_PASSPHRASE=${OPTARG}
      if [[ $MODEL_ENCRYPT_PASSPHRASE = "" ]]; then
          echo "Error: -e requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    p)
      MODEL_PROPERTIES_FILE=${OPTARG}
      if [[ $MODEL_PROPERTIES_FILE = "" ]]; then
          echo "Error: -p requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    w)
      OPATCH_PATCH_LIST=${OPTARG}
      if [[ $OPATCH_PATCH_LIST = "" ]]; then
          echo "Error: -w requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    j)
      JDK_INSTALLER=${OPTARG}
      if [[ $JDK_INSTALLER = "" ]]; then
          echo "Error: -j requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    f)
      FMW_INSTALLER=${OPTARG}
      if [[ $FMW_INSTALLER = "" ]]; then
          echo "Error: -f requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    v)
      JDK_VERSION=${OPTARG}
      if [[ $JDK_VERSION = "" ]]; then
          echo "Error: -v requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    b)
      build_timestamp=${OPTARG}
      if [[ "$build_timestamp" = "" ]]; then
          echo "Error: -b requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    t)
      SAMPLE_APP_DEPLOY=true
      ;;
    T)
      SAMPLE_APP_UNDEPLOY=true
      ;;
    c)
      CLI_MODE=true
      ;;
    r)
      ROLLBACK_ENABLED=true
      ;;
    s)
      SCAN_IMAGE_ENABLED=true
      ;;
    o)
      SKIP_OPATCH_UPDATE=true
      ;;
    i)
      rollback_to_image=${OPTARG}
      if [[ "$rollback_to_image" = "" ]]; then
          echo "Error: -i requires a non-empty argument."
          exit_abnormal
      fi
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Error: -${OPTARG} requires an argument."
      exit_abnormal
      ;;
    \? )
      echo "Invalid Option: -$OPTARG" 1>&2
      exit_abnormal
      ;;
  esac
done
shift $((OPTIND -1))

current_dir=$(pwd)

if [[ $SAMPLE_APP_DEPLOY = true ]]
then
    WDT_ARCHIVE="/u01/shared/scripts/pipeline/samples/archive.zip"
    WDT_MODEL="/u01/shared/scripts/pipeline/samples/deploy_sample_app.yaml"
fi

if [[ $SAMPLE_APP_UNDEPLOY = true ]]
then
    WDT_MODEL="/u01/shared/scripts/pipeline/samples/undeploy_sample_app.yaml"
fi

# If manual rollback to a specified image is invoked
if [[ -n $rollback_to_image ]]
then
  rollback_domain_to_image $rollback_to_image $current_dir
  exit 0
fi

if [[ -z ${build_timestamp} ]]
then
    echo "Build timestamp is required. Please set BUILD_TS environment variable." 1>&2
    exit_abnormal
fi

domain_uid=$(get_metadata_attribute $metadata_file 'wls_domain_uid')
# This will get the initial domain image used during provisioning
base_domain_img=$(get_metadata_attribute $metadata_file 'ocir_domain_image_repo')
ocir_url=$(get_metadata_attribute ${metadata_file} 'ocir_url')

# Use kubectl to read the image being used by currently running domain
existing_domain_image=$(kubectl get domain  -n ${domain_ns} -o jsonpath="{..image}")
new_domain_image=$(generate_domain_img_tag ${metadata_file} ${build_timestamp})

echo "Using running domain image: ${existing_domain_image}"
echo "New domain image will be: ${new_domain_image}"


# Stages in deployment
# TODO Add deployment flag
if [[ $CLI_MODE = true ]]
then
    # This block of script is only executed when -c option is set. It is equivalent to deploy_apps_cli_test.sh.
    START_TIME=$(date +%s)

    # 0. Pre-check - Ensure domain with existing_domain_image has server pods in ready state
    validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}

    if [[ ! -z ${OPATCH_PATCH_LIST} ]] && [[ -z ${FMW_INSTALLER} ]]
    then
        apply_opatch "${OPATCH_PATCH_LIST}" ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${current_dir} ${build_timestamp} ${existing_domain_image} ${new_domain_image}
    elif [[ ! -z ${FMW_INSTALLER} ]]
    then
        rebase_full_install ${FMW_INSTALLER} ${JDK_INSTALLER} "${OPATCH_PATCH_LIST}" ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${current_dir} ${build_timestamp} ${existing_domain_image} ${new_domain_image}
    elif [[ -n ${WDT_MODEL} ]] || [[ -n ${WDT_ARCHIVE} ]]
    then
        # 1. Build
        build_domain_img ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${domain_uid} ${current_dir} ${build_timestamp} ${existing_domain_image} ${SAMPLE_APP_DEPLOY} ${SAMPLE_APP_UNDEPLOY} ${new_domain_image} ${MODEL_ENCRYPT_PASSPHRASE} ${MODEL_PROPERTIES_FILE}

        # 2. Rebase domain image
        rebase_domain ${build_timestamp} ${base_domain_img} ${current_dir} ${new_domain_image}
    fi

    if [[ ! -z ${OPATCH_PATCH_LIST} ]] || [[ -n ${WDT_MODEL} ]] || [[ -n ${WDT_ARCHIVE} ]] || [[ ! -z ${FMW_INSTALLER} ]]
    then
        # 2'. Scan image for vulnerabilities
        scan_image ${build_timestamp} ${current_dir} ${new_domain_image} ${SCAN_IMAGE_ENABLED}

        # 3. OCIR push domain image
        ocir_push_domain_img ${build_timestamp} ${ocir_url} ${current_dir} ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}

        # 2. Test
        test_domain_img ${existing_domain_image} ${build_timestamp} ${metadata_file} ${current_dir} ${new_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

        # 3. Test domain validation
        validate_running_test_domain ${domain_ns} ${current_dir} ${build_timestamp}

        # 4. Deploy domain
        deploy_domain_img ${domain_uid} ${build_timestamp} ${domain_ns} ${new_domain_image} ${current_dir}

        if [[ $? -ne 0 ]] && [[ ${ROLLBACK_ENABLED} = true ]]
        then
            # Rollback the domain
            rollback_domain ${domain_uid} ${build_timestamp} ${domain_ns} ${current_dir} ${existing_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}
        fi

        # 5. Domain validation
        validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}

        if [[ $? -ne 0 ]] && [[ ${ROLLBACK_ENABLED} = true ]]
        then
            # Rollback the domain
            rollback_domain ${domain_uid} ${build_timestamp} ${domain_ns} ${current_dir} ${existing_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}
        fi
    fi

    if [[ ! -z ${JDK_INSTALLER} ]] && [[ -z ${FMW_INSTALLER} ]]
    then
        # Use kubectl to read the image being used by currently running domain
        existing_domain_image=$(kubectl get domain  -n ${domain_ns} -o jsonpath="{..image}")
        new_ts=$(date +"%y-%m-%d_%H-%M-%S")
        new_domain_image=$(generate_domain_img_tag ${metadata_file} ${new_ts})

        apply_jdk "${JDK_INSTALLER}" ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${current_dir} ${build_timestamp} ${existing_domain_image} ${new_domain_image}

        # 2'. Scan image for vulnerabilities
        scan_image ${build_timestamp} ${current_dir} ${new_domain_image} ${SCAN_IMAGE_ENABLED}

        # 3. OCIR push domain image
        ocir_push_domain_img ${build_timestamp} ${ocir_url} ${current_dir} ${metadata_file} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}

        # 2. Test
        test_domain_img ${existing_domain_image} ${build_timestamp} ${metadata_file} ${current_dir} ${new_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN}

        # 3. Test domain validation
        validate_running_test_domain ${domain_ns} ${current_dir} ${build_timestamp}

        # 4. Deploy domain
        deploy_domain_img ${domain_uid} ${build_timestamp} ${domain_ns} ${new_domain_image} ${current_dir}

        if [[ $? -ne 0 ]] && [[ ${ROLLBACK_ENABLED} = true ]]
        then
            # Rollback the domain
            rollback_domain ${domain_uid} ${build_timestamp} ${domain_ns} ${current_dir} ${existing_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}
        fi

        # 5. Domain validation
        validate_running_domain ${domain_ns} ${current_dir} ${build_timestamp} ${domain_uid}

        if [[ $? -ne 0 ]] && [[ ${ROLLBACK_ENABLED} = true ]]
        then
            # Rollback the domain
            rollback_domain ${domain_uid} ${build_timestamp} ${domain_ns} ${current_dir} ${existing_domain_image} ${OCIR_USER} ${OCIR_AUTH_TOKEN} ${new_domain_image}
        fi
    fi

    END_TIME=$(date +%s);
    echo "Complete pipeline execution took:"
    echo $((END_TIME-START_TIME)) | awk '{print int($1/60)"m:"int($1%60)"s"}'

    # Cleanup
    exit_with_cleanup 0 ${current_dir} ${build_timestamp}
fi
