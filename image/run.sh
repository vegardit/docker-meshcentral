#!/usr/bin/env bash
#
# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral
#

set -eu

##############################
# execute script with bash if loaded with other shell interpreter
##############################
if [ -z "${BASH_VERSINFO:-}" ]; then /usr/bin/env bash "$0" "$@"; exit; fi

set -o pipefail

trap 'status=$?; echo >&2 "$(date +%H:%M:%S) Error - exited with status $status at line $LINENO:"; pr -tn $0 | tail -n+$((LINENO - 3)) | head -n7' ERR

if [ "${DEBUG_RUN_SH:-}" == "1" ]; then
   set -x
fi

cat <<'EOF'
                  _       ___           _             _
  /\/\   ___  ___| |__   / __\___ _ __ | |_ _ __ __ _| |
 /    \ / _ \/ __| '_ \ / /  / _ \ '_ \| __| '__/ _` | |
/ /\/\ \  __/\__ \ | | / /__|  __/ | | | |_| | | (_| | |
\/    \/\___||___/_| |_\____/\___|_| |_|\__|_|  \__,_|_|
EOF

cat /opt/build_info
echo

function log() {
   if [ -p /dev/stdin ]; then
      while read line; do
          echo "[$(date "+%Y-%m-%d %H:%M:%S") ${BASH_SOURCE}:${BASH_LINENO}] $line"
      done
   else
      echo "[$(date "+%Y-%m-%d %H:%M:%S") ${BASH_SOURCE}:${BASH_LINENO}] ${@}"
   fi
}

if [ -f "$INIT_SH_FILE" ]; then
   log "Loading [$INIT_SH_FILE]..."
   source "$INIT_SH_FILE"
fi

if [[ -n $CONFIG_TEMPLATE_FILE ]]; then

   if [[ ! -e $CONFIG_TEMPLATE_FILE ]]; then
      log "ERROR: Specified config.json template file [$CONFIG_TEMPLATE_FILE] does not exist."
   fi

   function interpolate_vars() {
      # based on https://stackoverflow.com/a/40167919
      local line lineEscaped
      while IFS= read -r line || [ -n "$line" ]; do  # the `||` clause ensures that the last line is read even if it doesn't end with \n
         # escape all chars that could trigger an expansion
         IFS= read -r lineEscaped < <(echo "$line" | tr '`([$' '\1\2\3\4')
         # selectively re-enable ${ references
         lineEscaped=${lineEscaped//$'\4'{/\${}
         # escape back slashes to preserve them
         lineEscaped=${lineEscaped//\\/\\\\}
         # escape embedded double quotes to preserve them
         lineEscaped=${lineEscaped//\"/\\\"}
         eval "printf '%s\n' \"$lineEscaped\"" | tr '\1\2\3\4' '`([$'
      done
   }

   log "Generating config.js based on template [$CONFIG_TEMPLATE_FILE]..."
   if interpolated=$(interpolate_vars < $CONFIG_TEMPLATE_FILE); then
      echo "$interpolated" > meshcentral-data/config.json
   else
      exit $?
   fi
fi

if [[ -n $OSSLSIGNCODE_OPTS ]]; then
  for exe in $(find ./node_modules/meshcentral/agents/ -name *-signed.exe); do
    log "Signing Windows binary [${exe/-signed/}]..."
    eval "osslsigncode sign $OSSLSIGNCODE_OPTS -in ${exe/-signed/} -out $exe"
  done
fi

export NODE_ENV="production"

exec node ./node_modules/meshcentral/meshcentral.js