#!/bin/bash

install () {
    # INSTALL PHASE
    printf "Installing app dependencies... \n\n"
    curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl   
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
    source ~/.bashrc
    printf '\nCheck kubectl & aws version: \n\n'
    kubectl version --short --client
    aws --version

    # PRE-BUILD
    # EKS PART
    printf "\n\nLogging into Amazon EKS...\n"
    echo "Caller identity:"
    aws sts get-caller-identity

    # printf "Assuming eks role \n"
    #aws sts assume-role --role-arn $EKS_ROLE --role-session-name test
    echo "using cloudformation role"
    CLOUDFORMATION_ROLE="arn:aws:iam::356403663115:role/mi-aplicacion-cloudformation-role-test"

    #echo "Extracting AWS Credential Information using STS Assume Role for kubectl"
    # printf "\n\n Setting Environment Variables related to AWS CLI for Kube Config Setup \n"          
    CREDENTIALS=$(aws sts assume-role --role-arn ${CLOUDFORMATION_ROLE} --role-session-name codebuild-kubectl)
    export AWS_ACCESS_KEY_ID="$(echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId')"
    export AWS_SECRET_ACCESS_KEY="$(echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey')"
    export AWS_SESSION_TOKEN="$(echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken')"
    export AWS_EXPIRATION=$(echo ${CREDENTIALS} | jq -r '.Credentials.Expiration')
    
    # printf "\nCheck caller identity again \n"
    # aws sts get-caller-identity

    # Setup kubectl with our EKS Cluster              
    printf "\n\nUpdate Kube Config \n"      
    # aws eks update-kubeconfig --name $AWS_CLUSTER_NAME --role-arn $EKS_ROLE
    aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $AWS_CLUSTER_NAME --role-arn $CLOUDFORMATION_ROLE

    export KUBECONFIG=$HOME/.kube/config

    printf "\n\nCheck config: \n"
    kubectl config view --minify
    kubectl config get-contexts

    printf "\n\nCheck auth map config \n"
    kubectl describe configmap/aws-auth -n kube-system
    printf "\n\nUpdating config map"
    ROLE="    - rolearn: ${EKS_ROLE}\n      username: build\n      groups:\n        - system:masters"
    kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"${ROLE}\";next}1" > /tmp/aws-auth-patch.yml
    kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"

    # Check access
    printf "\n\nCheck kubectl access \n"
    
    kubectl get svc

    if [ $? -eq 0 ]; then
        
        build
    else
        printf "\n\n ERROR WHILE LOGIN \n\n"
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
  install
}

main "$@"