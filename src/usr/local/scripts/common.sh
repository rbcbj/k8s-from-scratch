#!/usr/bin/env bash

if [[ ! -f "/etc/kubernetes/config.env" ]]; then
  echo ":: config file not found"
  exit 1
fi

export $(grep -v '^#' /etc/kubernetes/config.env | xargs -d '\n')