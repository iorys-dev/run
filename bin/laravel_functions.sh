#!/bin/bash

artisan() {
  writeInfo "Run php artisan" "$@"
  docker-compose run --rm php php artisan "$@"
}

addCommand "artisan" "artisan" "Run custom artisan command." "[command]"
addAlias "lara" "artisan"
