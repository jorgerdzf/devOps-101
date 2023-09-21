#!/bin/bash

install () {
    # INSTALL PHASE
    printf "\n\n Installing app dependencies... \n"
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl   
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
    source ~/.bashrc
    printf '\n\nCHECK EKSCTL, KUBECTL & AWS VERSIONS: \n'
    echo "EKSCTL VERSION: $(eksctl version)"
    echo "KUBECTL VERSION: $(kubectl version --short --client)"
    echo "AWS VERSION: $(aws --version)"

    # PRE-BUILD
    # EKS PART
    printf "\n\nLogging into Amazon EKS...\n"
    echo "CALLER IDENTITY:"
    aws sts get-caller-identity

    #printf "\n\nASSUMING CLOUDFORMATION ROLE: \n"
    #echo "Extracting AWS Credential Information using STS Assume Role for kubectl"
    # printf "\n\n Setting Environment Variables related to AWS CLI for Kube Config Setup \n"          
    # CREDENTIALS=$(aws sts assume-role --role-arn ${$CLOUDFORMATION_ROLE} --role-session-name codebuild-kubectl)
    # export AWS_ACCESS_KEY_ID="$(echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId')"
    # export AWS_SECRET_ACCESS_KEY="$(echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey')"
    # export AWS_SESSION_TOKEN="$(echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken')"
    # export AWS_EXPIRATION=$(echo ${CREDENTIALS} | jq -r '.Credentials.Expiration')
    
    # Setup kubectl with our EKS Cluster              
    printf "\n\nUpdate Kube Config \n"      
    # aws eks update-kubeconfig --name $AWS_CLUSTER_NAME --role-arn $CLOUDFORMATION_ROLE
    aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $AWS_CLUSTER_NAME #--role-arn $CLOUDFORMATION_ROLE

    #export KUBECONFIG=$HOME/.kube/config
    printf "\nCheck caller identity again \n"
    aws sts get-caller-identity

    printf "\n\nCheck config: \n"
    kubectl config view --minify
    kubectl config get-contexts

    printf "\n\nCheck iam identity mapping: \n"
    eksctl get iamidentitymapping --cluster $AWS_CLUSTER_NAME --region=$AWS_DEFAULT_REGION

    printf "\n\Add identity mappings: \n"
    eksctl create iamidentitymapping --cluster $AWS_CLUSTER_NAME --region=$AWS_DEFAULT_REGION \
    --arn $EKS_ROLE --username admin --group system:masters \
    --no-duplicate-arns

    if [ $? -eq 0 ]; then   
        # Check config maps
        printf "\n\nCheck auth map config \n"
        kubectl describe configmap/aws-auth -n kube-system

        # Check access
        printf "\n\nCheck kubectl access \n"
        kubectl get svc

        if [ $? -eq 0 ]; then
            build
        else
            printf "\n\n ERROR WHILE LOGIN \n\n"
            exit 1
        fi
    else
        printf "\n\n ERROR CREATING IDENTITY MAPPING \n\n"
        exit 1
    fi
}
build () {
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

    if [ $? -eq 0 ]; then
        deploy
    else
        echo "Error while building app"
        exit 1
    fi
}
deploy () {
    # DEPLOY PHASE
    printf "\n\n BUILD COMPLETED ON `date` \n"
    printf "\n\n PUSHING DOCKER IMAGE TO ECR... `date` \n"
    docker push $REPOSITORY_URI/$IMAGE_REPO_NAME:$IMAGE_TAG
    printf "\n\n PUSHING IMAGE TO EKS... `date` \n"
    kubectl apply -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/deployment.yaml
    kubectl apply -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/service.yaml
    kubectl rollout restart -f ${APPLICATION_NAME}/Aws/Kubernetes/${ENVIRONMENT_TYPE}/deployment.yaml

    printf "\n\n CHECK CLUSTER COINFIGS `date` \n"
    kubectl get svc --all-namespaces
    kubectl get services
    kubectl get deployments
    kubectl get nodes
    kubectl cluster-info
}
main(){
  install
}

main "$@"