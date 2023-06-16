#!/bin/bash

#assing user and current month variables.
#TODO: in case no parameters are provided default values will be assigned ??
while getopts "o:m:" opt; do
    case $opt in
        o) ownerToFilter=$OPTARG ;;
        m) monthToFilter=$OPTARG ;;
        *)
            echo "invalid command: parameter -$OPTARG- is not valid or not present"
            # echo "assigning default values"
            # ownerToFilter=$(whoami)
            # monthToFilter=$(date +%B)
            # ;;
    esac
done

#Printing out what we will be looking for
if [ ! -z $ownerToFilter ]
then
    echo "Looking for files where the owner is: ${ownerToFilter}"
fi 

if [ ! -z $monthToFilter ]
then
    echo "Looking for files where the month is: ${monthToFilter}"
fi 


#Iterating through files in current directory
for FILE in *; do
    #check if object is a file, we don't want include directories
    if [[ -f $FILE ]]
    then
        fileName=$(stat -f $FILE)    
        creationDate=$(stat -f '%Sc' $FILE)
        fileOwner=$(ls -ld $FILE | awk '{print $3}')
        fileLines=$(wc -l < $FILE)
        #we have owner to filter
        if [ ! -z $ownerToFilter ] && [ $fileOwner == $ownerToFilter ]
            then    
                #we have both onwer and month
                if [ ! -z $monthToFilter ] && [[ "$creationDate" == *"$monthToFilter"* ]]
                    then  
                        echo "File: ${FILE}, Lines: ${fileLines}"
                #we only have owner
                elif [ ! -z $ownerToFilter ] && [ -z $monthToFilter ]
                    then
                        echo "File: ${FILE}, Lines: ${fileLines}"
                fi
        #we dont have owner but do have month
        elif [ ! -z $monthToFilter ] && [[ "$creationDate" == *"$monthToFilter"* ]]
            then
                echo "File: ${FILE}, Lines: ${fileLines}"
        fi
    fi
done
