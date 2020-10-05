"""
Copyright (c) 2020, Oracle Corporation and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.
"""
import yaml
import sys
import json
import os

TEST_SUFFIX = "-test"


def usage(args):
    """
    Prints usage.

    :param args:
    :return:
    """
    print('Args passed: ' + args)
    print("""
    Usage: python domain_builder_utils.py <operation>
    where,
        operation = create-test-domain-yaml
        args = <running_domain_yaml> <test_domain_yaml_file> <provisioning_metadata_file> <new domain image>

        operation = check-pods-ready
        args = sys.stdin
        
        operation = get-replica-count
        args = <domain_yaml_file>

    """)
    sys.exit(1)


def get_replica_count(domain_yaml_file):
    """
    Get replica count from domain yaml
    :param domain_yaml_file:
    :return:
    """
    replica_count = 0
    try:
        with open(domain_yaml_file) as f:
            domain_yaml = yaml.full_load(f)
            replica_count = domain_yaml["spec"]["clusters"][0]["replicas"]
    except Exception as ex:
        print("Error in parsing json file [%s]: %s" % (domain_yaml_file, str(ex)))

    print(str(replica_count))


def create_test_domain_yaml(running_domain_yaml_file, test_domain_yaml_file, provisioning_metadata_file,
                            new_domain_img):
    """
    Create test domain YAML file.

    :param running_domain_yaml_file:        YAML for currently running domain
    :param test_domain_yaml_file:           YAML for test domain to be created
    :param provisioning_metadata_file:      Provisioning metadata json file
    :param new_domain_img:                  New domain image to be tested
    :return:
    """
    domain_uid = get_metadata_attribute(provisioning_metadata_file, 'wls_domain_uid')
    test_domain_uid = domain_uid + TEST_SUFFIX

    with open(running_domain_yaml_file) as f:
        running_domain_yaml = yaml.full_load(f)
    with open(test_domain_yaml_file) as f:
        test_domain_yaml = yaml.full_load(f)

    # print(running_domain_yaml)
    # print(test_domain_yaml)

    test_domain_yaml["metadata"]["name"] = test_domain_uid
    test_domain_yaml["metadata"]["labels"]["weblogic.domainUID"] = test_domain_uid

    domain_ns = get_metadata_attribute(provisioning_metadata_file, 'wls_domain_namespace')
    test_domain_ns = domain_ns + TEST_SUFFIX
    test_domain_yaml["metadata"]["namespace"] = test_domain_ns
    test_domain_yaml["spec"]["clusters"][0]["replicas"] = 1

    stage_logs = running_domain_yaml["spec"]["logHome"]
    tests_logs = os.path.join(stage_logs, test_domain_uid)
    test_domain_yaml["spec"]["logHome"] = tests_logs

    test_domain_yaml["spec"]["image"] = new_domain_img

    with open(test_domain_yaml_file, 'w') as f:
        yaml.dump(test_domain_yaml, f)

    print("Successfully created test domain yaml [%s]" % test_domain_yaml_file)


def check_pods_ready(file):
    """
    Check if pods are ready and print the count of pods that are in ready state
    :param file:    stdin file descriptor
    :return:
    """
    count = 0
    try:
        a = json.load(file)

        for i in a['items']:
            for j in i['status']['conditions']:
                if j['status'] == "True" and j['type'] == "Ready" and i['status']['phase'] == 'Running':
                    # print(i['metadata']['name'])
                    count = count + 1
    except:
        print("The data from stdin doesn't appear to be valid json. Fix this!")
        sys.exit(1)
    print(count)


def get_ocir_user(ocir_url, file):
    """
    Get OCIR user from the input ocirsecrets auths json.

    :param ocir_url: e.g. phx.ocir.io
    :param file: stdin from kubectl command to read ocirsecrets json.
    :return:
    """
    try:
        a = json.load(file)
        if 'Username' in a['auths'][ocir_url]:
            print(a['auths'][ocir_url]['Username'])
        else:
            print(a['auths'][ocir_url]['username'])
    except:
        print("The data from stdin doesn't appear to be valid json. Fix this!")
        sys.exit(1)

def get_ocir_auth_token(ocir_url, file):
    """
    Get OCIR auth token from the input ocirsecrets auths json.

    :param ocir_url: e.g. phx.ocir.io
    :param file: stdin from kubectl command to read ocirsecrets json.
    :return:
    """
    try:
        a = json.load(file)
        if 'Password' in a['auths'][ocir_url]:
            print(a['auths'][ocir_url]['Password'])
        else:
            print(a['auths'][ocir_url]['password'])
    except:
        print("The data from stdin doesn't appear to be valid json. Fix this!")
        sys.exit(1)

def get_metadata_attribute(file, attr):
    """
    Get Metadata attribute from the provisioning metadata file.

    :param file:    Provisioning metadata file.
    :param attr:    Attribute to look for.
    :return:
    """
    with open(file) as f:
        try:
            data = json.load(f)
            #print("attr: " + data[attr])
            return data[attr]
        except Exception as ex:
            print("Error in parsing json file [%s] or failed to get attribute [%s] : %s" % (file, attr, str(ex)))
            sys.exit(2)


def main():
    if len(sys.argv) < 2:
        usage(sys.argv)
    try:
        operation = sys.argv[1]

        if operation == 'create-test-domain-yaml':
            if len(sys.argv) < 6:
                usage(sys.argv)
            running_domain_yaml_file = sys.argv[2]
            test_domain_yaml_file = sys.argv[3]
            provisioning_metadata_file = sys.argv[4]
            new_domain_img = sys.argv[5]

            create_test_domain_yaml(running_domain_yaml_file, test_domain_yaml_file, provisioning_metadata_file,
                                    new_domain_img)
        elif operation == 'check-pods-ready':
            check_pods_ready(sys.stdin)
        elif operation == 'get-ocir-user':
            ocir_url = sys.argv[2]
            get_ocir_user(ocir_url, sys.stdin)
        elif operation == 'get-ocir-auth-token':
            ocir_url = sys.argv[2]
            get_ocir_auth_token(ocir_url, sys.stdin)
        elif operation == 'get-replica-count':
            if len(sys.argv) < 3:
                usage(sys.argv)
            domain_yaml_file = sys.argv[2]
            get_replica_count(domain_yaml_file)

    except Exception as ex:
        print("Error: " + str(ex))
        sys.exit(1)


if __name__ == "__main__":
    main()
