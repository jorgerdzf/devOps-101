# ImmsExchange Service API Stack creation

The following command will create the necessary resources for the ImmsExchange Service API stack. 

This execution will create the next resources (per-environment):
- ECR repository to store the generated docker images.
- EKS kubernetes cluster with working nodes.
- IAM roles to handle the creation of each service. 
- CI/CD pipeline that will orchestrate the build and deploy of this service triggered by changes to a defined code branch.

Just provide the required parameters to deploy to the environment you desire.

## Before start

- Consider to run everything under a linux/wsl2 OS. 
- It is required to have the following resources installed:
    - - aws cli profile configured (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
    - - eksctl (https://eksctl.io/introduction/#for-unix)
    - - kubectl (https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
    - - jq utility
- Be sure the *buildspec* file path is correct in the *pipeline.yaml*
- Be sure the *imageURI* for the ECR repo is updated in the corresponding kubernetes deployment.yml file. This image uri is quite easy to determine since the structure wont change unless the tag does, the structure will always be: <AWS::Account:ID>.dkr.ecr.<AWS::Region>.amazonaws.com/<ApplicationName>:<ImageTag>


## 1. Create a connection to the repository

You need to create a connection to the repository in order to link the pipeline to the repo.
Follow this steps [Create a connection](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-create.html)

The PIPELINE_CONNECTION_ARN is the arn of the connection you just created.

## 2. Walk through the required Parameters

| Parameter               | Description                                                                     | Example                                                                                             |
| ----------------------- |  ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| AWS_CLI_PROFILE         | AWS IAM user with enough permissions to create the resources                    | 3pg                                                                                                 |
| REGION                  | AWS desired region to deploy all the resources                                  | us-west-2                                                                                           |
| ROLE_TRUST_POLICY_FILE  | Trust policy to allow cloudformation to assume the required role                | file://./pipeline/policies/cloudformation-trust-policy.json                                         |
| ROLE_POLICY_FILE        | Location of the trust policy file                                               | file://./pipeline/policies/cloudformation-policy.json                                               |
| API_STACK_TEMPLATE      | Location of the cloudformation template for the ImmsExchange API                | file://./api/cloudformation-template.yml                                                            |
| PIPELINE_STACK_TEMPLATE | Location of the cloudformation template for the ImmsExchange pipeline           | file://./pipeline/pipeline.yml                                                                      |
| PIPELINE_CONNECTION_ARN | ARN of the connection you just created as described in previous steps           | arn:aws:codestar-connections:us-east-2:356403663115:connection/68c0ec37-5bfa-40cb-935a-9e731b1faa61 |
| REPOSITORY_ID           | User and repository name (<user>/<repository>) where the API is stored			| user/repo                                                                                           |
| REPOSITORY_BRANCH       | Name of the branch that pipeline will be listening to be triggered              | main                                                                                                |
| ENVIRONMENT_TYPE        | Must be dev, qa, staging or prod                                                | test                                                                                                |
| APPLICATION_NAME        | Must be the name of the root directory of the app                               | ImmsExchange *Use the real app name, inside the scripts there is some file paths depending on this  |

*Important: For the Kubernetes deployment, depending on the environment, the script will search the corresponding files under the environment path so be sure to have both deployment and service files in the corresponding folder.

## 3. Running the aws stack creation Scripts.

The following script is the one in charge to create the required resources, stacks and CI/CD workflow for any type of app envirnoment. 

```bash
AWS_CLI_PROFILE="jorge" \
REGION="us-east-2" \
ROLE_TRUST_POLICY_FILE="file://./Aws/CloudFormation/pipeline/policies/cloudformation-trust-policy.json" \
ROLE_POLICY_FILE="file://./Aws/CloudFormation/pipeline/policies/cloudformation-policy.json" \
API_STACK_TEMPLATE="file://./Aws/CloudFormation/api/cloudformation-template.yml" \
PIPELINE_STACK_TEMPLATE="file://./Aws/CloudFormation/pipeline/pipeline.yml" \
PIPELINE_CONNECTION_ARN="arn:aws:codestar-connections:us-east-2:356403663115:connection/68c0ec37-5bfa-40cb-935a-9e731b1faa61" \
REPOSITORY_ID="jorgerdzf/devOps-101" \
REPOSITORY_BRANCH="main" \
ENVIRONMENT_TYPE="test" \
APPLICATION_NAME="mi-aplicacion" \
./Aws/CloudFormation/stack/create-cloudformation-stack.sh
```
### Important
- Grant executions privileges to the bash script.
- Be sure to run this command under the application root folder. If not, then be sure to modify the file paths for the script parameters.
- If for some reason any changeset creation fails, check cloudformation events tab to see what's wrong, and if there's not anything at all just run again the full command. In case of any failure and the stack/changeSet was created, please delete it from the AWS console, fix the error and then execute the script again. In case the stack was correctly created, the script will detect this and won't try to create it again.
