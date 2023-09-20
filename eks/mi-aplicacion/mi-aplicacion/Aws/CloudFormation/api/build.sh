#!/bin/bash

build_and_deploy () {
# INSTALL PHASE
    printf "Installing app dependencies... \n\n"
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl   
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
    source ~/.bashrc
    printf '\n Check kubectl & aws version:'
    kubectl version --short --client
    aws --version

# PRE-BUILD
# EKS PART
    printf "\n\n Logging into Amazon EKS..."
    echo "Caller identity:"
    aws sts get-caller-identity

    printf "Assuming eks role"
    aws sts assume-role --role-arn ${EKS_ROLE} --role-session-name codebuild-kubectl
    
    printf "\n Check caller identity again"
    aws sts get-caller-identity

    #echo "Extracting AWS Credential Information using STS Assume Role for kubectl"
    #printf "\n\n Setting Environment Variables related to AWS CLI for Kube Config Setup"          
    # CREDENTIALS=$(aws sts assume-role --role-arn ${EKS_ROLE} --role-session-name codebuild-kubectl --duration-seconds 900)
    # export AWS_ACCESS_KEY_ID="$(echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId')"
    # export AWS_SECRET_ACCESS_KEY="$(echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey')"
    # export AWS_SESSION_TOKEN="$(echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken')"
    # export AWS_EXPIRATION=$(echo ${CREDENTIALS} | jq -r '.Credentials.Expiration')
    
    # Setup kubectl with our EKS Cluster              
    printf "\n Update Kube Config"      
    aws eks update-kubeconfig --name $AWS_CLUSTER_NAME
    printf "\n Check config:"
    kubectl config view --minify

    printf "\n\n Updating config map"
    ROLE="    - rolearn: ${EKS_ROLE}\n      username: build\n      groups:\n        - system:masters"
    kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"${ROLE}\";next}1" > /tmp/aws-auth-patch.yml
    kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"
    
    #- echo "- rolearn: $RoleArnParameter\n  username: <USERNAME>\n  groups:\n   system:masters" > add-role.yaml && kubectl apply -f add-role.yaml
    echo check auth map config
    kubectl describe configmap/aws-auth -n kube-system
    # Check access
    echo check kubectl access
    kubectl get svc

# ECR PART
    echo Logging in to Amazon ECR...
    REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
    IMAGE_REPO_NAME=${APPLICATION_NAME}-repo-${ENVIRONMENT_TYPE}
    IMAGE_TAG=latest
    printf "\n REPOSITORY_URI=$REPOSITORY_URI \n IMAGE_REPO_NAME=$IMAGE_REPO_NAME \n IMAGE_TAG=$IMAGE_TAG \n\n"
    aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com

# BUILD PHASE
    echo Build started on `date`
    echo Building the Docker image...  
    cd eks/${APPLICATION_NAME}
    docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG -f ${APPLICATION_NAME}/Dockerfile .
    docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $REPOSITORY_URI/$IMAGE_REPO_NAME:$IMAGE_TAG

# DEPLOY PHASE
    echo Build completed on `date`
    echo Pushing the Docker image...
    docker push $REPOSITORY_URI/$IMAGE_REPO_NAME:$IMAGE_TAG
    echo Push the latest image to cluster
    kubectl apply -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/deployment.yaml
    kubectl apply -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/service.yaml
    kubectl rollout restart -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/deployment.yaml
    kubectl get svc --all-namespaces
}

main(){
  build_and_deploy
}

main "$@"