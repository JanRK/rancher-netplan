#!/bin/bash

if [ ! -z $1 ]
then
    SERVER=$2

    FILE=./company
    if [ ! -f "$FILE" ]; then
        read -p "Enter company: " company
        echo $company > ./company
    else
        company=$(cat ./company)
    fi


    FILE=./username
    if [ ! -f "$FILE" ]; then
        read -p "Enter username: " USER
        echo $USER > ./username
    else
        USER=$(cat ./username)
    fi

    FILE=./password
    if [ ! -f "$FILE" ]; then
        read -p "Enter password: " PWD
        echo $PWD > ./password
    else
        PWD=$(cat ./password)
    fi

    if [ -z "$SERVER" ]
    then
        read -p "Enter host/ip: " SERVER
    fi

    if [ $1 = "netplan" ]
    then
        curl https://raw.githubusercontent.com/JanRK/rancher-netplan/main/NetplanApply.sh | -s -- $SERVER $company
        # bash ./NetplanApplyTest.sh $SERVER $company
    elif [ $1 = "ssh" ]
    then
        echo Connecting to $SERVER. Use credentials ${USER}:${PWD}
        echo
        ssh -o StrictHostKeyChecking=no -tt -l $USER $SERVER
    else
        echo Unknown command $1...
    fi

else
	echo "Write netplan or ssh to run this script"
fi
