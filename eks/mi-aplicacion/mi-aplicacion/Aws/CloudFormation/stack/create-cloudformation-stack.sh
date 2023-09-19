#!/bin/bash

create_cloudformation_stack () {
  printf "\n Creating the needed cloudformation role \n"
  roleName="${APPLICATION_NAME}-cloudformation-role-${ENVIRONMENT_TYPE}"

  role_description=$(aws iam get-role --role-name "$roleName" 2>&1)

  if [ $? -eq 0 ]; then
    roleArn=$(echo "$role_description" | jq -r '.Role.Arn')
    printf " Role $roleName exists with arn: $roleArn \n"
  else
    printf " Role $roleName does not exist, proceed to add it. \n"
    roleArn=$(aws --profile="${AWS_CLI_PROFILE}" iam create-role --role-name $roleName --assume-role-policy-document "${ROLE_TRUST_POLICY_FILE}" --output text --query 'Role.Arn')
    echo "The generated $roleName role arn is: $roleArn"
    printf "\n waiting 10 seconds so that cloudformation recognizes the newly created role \n"
    sleep 10
  fi

  if [ -z "${roleArn}" ]; then
    echo "Error while reading/creating the role"
    exit 1;
  fi

  printf "\n Embed the permissions policy to the role to specify what it is allowed to do \n"
  aws --profile="${AWS_CLI_PROFILE}" iam put-role-policy \
  --role-name "$roleName" \
  --policy-name "${APPLICATION_NAME}-cloudformation-policy-${ENVIRONMENT_TYPE}" \
  --policy-document "${ROLE_POLICY_FILE}"

  #CHECK IF STACK IS ALREADY EXISTENT
  stack_description=$(aws cloudformation describe-stacks --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" 2>&1)

  if [ $? -eq 0 ]; then
    printf "\n \n Stack ${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE} has already been created. \n"
  else
    #CLOUDFORMATION STACK CREATION
    echo "Creating the cloudformation stack and change set"
    stackId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
    --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" \
    --template-body "${API_STACK_TEMPLATE}" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey="ApplicationName",ParameterValue=${APPLICATION_NAME} ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" \
    --role-arn "$roleArn" \
    --change-set-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}-changeset" \
    --change-set-type CREATE \
    --output text --query 'StackId')

    while true; do
      change_set_status=$(aws cloudformation describe-change-set --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" \
        --change-set-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}-changeset" --query "Status" --output text)
      if [ "$change_set_status" == "CREATE_COMPLETE" ]; then
        break
      elif [ "$change_set_status" == "FAILED" ]; then
        echo "Cloudformation change set creation failed."
        exit 1
      else
        echo "Waiting for cloudformation change set to be created"
        sleep 5
      fi
    done

    if [ -z "${stackId}" ]; then
      echo "Error while creating the cloudformation API stack"
      exit 1;
    fi

    printf "\n \n Cloudformation ${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE} stack created with the id $stackId \n"

    #CLOUDFORMATION STACK EXECUTION
    aws cloudformation execute-change-set --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" \
      --change-set-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}-changeset"

    #Wait until execution is complete
    while true; do
      stack_status=$(aws cloudformation describe-stacks --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" \
        --query "Stacks[0].StackStatus" --output text)
      if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ]; then
        break
      elif [ "$stack_status" == "ROLLBACK_COMPLETE" ]; then
        echo "Cloudformation stack execution has failed."
        exit 1
      else
        echo "Waiting for cloudformation stack execution to complete"
        sleep 5
      fi
    done

  fi

  # We read the template outputs
  aws cloudformation describe-stacks --stack-name "${APPLICATION_NAME}-api-${ENVIRONMENT_TYPE}" > stack_info.json

  # Extract output values into a json
  repository_name=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="RepositoryName").OutputValue' stack_info.json)
  cluster_name=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="ClusterName").OutputValue' stack_info.json)

  printf "\n Cloudformation Temple Output parameters: \n ECR Repository name: ${repository_name} \n EKS Cluster name: ${cluster_name}"
  # Remove temp json
  rm stack_info.json

  #PIPELINE STACK CREATION
  printf "\n\n Creating the cloudformation pipeline stack and change set \n"

  printf "\n Pipeline Parameters: \n ApplicationName=${APPLICATION_NAME} \n EnvironmentType=${ENVIRONMENT_TYPE} \n PipelineConnectionArn=${PIPELINE_CONNECTION_ARN} \n RepositoryID=${REPOSITORY_ID} \n RepositoryBranch=${REPOSITORY_BRANCH} \n CFRole=${roleArn} \n EKSClusterName=${cluster_name} \n"

  pipelineChangeSetId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
  --stack-name "${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE}" \
  --template-body "${PIPELINE_STACK_TEMPLATE}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters ParameterKey="ApplicationName",ParameterValue=${APPLICATION_NAME} ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" ParameterKey="PipelineConnectionArn",ParameterValue="${PIPELINE_CONNECTION_ARN}" ParameterKey="RepositoryId",ParameterValue="${REPOSITORY_ID}" ParameterKey="RepositoryBranch",ParameterValue="${REPOSITORY_BRANCH}" ParameterKey="S3Bucket",ParameterValue="${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-artifacts" ParameterKey="CFRole",ParameterValue="$roleArn" ParameterKey="EKSClusterName",ParameterValue="$cluster_name" \
  --role-arn "$roleArn" \
  --change-set-name "${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE}-changeset" \
  --change-set-type CREATE \
  --output text --query 'Id')

  #Wait for pipeline change set creation
  while true; do
    change_set_status=$(aws cloudformation describe-change-set --stack-name "${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE}" \
      --change-set-name "${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE}-changeset" --query "Status" --output text)
    if [ "$change_set_status" == "CREATE_COMPLETE" ]; then
      break
    elif [ "$change_set_status" == "FAILED" ]; then
      printf "\n\n Pipeline change set creation failed."
      exit 1
    else
      printf "\n\n Waiting for pipeline change set to be created"
      sleep 5
    fi
  done

  if [ -z "${pipelineChangeSetId}" ]; then
    echo "Error while creating the pipeline stack"
    exit 1;
  fi

  printf "\n Cloudformation ${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE} stack created with the changeSet $pipelineChangeSetId"

  #PIPELINE STACK EXECUTION
  printf "Executing the change set of the ${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE} stack"

  aws --profile="${AWS_CLI_PROFILE}" cloudformation execute-change-set --change-set-name "$pipelineChangeSetId"

  # Wait until pipeline change set (CREATE_COMPLETE o UPDATE_COMPLETE)
  while true; do
    stack_status=$(aws cloudformation describe-stacks --stack-name "${APPLICATION_NAME}-pipeline-${ENVIRONMENT_TYPE}" \
      --query "Stacks[0].StackStatus" --output text)
    if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ]; then
      break
    elif [ "$stack_status" == "ROLLBACK_COMPLETE" ]; then
      echo "Pipeline stack execution has failed."
      exit 1
    else
      printf "\n Waiting for pipeline stack execution to complete"
      sleep 5
    fi
  done

  echo "Change set execute completed"
}


main(){
  create_cloudformation_stack
}

main "$@"