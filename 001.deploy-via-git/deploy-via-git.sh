#!/bin/bash

# 1. global definitions and initializations
NOW=$(date "+%Y-%m-%d-%k%M%S")
SCRIPT_FILE=${0##*/}
SCRIPT_NAME=${SCRIPT_FILE/\.sh/}
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
TMP_SCRIPT_DIR="/tmp/${SCRIPT_NAME}.tmp"
CONFIG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME}.conf"
CLEAN_CONFIG_FILE="${TMP_SCRIPT_DIR}/${SCRIPT_NAME}.conf.clean"
OUT_FILE="${TMP_SCRIPT_DIR}/${SCRIPT_NAME}.stdout"
ERROR_FILE="${TMP_SCRIPT_DIR}/${SCRIPT_NAME}.stderr"
VERBOSE=0

# 2. functions
log_it()
{
    LEVEL="$1"
    MSG="$2"
    logger -p "user.info" "$SCRIPT_NAME: <${LEVEL}> $MSG"
    echo "$MSG"
}

trap_err()
{
    LAST_LINE="$1"
    LAST_ERR="$2"

    log_it "error" "line: $LAST_LINE."

    exit "$LAST_ERR"
}

trap_exit()
{
    LAST_ERR="$1"

    if [ "$LAST_ERR" != 0 ]; then
        log_it "error" "$(cat "$ERROR_FILE")"
        log_it "error" "exit code: $LAST_ERR."
    fi
}

read_config()
{
    ATTR_EXPR='[a-zA-Z0-9_-]'
    ATTR_EXPR_PATTERN="^${ATTR_EXPR}+=${ATTR_EXPR}+$"
    if test -f "$CONFIG_FILE"; then  
        cat $CONFIG_FILE |cut -d"#" -f1 \
                        |grep -E $ATTR_EXPR_PATTERN > "$CLEAN_CONFIG_FILE"   
        source "$CLEAN_CONFIG_FILE"
	log_it "info" "env vars loaded:"
	log_it "info" "$(cat $CLEAN_CONFIG_FILE)"
    else
        log_it "error" "config file $CONFIG_FILE does not exist."

        exit 1
    fi
}

is_git_repo()
{
    local DIR="$1"

    if test -d "${DIR}"/.git; then
        return 0
    else
        return 1
    fi
}

try_git_pull()
{
    RET=0  
    SHA1_PATTERN="^[a-fA-F0-9]{40}$"
    REMOTE_HEAD_ID=$(git ls-remote origin "$BRANCH" |cut -f1)
    
    if [[ "$REMOTE_HEAD_ID" =~ $SHA1_PATTERN ]]; then
        if git checkout "$BRANCH"; then
            LOCAL_HEAD_ID=$(git rev-parse HEAD)
            if [[ "$LOCAL_HEAD_ID" =~ $SHA1_PATTERN ]]; then
                if [ "$LOCAL_HEAD_ID" != "$REMOTE_HEAD_ID" ]; then
                    log_it "info" "pulling from $LOCAL_HEAD_ID to $REMOTE_HEAD_ID"
                    if ! git pull; then
                        RET=1
                        log_it "error" "git pull failed."
                    fi
                else
                    log_it "info" "remote head equals to local head. Nothing to do."
                fi
            else
                RET=1
                log_it "error" "LOCAL_HEAD_ID format error: $LOCAL_HEAD_ID"
            fi
        else
            RET=1
            log_it "error" "git checkout $BRANCH failed."
        fi
    else
        RET=1
        log_it "error" "REMOTE_HEAD_ID format error: $REMOTE_HEAD_ID"
    fi  
    return $RET
}

test_deploy()
{
    local TMP_REPO_DIR="${TMP_SCRIPT_DIR}/${NOW}"

    mkdir -p "$TMP_REPO_DIR"
    cp -nrf --parents "${REPO_DIR}" "$TMP_REPO_DIR"

    deploy "${TMP_REPO_DIR}/${REPO_DIR}"

    log_it "info" "'--test' duplicated your repo at $TMP_REPO_DIR."
}

deploy()
{
    cd "$1"

    if ! try_git_pull; then
        log_it "error" "try_git_pull with errors. See the logs."

        exit 1
    fi
}

_help()
{
    echo "Usage: $0 [OPTION] -b BRANCH"
    echo ""
    echo "Via git, pull REPODIR to the HEAD from BRANCH."
    echo ""
    echo "-h, --help           print this help"
    echo "-v, --verbose        print debbuging messages"
    echo "-t, --test           deploy at /tmp. Does not change REPODIR content."
    echo "-b, --branch         set the BRANCH to be pulled"
    echo ""
    echo "You must set VARS at $CONFIG_FILE"

}

usage()
{
    echo "Try -h | --help for more information about usage."
}

get_params()
{
    MANDATORY_ARGS=1
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    while [ "$1" != "" ]; do
        case "$1" in
            -h | --help )
                _help "$@"
                exit 0
                ;;
            -v | --verbose )
                VERBOSE=1
                ;;
            -t | --test )
                TEST=1
                ;;
            -b | --branch )
                    BRANCH=$(git check-ref-format --branch $2)
                    shift
		    MANDATORY_ARGS=$(( MANDATORY_ARGS-1 ))
                ;;
            * )
                usage
                exit 1
        esac
        shift
    done

    if [ $MANDATORY_ARGS -ne 0 ]; then
        usage
        exit 1
    fi
}


# 3. main
cd ~

if ! [[ $TMP_SCRIPT_DIR =~ ^/tmp/ ]]; then
    log_it "warn" "you set TMP_SCRIPT_DIR out of /tmp/."
fi

if ! test -d "$TMP_SCRIPT_DIR"; then
    mkdir "$TMP_SCRIPT_DIR"
fi

exec 2>"$ERROR_FILE"
trap 'trap_err $LINENO $?' ERR 
trap 'trap_exit $?' EXIT
set -o errtrace

get_params "$@"

if [ "$VERBOSE" == 0 ]; then
    exec >"$OUT_FILE"
fi

type git

read_config

if [ "$(whoami)" == ${CI_USER:?} ]; then
    if is_git_repo "${REPO_DIR:?}"; then

        if [ "${TEST:-0}" == 1 ]; then
            test_deploy
        else
            deploy "$REPO_DIR"
        fi
        
    else
        log_it "info" "REPO_DIR => $REPO_DIR is not a git repo."
    fi
else
    log_it "info" "you must run this script with $CI_USER user."
fi

exit 0

