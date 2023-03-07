#!/bin/bash

artisan() {
    writeInfo "Run php artisan $@"
    # shellcheck disable=SC2086
    docker-compose run php php artisan $@
}

addCommand "artisan" "artisan" "Run custom artisan command." "[command]"
addAlias "lara" "artisan"
