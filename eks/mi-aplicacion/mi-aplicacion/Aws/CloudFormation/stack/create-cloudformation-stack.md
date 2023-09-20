# Create the ImmsExchange API Stack

Run the following command to create the resources for the ImmsExchange API stack. 
It will create the codePipeline stack and the ImmsExchange API stack as well. 
Just provide the required parameters to deploy to the environment you desire.

The template.yml is an empty template so that you can create a stack that then will be linked to the pipeline. 
Once the pipeline is working, the template.yml will be updated with the one that is in the project repository.

## Before start

- Consider to run everything under a linux/wsl2 OS. 
- Be sure to have aws cli profile configured (https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
- Be sure the buildspec file path is correct in the pipeline.yaml
- Have installed:
    - jq utility
    - 
    - eksctl (https://eksctl.io/introduction/#for-unix)
    - kubectl (https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

## 1. Create a connection to the repository

You need to create a connection to the repository in order to link the pipeline to the repo.
Follow this steps [Create a connection](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections-create.html)

The PIPELINE_CONNECTION_ARN is the arn of the connection you just created.

## 2. Walk through the required Parameters

| Parameter               | Description                                                                     | Example                                                                                             |
| ----------------------- | :------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| AWS_CLI_PROFILE         | AWS IAM user with enough permissions to create the resources                    | 3pg                                                                                                 |
| ROLE_TRUST_POLICY_FILE  | Trust policy to allow cloudformation to assume the required role                | file://./pipeline/policies/trust-policy.json                                                        |
| ROLE_POLICY_FILE        | Location of the trust policy file                                               | file://./pipeline/policies/policy.json                                                              |
| API_STACK_TEMPLATE      | Location of the cloudformation template for the ImmsExchange API                | file://./api/template.yml                                                                           |
| PIPELINE_STACK_TEMPLATE | Location of the cloudformation template for the ImmsExchange pipeline           | file://./pipeline/pipeline.yml                                                                      |
| PIPELINE_CONNECTION_ARN | ARN of the connection you just created as described in previous steps           | arn:aws:codestar-connections:us-east-2:356403663115:connection/68c0ec37-5bfa-40cb-935a-9e731b1faa61 |
| REPOSITORY_ID           | User and repository name (<user>/<repository>) where the API is stored			| user/repo                                                                                           |
| REPOSITORY_BRANCH       | Name of the branch that pipeline will be listening to be triggered              | main                                                                                                |
| ENVIRONMENT_TYPE        | Must be dev, qa, staging or prod                                                | test                                                                                                |
| APPLICATION_NAME        | Must be the name of the root directory of the app                               | test-app                                                                                            |

## Script

The following script is the one in charge to create the required resources, stacks and CI/CD workflow for any type of app envirnoment. 

### Important
- Grant executions privileges to the bash script.
- Be sure to run this command under the application root folder.
- If for some reason any changeset creation fail, check cloudformation events tab to see what's wrong, and if there's not anything at all just run again the full command.

## Development Environment Script

```bash
AWS_CLI_PROFILE="jorge" \
ROLE_TRUST_POLICY_FILE="file://./Aws/CloudFormation/pipeline/policies/cloudformation-trust-policy.json" \
ROLE_POLICY_FILE="file://./Aws/CloudFormation/pipeline/policies/cloudformation-policy.json" \
API_STACK_TEMPLATE="file://./Aws/CloudFormation/api/template.yml" \
PIPELINE_STACK_TEMPLATE="file://./Aws/CloudFormation/pipeline/pipeline.yml" \
PIPELINE_CONNECTION_ARN="arn:aws:codestar-connections:us-east-2:356403663115:connection/68c0ec37-5bfa-40cb-935a-9e731b1faa61" \
REPOSITORY_ID="jorgerdzf/devOps-101" \
REPOSITORY_BRANCH="main" \
ENVIRONMENT_TYPE="test" \
APPLICATION_NAME="mi-aplicacion" \
./Aws/CloudFormation/stack/create-cloudformation-stack.sh
```
