#!/bin/bash
set -e

TERMINAL_WIDTH=$(tput cols)

pad() {
  s=$1
  len=$2
  char=${3:- }
  printf '%s%*s' "$s" $((len - ${#s})) '' | sed "s/ /${char}/g"
}

writeInfo() {
  TEXT=$1
  STRLEN=${#TEXT}
  MAXLEN=${TERMINAL_WIDTH}
  BORDERLEN=$(($MAXLEN - 2))
  LINELEN=$(($MAXLEN - $STRLEN - 3))
  COLOR_OFF='\033[0m'
  BCYAN='\033[1;36m'

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
  IP_MATCH='^(192\.168\.)|(([0-9]+\.){3}[0-9]+)'

  if command -v ipconfig.exe &> /dev/null; then
    HOST_IP=$(ipconfig.exe | grep -Eo "${IP_MATCH}" | awk '{if ($0 ~ /^192\.168\./) print $0; else a[++i]=$0} END {for (j=1;j<=i;j++) print a[j]}' | head -n1)
  else
    HOST_IP=$(ifconfig | grep -Eo "${IP_MATCH}" | awk '{if ($0 ~ /^192\.168\./) print $0; else a[++i]=$0} END {for (j=1;j<=i;j++) print a[j]}' | head -n1)
  fi

  echo "$HOST_IP"
}

getServiceIp() {
  SERVICE_NAME=$1
  SERVICE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker-compose ps -q "${SERVICE_NAME}")" | sed -n '1p')
  echo "$SERVICE_IP"
}

getServicePort() {
  SERVICE_NAME=$1
  SERVICE_INTERNAL_PORT=$2
  SERVICE_PORT=$(docker-compose port "${SERVICE_NAME}" "${SERVICE_INTERNAL_PORT}" | sed 's/.*://')
  echo "$SERVICE_PORT"
}

printServiceInfo() {
  SERVICE_SHORT_NAME=$1
  SERVICE_CONTAINER_IP=$2
  SERVICE_MATCHED_PORT=$3
  SERVICE_DEFAULT_PORT=$4

  if [ $# -lt 5 ]; then
    PREFIX='http://'
  else
    PREFIX="${5}"
  fi

  echo "$(pad "${SERVICE_SHORT_NAME^} Container IP" 40 " "): ${PREFIX}${SERVICE_CONTAINER_IP}:${SERVICE_DEFAULT_PORT}"
  echo "$(pad "${SERVICE_SHORT_NAME^} Shared IP   " 40 " "): ${PREFIX}${HOST_IP}:${SERVICE_MATCHED_PORT}"
  echo "$(pad "${SERVICE_SHORT_NAME^} Docker Host " 40 " "): ${PREFIX}host.docker.internal:${SERVICE_MATCHED_PORT}"
  # shellcheck disable=SC2005
  echo "$(pad "" "${TERMINAL_WIDTH}" "-")"
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

  echo "Application shutdown successful"
}

curlCheck() {
  echo "Run curl" "$@"
  docker-compose exec -T php curl -s --max-time 5 --request GET "${@}" >/dev/null && echo "OK" || echo "NO"
}

dockerExecute() {
  echo "Executing docker compose exec" "${@}"
  docker-compose exec "${@}"
}

bringUpServices() {
  docker-compose up -d --remove-orphans
}

declare -A FUNCTIONS=(
  ["app:install"]="appInstall"
  ["composer:install"]="composerInstall"
  ["composer:update"]="composerUpdate"
  ["down"]="appShutdown"
  ["exec"]="dockerExecute"
  ["isup"]="curlCheck"
  ["help"]="help"
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
  ["exec"]="<serviceName> <command>"
)

# Map the function aliases to their base functions
declare -A FUNCTION_ALIAS=()

# Define the help function
showHelp() {
  FUNCTION_NAME=$1
  if [[ -n "$FUNCTION_NAME" ]] && [[ -n "${FUNCTION_ALIAS[$FUNCTION_NAME]}" ]]; then
    FUNCTION_REAL_NAME=${FUNCTION_ALIAS[$FUNCTION_NAME]}
  fi

  if [[ -n "$FUNCTION_NAME" ]] && [[ -n "${FUNCTIONS[$FUNCTION_NAME]}" ]]; then
    if [[ "${FUNCTION_USAGE[$FUNCTION_NAME]}" ]]; then
      echo "Usage: ./run $FUNCTION_NAME ${FUNCTION_USAGE[$FUNCTION_NAME]}"
    else
      echo "Usage: ./run $FUNCTION_NAME"
    fi
    echo "${FUNCTION_DESCRIPTIONS[$FUNCTION_NAME]}"
  elif [[ -n "$FUNCTION_REAL_NAME" ]] && [[ -n "${FUNCTIONS[$FUNCTION_REAL_NAME]}" ]]; then
    if [[ "${FUNCTION_USAGE[$FUNCTION_REAL_NAME]}" ]]; then
      echo "Usage: ./run $FUNCTION_NAME ${FUNCTION_USAGE[$FUNCTION_REAL_NAME]}"
    else
      echo "Usage: ./run $FUNCTION_NAME"
    fi
    echo "${FUNCTION_DESCRIPTIONS[$FUNCTION_REAL_NAME]}"
  else
    echo "Usage: ./run help [function_name]"
    echo "Available functions:"

    # Sort the keys
    IFS=$'\n' sorted_keys=($(sort <<<"${!FUNCTIONS[*]}"))
    unset IFS

    for function_name in "${sorted_keys[@]}"; do
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
  if [[ -n "$1" ]] && [[ -n "${FUNCTION_ALIAS[$1]}" ]]; then
    FUNCTION_NAME=${FUNCTION_ALIAS[$1]}
  else
    FUNCTION_NAME=$1
  fi

  FUNCTION_COMMAND=$2

  if [[ "${FUNCTION_NAME}" == "help" ]]; then
    if [[ -n "${FUNCTION_COMMAND}" ]] && [[ -n "${FUNCTION_ALIAS[$FUNCTION_COMMAND]}" ]]; then
      showHelp $FUNCTION_COMMAND
    elif [[ -n "${FUNCTION_COMMAND}" ]] && [[ -n "${FUNCTIONS[$FUNCTION_COMMAND]}" ]]; then
      showHelp $FUNCTION_COMMAND
    else
      showHelp
    fi
  elif [[ -z "${FUNCTION_NAME}" ]]; then
    FUNCTION_NAME=${FUNCTIONS["__DEFAULT__"]}
    echo "No command specified, running default command: ${FUNCTION_NAME}"
    ${FUNCTIONS[$FUNCTION_NAME]} "${@:2}"
  else
    ${FUNCTIONS[$FUNCTION_NAME]} "${@:2}"
  fi
}

addCommand() {
  FUNCTION_NAME=$1
  FUNCTION_COMMAND=$2
  FUNCTION_DESCRIPTION=$3
  FUNCTION_USAGE=$4

  FUNCTIONS[$FUNCTION_NAME]=$FUNCTION_COMMAND

  if [[ -n "${FUNCTION_DESCRIPTION}" ]]; then
    FUNCTION_DESCRIPTIONS[$FUNCTION_NAME]=$FUNCTION_DESCRIPTION
  fi

  if [[ -n "${FUNCTION_USAGE}" ]]; then
    FUNCTION_USAGE[$FUNCTION_NAME]=$FUNCTION_USAGE
  fi
}

addAlias() {
  FUNCTION_ALIAS_NAME=$1
  FUNCTION_BASE_NAME=$2

  FUNCTION_ALIAS[$FUNCTION_ALIAS_NAME]=$FUNCTION_BASE_NAME
}

addCommand "__DEFAULT__" "app:install"
addAlias "composerInstall" "composer:install"
addAlias "composer-install" "composer:install"
addAlias "composerUpdate" "composer:update"
addAlias "composer-update" "composer:update"
