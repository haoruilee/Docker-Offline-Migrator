#!/bin/bash
sanitize() {
  echo "$1" | tr '/:.-' '____'
}
