#!/usr/bin/env bash
#
# Copyright 2021 by Vegard IT GmbH, Germany, https://vegardit.com
# SPDX-License-Identifier: Apache-2.0
#
# Author: Sebastian Thomschke, Vegard IT GmbH
#
# https://github.com/vegardit/docker-meshcentral

source /opt/bash-init.sh

#################################################
# print header
#################################################
cat <<'EOF'
                  _       ___           _             _
  /\/\   ___  ___| |__   / __\___ _ __ | |_ _ __ __ _| |
 /    \ / _ \/ __| '_ \ / /  / _ \ '_ \| __| '__/ _` | |
/ /\/\ \  __/\__ \ | | / /__|  __/ | | | |_| | | (_| | |
\/    \/\___||___/_| |_\____/\___|_| |_|\__|_|  \__,_|_|

EOF

cat /opt/build_info
echo

log INFO "Timezone is $(date +"%Z %z")"


#################################################
# load custom init script if specified
#################################################
if [[ -f $INIT_SH_FILE ]]; then
   log INFO "Loading [$INIT_SH_FILE]..."
   source "$INIT_SH_FILE"
fi


if [[ -n $CONFIG_TEMPLATE_FILE ]]; then

   if [[ ! -e $CONFIG_TEMPLATE_FILE ]]; then
      log ERROR "Specified config.json template file [$CONFIG_TEMPLATE_FILE] does not exist."
   fi

   log INFO "Generating config.js based on template [$CONFIG_TEMPLATE_FILE]..."
   if interpolated=$(interpolate < $CONFIG_TEMPLATE_FILE); then
      echo "$interpolated" > meshcentral-data/config.json
   else
      exit $?
   fi
fi

if [[ -n $OSSLSIGNCODE_OPTS ]]; then
   for exe in $(find ./node_modules/meshcentral/agents/ -name *-signed.exe); do
      log INFO "Signing Windows binary [${exe/-signed/}] using osslsigncode..."
      eval "osslsigncode sign $OSSLSIGNCODE_OPTS -in ${exe/-signed/} -out $exe"
   done
fi

export NODE_ENV="production"

exec node ./node_modules/meshcentral/meshcentral.js
