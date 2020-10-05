#!groovy
/**
 * Copyright (c) 2020, Oracle Corporation and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
 */

/* Jenkinsfile for sample-app.war deployment. */

def ARGS = ""
pipeline {
    agent {
        node {
            label 'agent-label-slave'
        }
    }
    options {
        skipStagesAfterUnstable()
        disableConcurrentBuilds()
        timestamps()
        warnError('Pipeline error caught')
    }
    parameters {
        booleanParam defaultValue: false, description: 'Undeploy sample-app.war', name: 'Undeploy_Sample_App'
        booleanParam defaultValue: true, description: 'Rollback to previous state if Apply Domain fails.', name: 'Rollback_On_Failure'
//        booleanParam defaultValue: false, description: 'Scan domain image for security vulnerabilities.', name: 'Scan_Image_Enabled'
    }
    environment {
        BUILD_TS = getBuildTimestamp()
    }
    stages {
        stage("PRE-CHECK") {
            steps {
                echo "Validating Domain is running... "
                echo "OCIR_User: ${params.OCIR_User}"
                echo "Rollback_On_Failure: ${params.Rollback_On_Failure}"
//                echo "Scan_Image: ${params.Scan_Image_Enabled}"

                script {
                    if (params.Undeploy_Sample_App) {
                        ARGS += "-T "
                    } else {
                        ARGS += "-t "
                    }

                    if (params.Rollback_On_Failure) {
                        ARGS += "-r "
                    }

//                    if (params.Scan_Image_Enabled) {
//                        ARGS += "-s "
//                    }

                    sh "/u01/shared/scripts/pipeline/common/precheck_common.sh ${ARGS}"
                }

            }
            post {
                failure {
                    echo "Failed in pre-check"
                }
                unstable {
                    echo "Unstable in pre-check"
                }
            }
        }
        stage('BUILD_DOMAIN') {
            steps {
                echo "Building Domain... "
                sh "/u01/shared/scripts/pipeline/deployments/deploy_apps_build_domain.sh ${ARGS}"
            }
            post {
                failure {
                    echo "Failed in build domain"
                }
                unstable {
                    echo "Unstable in build domain"
                }
            }
        }
        stage("REBASE") {
            steps {
                echo "Rebasing Domain image... "
                sh "/u01/shared/scripts/pipeline/deployments/deploy_apps_rebase_domain.sh ${ARGS}"
            }
            post {
                failure {
                    echo "Failed in rebase domain"
                }
                unstable {
                    echo "Unstable in rebase domain"
                }
            }
        }
        /* Scan Image stage:
            Scan the new image for vulnerabilities.
         */
//        stage("SCAN_IMAGE") {
//            steps {
//                echo "Scanning image for vulnerabilities..."
//                sh "/u01/shared/scripts/pipeline/common/scan_domain_img_common.sh ${ARGS}"
//            }
//            post {
//                failure {
//                    echo "Failed in scanning image"
//                }
//                unstable {
//                    echo "Unstable in scanning image"
//                }
//            }
//        }
        stage("OCIR_UPLOAD") {
            steps {
                echo "Pushing Domain image to OCIR... "
                sh "/u01/shared/scripts/pipeline/common/ocir_push_domain_img_common.sh ${ARGS}"
            }
            post {
                failure {
                    echo "Failed in pushing domain to OCIR"
                }
                unstable {
                    echo "Unstable in pushing domain to OCIR"
                }
            }
        }
       stage("TEST_AND_DEPLOY_DOMAIN") {
           steps {
               build job: 'test-and-deploy-domain-job',
                       parameters: [
                               string(name: 'ARGS', value: "${ARGS}"),
                               string(name:'BUILD_TS', value:"${BUILD_TS}")
                       ]
           }
       }
    }
}
/**
 * Generating build timestamp.
 * This will be used to tag the updated domain docker image.
 */
def getBuildTimestamp() {
    Date date = new Date()
    buildTimestamp = date.format('yy-MM-dd_HH-mm-ss')
    println("Generated Build Timestamp: " + buildTimestamp)
    return buildTimestamp
}