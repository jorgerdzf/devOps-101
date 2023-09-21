#!/bin/bash

create_cloudformation_stack () {
  printf "\nCreating the needed cloudformation role... \n\n"
  CLOUDFORMATION_ROLE_NAME="${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-cloudformation-role"
  CLOUDFORMATION_ROLE_DESCRIPTION=$(aws iam get-role --role-name "$CLOUDFORMATION_ROLE_NAME" 2>&1)

  if [ $? -eq 0 ]; then
    CLOUDFORMATION_ROLE_ARN=$(echo "$CLOUDFORMATION_ROLE_DESCRIPTION" | jq -r '.Role.Arn')
    printf "Role $CLOUDFORMATION_ROLE_NAME exists with arn: $CLOUDFORMATION_ROLE_ARN \n"
  else
    printf "Role $CLOUDFORMATION_ROLE_NAME does not exist, proceed to add it. \n"
    CLOUDFORMATION_ROLE_ARN=$(aws --profile="${AWS_CLI_PROFILE}" iam create-role --role-name $CLOUDFORMATION_ROLE_NAME --assume-role-policy-document "${ROLE_TRUST_POLICY_FILE}" --output text --query 'Role.Arn')
    echo "The generated $CLOUDFORMATION_ROLE_NAME role arn is: $CLOUDFORMATION_ROLE_ARN"
    
    printf "\nEmbed the permissions policy to the role to specify what it is allowed to do \n"
    aws --profile="${AWS_CLI_PROFILE}" iam put-role-policy \
    --role-name "$CLOUDFORMATION_ROLE_NAME" \
    --policy-name "${APPLICATION_NAME}-cloudformation-policy-${ENVIRONMENT_TYPE}" \
    --policy-document "${ROLE_POLICY_FILE}"

    printf "\n*** Waiting 30 seconds so that cloudformation recognizes the newly created role \n"
    sleep 30
  fi

  if [ -z "${CLOUDFORMATION_ROLE_ARN}" ]; then
    echo "Error while reading/creating the role"
    exit 1;
  fi

  STACK_NAME=${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-app
  #CHECK IF STACK IS ALREADY EXISTENT
  STACK_DESCRIPTION=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" 2>&1)
  
  if [ $? -eq 0 ]; then
    printf "\n \n Stack ${STACK_NAME} has already been created. \n"
  else
    #CLOUDFORMATION STACK CREATION
    echo "Creating the cloudformation stack and change set"
    stackId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
    --stack-name "${STACK_NAME}" \
    --template-body "${API_STACK_TEMPLATE}" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey="ApplicationName",ParameterValue=${APPLICATION_NAME} ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" \
    --role-arn "$CLOUDFORMATION_ROLE_ARN" \
    --change-set-name "${STACK_NAME}-changeset" \
    --change-set-type CREATE \
    --output text --query 'StackId')

    while true; do
      change_set_status=$(aws cloudformation describe-change-set --stack-name "${STACK_NAME}" \
        --change-set-name "${STACK_NAME}-changeset" --query "Status" --output text)
      if [ "$change_set_status" == "CREATE_COMPLETE" ]; then
        break
      elif [ "$change_set_status" == "FAILED" ]; then
        echo "Cloudformation change set creation failed."
        exit 1
      else
        echo "Waiting for cloudformation change set to be created"
        sleep 10
      fi
    done

    if [ -z "${stackId}" ]; then
      echo "Error while creating the cloudformation API stack"
      exit 1;
    fi

    printf "Cloudformation ${STACK_NAME} stack created with the id $stackId. Proceed to execute changeset...\n\n"

    #CLOUDFORMATION STACK EXECUTION
    aws cloudformation execute-change-set --stack-name "${STACK_NAME}" \
      --change-set-name "${STACK_NAME}-changeset"

    #Wait until execution is complete
    while true; do
      stack_status=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
        --query "Stacks[0].StackStatus" --output text)
      if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ]; then
        break
      elif [ "$stack_status" == "ROLLBACK_COMPLETE" ]; then
        echo "Cloudformation stack execution has failed."
        exit 1
      else
        echo "Waiting for cloudformation stack execution to complete"
        sleep 10
      fi
    done

  fi

  # We read the template outputs
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" > stack_info.json

  # Extract output values into a json
  REPOSITORY_NAME=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="RepositoryName").OutputValue' stack_info.json)
  CLUSTER_NAME=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="ClusterName").OutputValue' stack_info.json)
  EKS_ARN=$(jq -r '.Stacks[0].Outputs[] | select(.OutputKey=="EksClusterRoleArn").OutputValue' stack_info.json)

  printf "\nCodePipeline Input Parameters: \n \
  Application Name: ${APPLICATION_NAME} \n \
  Environment Type: ${ENVIRONMENT_TYPE} \n \
  Pipeline Source Connection ARN: ${PIPELINE_CONNECTION_ARN} \n \
  ECR Repository Id: ${REPOSITORY_NAME} \n \
  Code Repository Branch: ${REPOSITORY_BRANCH} \n \
  S3 Bucket: ${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-artifacts \n \
  EKS Cluster name: ${CLUSTER_NAME} \n \
  CloudFormation Role ARN=${CLOUDFORMATION_ROLE_ARN} \n \
  Cluster Role ARN: ${EKS_ARN} \n"

  # Remove temp json
  rm stack_info.json

  #PIPELINE STACK CREATION
  printf "\n\n Creating the cloudformation pipeline stack and change set:"
  PIPELINE_NAME=${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-pipeline
  
  pipelineChangeSetId=$(aws --profile="${AWS_CLI_PROFILE}" cloudformation create-change-set \
  --stack-name "${PIPELINE_NAME}" \
  --template-body "${PIPELINE_STACK_TEMPLATE}" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters ParameterKey="ApplicationName",ParameterValue=${APPLICATION_NAME} ParameterKey="EnvironmentType",ParameterValue="${ENVIRONMENT_TYPE}" ParameterKey="PipelineConnectionArn",ParameterValue="${PIPELINE_CONNECTION_ARN}" ParameterKey="RepositoryId",ParameterValue="${REPOSITORY_ID}" ParameterKey="RepositoryBranch",ParameterValue="${REPOSITORY_BRANCH}" ParameterKey="S3Bucket",ParameterValue="${APPLICATION_NAME}-${ENVIRONMENT_TYPE}-artifacts" ParameterKey="CFRole",ParameterValue="$CLOUDFORMATION_ROLE_ARN" ParameterKey="EKSClusterName",ParameterValue="$CLUSTER_NAME" ParameterKey="EksClusterRoleArn",ParameterValue="$EKS_ARN"\
  --role-arn "$CLOUDFORMATION_ROLE_ARN" \
  --change-set-name "${PIPELINE_NAME}-changeset" \
  --change-set-type CREATE \
  --output text --query 'Id')

  #Wait for pipeline change set creation
  while true; do
    change_set_status=$(aws cloudformation describe-change-set --stack-name "${PIPELINE_NAME}" \
      --change-set-name "${PIPELINE_NAME}-changeset" --query "Status" --output text)
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

  printf "\n Cloudformation ${PIPELINE_NAME} stack created with the changeSet $pipelineChangeSetId"

  #PIPELINE STACK EXECUTION
  printf "Executing the change set of the ${PIPELINE_NAME} stack"

  aws --profile="${AWS_CLI_PROFILE}" cloudformation execute-change-set --change-set-name "$pipelineChangeSetId"

  # Wait until pipeline change set (CREATE_COMPLETE o UPDATE_COMPLETE)
  while true; do
    stack_status=$(aws cloudformation describe-stacks --stack-name "${PIPELINE_NAME}" \
      --query "Stacks[0].StackStatus" --output text)
    if [ "$stack_status" == "CREATE_COMPLETE" ] || [ "$stack_status" == "UPDATE_COMPLETE" ]; then
      break
    elif [ "$stack_status" == "ROLLBACK_COMPLETE" ]; then
      echo "Pipeline stack execution has failed."
      exit 1
    else
      printf "\n Waiting for pipeline stack execution to complete"
      sleep 10
    fi
  done

  echo "Change set execute completed"
}


main(){
  create_cloudformation_stack
}

main "$@"