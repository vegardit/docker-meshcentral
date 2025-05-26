#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: © Vegard IT GmbH (https://vegardit.com)
# SPDX-FileContributor: Sebastian Thomschke
# SPDX-License-Identifier: Apache-2.0
# SPDX-ArtifactOfProjectHomePage: https://github.com/vegardit/docker-meshcentral

# shellcheck disable=SC1091  # Not following: /opt/bash-init.sh was not specified as input
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
if [[ -f ${INIT_SH_FILE:-} ]]; then
  log INFO "Loading [$INIT_SH_FILE]..."

  # shellcheck disable=SC1090  # ShellCheck can't follow non-constant source
  source "$INIT_SH_FILE"
fi


#################################################
# Generate config.js
#################################################
if [[ -n $CONFIG_TEMPLATE_FILE ]]; then

  if [[ ! -f $CONFIG_TEMPLATE_FILE ]]; then
    log ERROR "Specified config.json template file [$CONFIG_TEMPLATE_FILE] does not exist."
  fi

  log INFO "Generating config.js based on template [$CONFIG_TEMPLATE_FILE]..."
  if interpolated=$(interpolate <"$CONFIG_TEMPLATE_FILE"); then
    echo "$interpolated" >meshcentral-data/config.json
  else
    exit $?
  fi
fi


#################################################
# sign Windows agent executables
#################################################
if [[ -n $OSSLSIGNCODE_OPTS ]]; then
  find ./node_modules/meshcentral/agents/ -type f -name "*-.exe" ! -name "*-signed.exe" -print0 \
  | while IFS= read -r -d '' unsigned_exe; do
      signed_exe="${unsigned_exe%.exe}-signed.exe"

      log INFO "Signing Windows binary [$unsigned_exe] using osslsigncode..."
      eval "osslsigncode sign $OSSLSIGNCODE_OPTS -in '$unsigned_exe' -out '$signed_exe'"
    done
fi

export NODE_ENV="production"

exec node ./node_modules/meshcentral/meshcentral.js
