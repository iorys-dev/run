#!/bin/bash

source vendor/iorys/run/bin/functions.sh
#source vendor/iorys/run/bin/laravel_functions.sh

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

bringUpServices() {
#    docker-compose up -d --remove-orphans
  echo "Mock of bringUpServices"
}

createEnvFile() {
#    [ -e ".env.local" ] && (echo "Using .env.local" && cp .env.local .env) || (echo "Using .env.example" && cp .env.example .env)
  echo "Mock of createEnvFile"
}

setupPermissions() {
  echo "Mock of setupPermissions"
}

getServicesIpsAndPorts() {
    HOST_IP=$(getHostIp)
#    APP_HOST=$(getServiceIp nginx)
#    APP_PORT=$(getServicePort nginx 80)
    APP_HOST="MOCKED_HOST"
    APP_PORT="MOCKED_PORT"
  echo "Mock of getServicesIpsAndPorts"
}

printServicesInfo() {
    getServicesIpsAndPorts
#    printServiceInfo "APP" "${APP_HOST}" "${APP_PORT}" "80"
    printServiceInfo "APP" "${APP_HOST}" "${APP_PORT}" "MOCKED_CONTAINER_PORT"
  echo "Mock of printServicesInfo"
}

composerInstall() {
  echo "Mock of composerInstall, just to imitate the original function. composerInstall function is already defined in vendor/iorys/run/bin/functions.sh"
}

######### CUSTOM COMMANDS ########
##################################

callCommand $@
