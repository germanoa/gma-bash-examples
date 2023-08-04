#!/bin/bash

#Vars
NOW=$(date "+%Y-%m-%d-%H%M%S")
region="us-east-1"
arn="arn:minio:sqs:${region}:PRIMARY:elasticsearch"

#Functions
_help()
{
    echo "Usage: $0 [OPTION] -c CLUSTER -b BUCKET"
    echo ""
    echo "Create bucket (and related user and policy) in the specified cluster"
    echo ""
    echo "-c, --cluster		set the cluster"
    echo "-b, --bucket		set the bucket name"
    echo "-h, --help		print this help"
    echo "-d, --dry-run		print but do not execute the cmds to create the bucket"
    echo "-v, --verbose		print and execute the cmds to create the bucket"
    echo ""
    echo "Obs: --dry-run has higher precedence than --verbose".
}

usage()
{
    echo "Try -h | --help for more information."
}

get_params()
{
    MANDATORY_ARGS=2
    if [ $# -eq 0 ]; then
        usage; exit 1
    fi

    while [ "$1" != "" ]; do
        case "$1" in
            -h | --help )
                _help "$@"; exit 0
                ;;
            -d | --dry-run )
                DRYRUN=1
                ;;        
            -v | --verbose )
                VERBOSE=1
                ;;        
            -c | --cluster )
                if [ "$2" != "" ]; then
                    cluster=$2
                    shift
                    MANDATORY_ARGS=$(( MANDATORY_ARGS-1 ))
                else
                    usage; exit 1
                fi
                ;;        
            -b | --bucket )
                if [ "$2" != "" ]; then
                    bucket=$2
                    shift
                    MANDATORY_ARGS=$(( MANDATORY_ARGS-1 ))
                else
                    usage; exit 1
                fi
                ;;
            -p | --password )
                if [ "$2" != "" ]; then
                    password=$2
                    shift
                else
                    usage; exit 1
                fi
                ;;
            * )
                usage; exit 1
        esac
        shift
    done       

    if [ $MANDATORY_ARGS -ne 0 ]; then
        usage; exit 1
    fi
}

generate_bucket_pol()
{
    echo "{"
    echo "\"Version\": \"2012-10-17\","
    echo "\"Statement\": ["
    echo "  {"
    echo "    \"Effect\": \"Allow\","
    echo "    \"Action\": ["
    echo "      \"s3:*\""
    echo "    ],"
    echo "    \"Resource\": ["
    echo "      \"arn:aws:s3:::${bucket}\","
    echo "      \"arn:aws:s3:::${bucket}/*\""
    echo "    ]"
    echo "  }"
    echo "]"
    echo "}"
}

get_pass()
{
    echo "Please enter the password for the user $user:"
    read -s password
    while [ "$password" == "" ]; do
        echo "You must provide a non-blank password:"
        read -s password
    done
}

# Main

get_params "$@"

jqselectfilterbucket='select(.type == "folder")| select(.key == "'$bucket'/") | .key'
bucket_exist=`mc ls --json ${cluster}| jq -r "$jqselectfilterbucket" |cut -d '/' -f1`
if [ "$bucket_exist" == "$bucket" ]; then
    echo "ERROR: bucket already exists. Aborting."
    exit 1
fi

pol="${bucket}RW"
user=$bucket
temp_pol_file="/tmp/${cluster}-${pol}-${NOW}"
generate_bucket_pol > $temp_pol_file

if [ "$password" == "" ]; then
    get_pass
fi

unset cmds
cmds+=("mc mb ${cluster}/${bucket}")
cmds+=("mc event add ${cluster}/${bucket} ${arn}")
cmds+=("mc admin user add $cluster $user $password")
cmds+=("mc admin policy create $cluster $pol $temp_pol_file")
cmds+=("mc admin policy attach $cluster $pol --user $user")

for i in "${cmds[@]}"
do
    if [ "$DRYRUN" == 1 ]; then
        echo $i
    else
        if [ "$VERBOSE" == 1 ]; then echo $i; fi
        output=`$i`
        if [ $? != 0 ]; then echo $output; exit 1; fi
    fi
done

rm $temp_pol_file
