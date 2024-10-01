#!/bin/bash

#### vars
aws_ips_url="https://d7uri8nf7uskq.cloudfront.net/tools/list-cloudfront-ips"

#### functions
_help()
{
    echo "Usage: $0 -c HAPROXY-CONFIG-FRONTEND"
    echo ""
    echo "Update haproxy config-frontend with cloudfront aws ips."
    echo ""
    echo "-c, --config         haproxy config-frontend file reference"
    echo ""
}

usage()
{
    echo "Try -h | --help for more information."
}

get_params()
{
    MANDATORY_ARGS=1
    if [ $# -eq 0 ]; then
        usage; exit 1
    fi  

    while [ "$1" != "" ]; do
        case "$1" in
            -h | --help )
                _help "$@"; exit 0
                ;;
            -c | --config )
                if [ "$2" != "" ]; then
	            haproxy_config_frontend=$2
                    shift
                    MANDATORY_ARGS=$(( MANDATORY_ARGS-1 ))
                else
                    usage; exit 1
                fi
                ;;
            * )
                usage; exit 1
        esac
        shift
    done
}

#### main

get_params "$@"

aws_ips=$(wget -qO - ${aws_ips_url} | jq -r '. | .[]' | grep '"' | cut -d\" -f2 | sort)
haproxy_ips=$(cat ${haproxy_config_frontend} |grep '^acl ips_aws' | cut -d' ' -f4 | sort)
diff_aws_haproxy_ips=$(diff <(echo "$aws_ips") <(echo "$haproxy_ips"))

ips_to_add=$(grep '<' <(echo "$diff_aws_haproxy_ips") |cut -d" " -f2)
ips_to_del=$(grep '>' <(echo "$diff_aws_haproxy_ips") |cut -d" " -f2)
ips_to_keep=$(grep -v -f <(echo "$ips_to_del") <(echo "$haproxy_ips"))

new_aws_ips="$ips_to_keep"$'\n'
new_aws_ips+=$ips_to_add
new_aws_ips="$(cat <(echo "$new_aws_ips") |sort)"

aws_comment_mark='^#ips aws'
bignumber=999999
config_frontend_before_aws_ips=$(grep "$aws_comment_mark" -B $bignumber ${haproxy_config_frontend})
config_frontend_aws_ips=$(for i in `echo $new_aws_ips`; do echo "acl ips_aws src ${i}"; done)
config_frontend_after_aws_ips=$(grep "$aws_comment_mark" -A $bignumber ${haproxy_config_frontend} |grep -v "^acl ips_aws\|${aws_comment_mark}")

new_config_frontend="$config_frontend_before_aws_ips"$'\n'
new_config_frontend+="$config_frontend_aws_ips"$'\n'
new_config_frontend+=$config_frontend_after_aws_ips

cat <(echo "$new_config_frontend")
