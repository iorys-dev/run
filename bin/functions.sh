#!/bin/bash
set -e

pad() {
    local s=$1
    local len=$2
    local char=${3:- }
    printf '%s%*s' "$s" $((len - ${#s})) '' | sed "s/ /${char}/g"
}

writeInfo() {
    local TEXT=$1
    local STRLEN=${#TEXT}
    local MAXLEN=$(tput cols)
    local BORDERLEN=$(($MAXLEN - 2))
    local LINELEN=$(($MAXLEN - $STRLEN - 3))
    local COLOR_OFF='\033[0m'
    local BCYAN='\033[1;36m'

    echo -en "${BCYAN}╔"
    pad "" $BORDERLEN "═"
    echo -e "╗"
    echo -en "╠ $1"
    pad "" $LINELEN " "
    echo -e "║"
    echo -en "╚"
    pad "" $BORDERLEN "═"
    echo -e "╝${COLOR_OFF}"
}

getHostIp() {
    local IP_MATCH='^(192\.168\.)|(([0-9]+\.){3}[0-9]+)'
    local HOST_IP=$(ipconfig.exe | grep -Eo ${IP_MATCH} | head -n1)

    if [ -z "$HOST_IP" ]; then
        local HOST_IP=$(ifconfig | grep -Eo ${IP_MATCH} | head -n1)
    fi

    echo "$HOST_IP"
}

getServiceIp() {
    SERVICE_NAME=$1
    SERVICE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker-compose ps -q ${SERVICE_NAME})" | sed -n '1p')
    echo "$SERVICE_IP"
}

getServicePort() {
    SERVICE_NAME=$1
    SERVICE_INTERNAL_PORT=$2
    SERVICE_PORT=$(docker-compose port ${SERVICE_NAME} ${SERVICE_INTERNAL_PORT} | sed 's/.*://')
    echo "$SERVICE_PORT"
}

printServiceInfo() {
    SERVICE_SHORT_NAME=$1
    SERVICE_CONTAINER_IP=$2
    SERVICE_MATCHED_PORT=$3
    SERVICE_DEFAULT_PORT=$4

    if [ $# -lt 5 ]; then
        local PREFIX='http://'
    else
        local PREFIX="${5}"
    fi

    echo "$(pad "${SERVICE_SHORT_NAME^} Container IP" 20 " "): ${PREFIX}${SERVICE_CONTAINER_IP}:${SERVICE_DEFAULT_PORT}"
    echo "$(pad "${SERVICE_SHORT_NAME^} Shared IP   " 20 " "): ${PREFIX}${HOST_IP}:${SERVICE_MATCHED_PORT}"
    echo "$(pad "${SERVICE_SHORT_NAME^} Localhost   " 20 " "): ${PREFIX}127.0.0.1:${SERVICE_MATCHED_PORT}"
    echo "$(pad "" 50 "-")"
}

composerInstall() {
    echo "Using container composer"
    docker-compose run php composer install -n
}

composerUpdate() {
    echo "Using container composer"
    docker-compose run php composer update -n
}

appShutdown() {
    docker-compose down

    writeInfo "Application shutdown successful"
}

curlCheck() {
    writeInfo "Run curl ${@}"
    # shellcheck disable=SC2086
    docker-compose exec php -T curl -s --max-time 5 --request GET ${@} >/dev/null && echo "OK" || echo "NO"
}

exec() {
    writeInfo "Executing docker compose exec ${@}"
    # shellcheck disable=SC2086
    docker compose exec -t ${@}
}

declare -A FUNCTIONS=(
    ["app:install"]="appInstall"
    ["composer:install"]="composerInstall"
    ["composer:update"]="composerUpdate"
    ["down"]="appShutdown"
    ["exec"]="exec"
    ["isup"]="curlCheck"
    ["help"]="help"
    ["__DEFAULT__"]="app:install"
)

# Map the function names to their descriptions
declare -A FUNCTION_DESCRIPTIONS=(
    ["app:install"]="Run fresh application install."
    ["composer:install"]="Run composer install."
    ["composer:update"]="Run composer update."
    ["down"]="Shutdown the application."
    ["exec"]="Execute command in container"
    ["isup"]="Check connectivity to external resource by curl."
    ["help"]="Show available commands (current command)."
)

# Map the function names to their descriptions
declare -A FUNCTION_USAGE=(
    ["isup"]="http://example.com"
)

# Map the function aliases to their base functions
declare -A FUNCTION_ALIAS=()

# Define the help function
showHelp() {
    FUNCTION_NAME=$1
    if [[ ! -z "$FUNCTION_NAME" ]] && [[ ! -z "${FUNCTION_ALIAS[$FUNCTION_NAME]}" ]]; then
        FUNCTION_REAL_NAME=${FUNCTION_ALIAS[$FUNCTION_NAME]}
    fi

    if [[ ! -z "$FUNCTION_NAME" ]] && [[ ! -z "${FUNCTIONS[$FUNCTION_NAME]}" ]]; then
        if [[ "${FUNCTION_USAGE[$FUNCTION_NAME]}" ]]; then
            echo "Usage: ./run $FUNCTION_NAME ${FUNCTION_USAGE[$FUNCTION_NAME]}"
        else
            echo "Usage: ./run $FUNCTION_NAME"
        fi
        echo "${FUNCTION_DESCRIPTIONS[$FUNCTION_NAME]}"
    elif [[ ! -z "$FUNCTION_REAL_NAME" ]] && [[ ! -z "${FUNCTIONS[$FUNCTION_REAL_NAME]}" ]]; then
        if [[ "${FUNCTION_USAGE[$FUNCTION_REAL_NAME]}" ]]; then
            echo "Usage: ./run $FUNCTION_NAME ${FUNCTION_USAGE[$FUNCTION_REAL_NAME]}"
        else
            echo "Usage: ./run $FUNCTION_NAME"
        fi
        echo "${FUNCTION_DESCRIPTIONS[$FUNCTION_REAL_NAME]}"
    else
        echo "Usage: ./run help [function_name]"
        echo "Available functions:"

        for function_name in "${!FUNCTIONS[@]}"; do
            if [[ "${function_name}" == "__DEFAULT__" ]]; then
                continue
            fi

            if [[ "${function_name}" == "${FUNCTIONS['__DEFAULT__']}" ]]; then
                local PREFIX=" ** "
            else
                local PREFIX="    "
            fi

            echo "${PREFIX}$(pad "${function_name}" 20 " "): ${FUNCTION_DESCRIPTIONS[$function_name]}"
        done
    fi
}

callCommand() {
    if [[ ! -z "$1" ]] && [[ ! -z "${FUNCTION_ALIAS[$1]}" ]]; then
        FUNCTION_NAME=${FUNCTION_ALIAS[$1]}
    else
        FUNCTION_NAME=$1
    fi

    FUNCTION_COMMAND=$2

    if [[ "${FUNCTION_NAME}" == "help" ]]; then
        if [[ ! -z "${FUNCTION_COMMAND}" ]] && [[ ! -z "${FUNCTION_ALIAS[$FUNCTION_COMMAND]}" ]]; then
            showHelp $FUNCTION_COMMAND
        elif [[ ! -z "${FUNCTION_COMMAND}" ]] && [[ ! -z "${FUNCTIONS[$FUNCTION_COMMAND]}" ]]; then
            showHelp $FUNCTION_COMMAND
        else
            showHelp
        fi
    elif [[ -z "${FUNCTION_NAME}" ]]; then
        FUNCTION_NAME=${FUNCTIONS["__DEFAULT__"]}
        echo "No command specified, running default command: ${FUNCTION_NAME}"
        ${FUNCTIONS[$FUNCTION_NAME]} ${@:2}
    else
        ${FUNCTIONS[$FUNCTION_NAME]} ${@:2}
    fi
}

addCommand() {
    FUNCTION_NAME=$1
    FUNCTION_COMMAND=$2
    FUNCTION_DESCRIPTION=$3
    FUNCTION_USAGE=$4

    FUNCTIONS[$FUNCTION_NAME]=$FUNCTION_COMMAND

    if [[ ! -z "${FUNCTION_DESCRIPTION}" ]]; then
        FUNCTION_DESCRIPTIONS[$FUNCTION_NAME]=$FUNCTION_DESCRIPTION
    fi

    if [[ ! -z "${FUNCTION_USAGE}" ]]; then
        FUNCTION_USAGE[$FUNCTION_NAME]=$FUNCTION_USAGE
    fi
}

addAlias() {
    FUNCTION_ALIAS_NAME=$1
    FUNCTION_BASE_NAME=$2

    FUNCTION_ALIAS[$FUNCTION_ALIAS_NAME]=$FUNCTION_BASE_NAME
}
