#!/bin/bash

create_cloudformation_stack () {
  echo "Creating the needed cloudformation role"
  roleName="mi-aplicacion-cloudformation-role-${ENVIRONMENT_TYPE}"
  roleArn=$(aws --profile="${AWS_CLI_PROFILE}" iam create-role --role-name $roleName --assume-role-policy-document "${ROLE_TRUST_POLICY_FILE}" --output text --query 'Role.Arn')
  
  if [ -z "${roleArn}" ]; then
    echo "Error while creating the role"
    exit 1;
  fi

  echo "The $roleName role arn is: $roleArn"
  echo "Embed the permissions policy to the role to specify what it is allowed to do"
  aws --profile="${AWS_CLI_PROFILE}" iam put-role-policy \
  --role-name "$roleName" \
  --policy-name "mi-aplicacion-cloudformation-policy-${ENVIRONMENT_TYPE}" \
  --policy-document "${ROLE_POLICY_FILE}"

  echo "waiting 10s so that cloudformation recognizes the newly created role"
  sleep 10

  echo "Creating the cloudformation stack and change set"
  stackId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
  --stack-name "mi-aplicacion-api-${ENVIRONMENT_TYPE}" \
  --template-body "${API_STACK_TEMPLATE}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --role-arn "$roleArn" \
  --change-set-name "mi-aplicacion-api-${ENVIRONMENT_TYPE}-changeset" \
  --change-set-type CREATE \
  --output text --query 'StackId')

  if [ -z "${stackId}" ]; then
    echo "Error while creating the cloudformation API stack"
    exit 1;
  fi

  echo "Cloudformation mi-aplicacion-api-${ENVIRONMENT_TYPE} stack created with the id $stackId"

  aws cloudformation describe-stacks --stack-name "mi-aplicacion-api-${ENVIRONMENT_TYPE}" > stack_info.json

  # Extract output values into a json
  repository_name=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="RepositoryName").OutputValue' stack_info.json)
  cluster_name=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="ClusterName").OutputValue' stack_info.json)

  # Remove temp json
  rm stack_info.json


  echo "Creating the cloudformation pipeline stack and change set"

  pipelineChangeSetId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
  --stack-name "mi-aplicacion-pipeline-${ENVIRONMENT_TYPE}" \
  --template-body "${PIPELINE_STACK_TEMPLATE}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" ParameterKey="PipelineConnectionArn",ParameterValue="${PIPELINE_CONNECTION_ARN}" ParameterKey="RepositoryId",ParameterValue="${REPOSITORY_ID}" ParameterKey="RepositoryBranch",ParameterValue="${REPOSITORY_BRANCH}" ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" ParameterKey="S3Bucket",ParameterValue="mi-aplicacion-${ENVIRONMENT_TYPE}-artifacts" ParameterKey="CFRole",ParameterValue="$roleArn" ParameterKey="RepositoryName",ParameterValue=$repository_name ParameterKey="ClusterName",ParameterValue=$cluster_name \
  --role-arn "$roleArn" \
  --change-set-name "mi-aplicacion-pipeline-${ENVIRONMENT_TYPE}-changeset" \
  --change-set-type CREATE \
  --output text --query 'Id')

  if [ -z "${pipelineChangeSetId}" ]; then
    echo "Error while creating the pipeline stack"
    exit 1;
  fi


  echo "Cloudformation mi-aplicacion-pipeline-${ENVIRONMENT_TYPE} stack created with the changeSet $pipelineChangeSetId"

  # It will poll every 30 seconds until a successful state has been reached
  echo "Waiting for changeSet to be in status CREATE_COMPLETE"

  aws --profile="${AWS_CLI_PROFILE}" cloudformation wait change-set-create-complete --change-set-name "$pipelineChangeSetId"

  echo "Executing the change set of the mi-aplicacion-pipeline-${ENVIRONMENT_TYPE} stack"

  aws --profile="${AWS_CLI_PROFILE}" cloudformation execute-change-set --change-set-name "$pipelineChangeSetId"

  # It will poll every 30 seconds until a successful state has been reached
  echo "Waiting for changeSet to be executed"

  aws --profile="${AWS_CLI_PROFILE}" cloudformation wait stack-create-complete --stack-name "mi-aplicacion-pipeline-${ENVIRONMENT_TYPE}"
  
  echo "Change set execute completed"
}


main(){
  create_cloudformation_stack
}

main "$@"