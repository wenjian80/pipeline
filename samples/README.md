# Sample-app
This directory contains a sample web-application called sample-app that is deployed using the sample-app pipeline job.
The archive.zip contains the sample-app.war application archive.
The deloy_sample_app.yaml is the WebLogic Deploy Tooling model yaml file for the sample-app.

# Example deploy-apps model.yaml and variables.properties files
**deploy_apps_example_model.yaml** - is an example model.yaml showing the deployment of 1 application, 1 shared library and 
1 JDBC datasource. The model yaml file uses @@PROP:[property name]@@ (for example: @@PROP:db.password@@) and the property
is defined in **deploy_apps_example_variables.properties**.

Refer to WebLogic Deploy Tooling docs for more examples - https://github.com/oracle/weblogic-deploy-tooling