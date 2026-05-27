#!/bin/sh
printf '\033c\033]0;%s\a' 2proj
base_path="$(dirname "$(realpath "$0")")"
"$base_path/2proj.x86_64" "$@"
