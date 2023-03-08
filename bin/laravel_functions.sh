#!/bin/bash

artisan() {
    writeInfo "Run php artisan" "$@"
    docker-compose run php php artisan "$@"
}

addCommand "artisan" "artisan" "Run custom artisan command." "[command]"
addAlias "lara" "artisan"
