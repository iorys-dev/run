#!/bin/bash

declare -A SOURCES=(
  ["functions"]="vendor/iorys/run/bin/functions.sh"
  #  ["laravel_functions"]="vendor/iorys/run/bin/laravel_functions.sh"
)

if [[ ! -d vendor/iorys/run/bin ]]; then
  docker-compose run --rm php composer update iorys/run
fi

for key in "${!SOURCES[@]}"; do
  # shellcheck disable=SC1090
  source "${SOURCES[$key]}"
done

appInstall() {
  writeInfo "Create .env"
  createEnvFile

  writeInfo 'Bringing up docker-compose services'
  bringUpServices

  writeInfo 'Setting permissions'
  setupPermissions

  writeInfo 'Composer install'
  composerInstall

  writeInfo "Application install successful"
  printServicesInfo
}

# Just for demonstration purposes. Delete this when setting run script up.
# Typically its enough with provided one which executes docker-compose up -d --remove-orphans.
# If you are ok with that, you can remove this function from your 'run' file.
bringUpServices() {
  :
}

# Example of how to create .env file from .env.example or use .env.local if available.
createEnvFile() {
  # [ -e ".env.local" ] && (echo "Using .env.local" && cp .env.local .env) || (echo "Using .env.example" && cp .env.example .env)
  :
}

# Fill with your custom commands to set permissions.
setupPermissions() {
  :
}

getServicesIpsAndPorts() {
  HOST_IP=$(getHostIp)
  # APP_HOST=$(getServiceIp nginx)
  # APP_PORT=$(getServicePort nginx 80)
  APP_HOST="MOCKED_HOST"
  APP_PORT="MOCKED_PORT"
  echo "Mock of getServicesIpsAndPorts ${HOST_IP}" >/dev/null
}

printServicesInfo() {
  getServicesIpsAndPorts
  printServiceInfo "APP" "${APP_HOST}" "${APP_PORT}" "80"
  printServiceInfo "Mock Service" "MOCK_HOST1" "MOCK_PORT1" "MOCK_PORT2"
}

# Just for demonstration purposes. Delete this when setting run script up.
composerInstall() {
  :
}

######### CUSTOM COMMANDS ########
##################################

callCommand "$@"
