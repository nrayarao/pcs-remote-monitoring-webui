#!/bin/bash
# Copyright (c) Microsoft. All rights reserved.

AUTH_SERVER_URL=""
RESOURCE_TYPE=""
AUTH_TOKEN=""

# Acquires auth token for authroizating against key vault.
_acquire_token() {
    __set_keyvault_auth_server

    local _value=$(curl -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=$PCS_AAD_APPID&resource=https%3A%2F%2Fvault.azure.net&client_secret=$PCS_AAD_APPSECRET&grant_type=client_credentials" $AUTH_SERVER_URL/oauth2/token)
    AUTH_TOKEN=$(__parse_json $_value "access_token")
}

# Fetch key vault secret.
_get_keyvault_secret() {

    # Get a new token each time you access key vault.
    _acquire_token

    if [ "$1" == "-" ]; then
        echo ""
    else
        _keyvault_secret_bundle=$(curl -H "Authorization: Bearer $AUTH_TOKEN" -L https://$PCS_KEYVAULT_NAME.vault.azure.net/secrets/$1/?api-version=7.0)
        _keyvault_secret_bundle="'$_keyvault_secret_bundle'"

        # return the secret value.
        echo $(__parse_json $_keyvault_secret_bundle "value")
    fi
}

# Gets keyvault auth server by examining response headers of unauthenticated request to key vault.
# The 401 redirect contains WWW-Authenticate header which has KV auth server and resource type.
__set_keyvault_auth_server() {

    # Bare (unauthenticated) request to get secret.
    key_vault_wo_auth_call=$(curl -i -L "https://$PCS_KEYVAULT_NAME.vault.azure.net/secrets/authEnabled/?api-version=7.0" | grep -Fi WWW-Authenticate)

    wo_auth_call_resp_header=${key_vault_wo_auth_call#*:}

    # Extract auth server (url) & resource from WWW-Authenticate header.
    IFS=',' read -ra PARAMS <<< "$wo_auth_call_resp_header"

    for (( i = 0; i < 2; ++i )); do
        if [ $i == 0 ]; then
            __extract_auth_server ${PARAMS[0]}
        else
            __extract_resource_type ${PARAMS[1]}
        fi
    done
}

############# Helper functions #############

#Removes Bearer authorization prefix to extract auth server url from 401 redirect of keyvault.
__extract_auth_server() {
    AUTH_SERVER_URL=$(__extract_value_from_double_quotes $2)
}

#Removes "resource" prefix to extract resource type from 401 redirect of keyvault.
__extract_resource_type() {
    RESOURCE_TYPE=$(__extract_value_from_double_quotes $1)
}

__extract_value_from_double_quotes() {
    local string=$1
    # Remove trailing and prefixed double quotes.
    local _value=${string#*'"'}
    _value=${_value%'"'}

    #return the value
    echo $_value
}

__parse_json() {
  local _value=`echo $1 | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w $2`;
  echo ${_value##*|};
}

############# Main function #############

set_app_id() {
  sed -i "s~appId.*~appId: '$PCS_AAD_APPID',~g" /app/webui-config.js
}

modify_webui_config() {

  if [ "$1" == "AUTH" ]; then
    sed -i "s/authEnabled.*/authEnabled: $2,/g" /app/webui-config.js
  fi

  if [ "$1" == "TENANT" ]; then
    sed -i "s/tenant.*/tenant: '$2',/g" /app/webui-config.js
  fi

  if [ "$1" == "INSTANCE_URL" ]; then
    if [ "$2" == "" ]; then
      sed -i "s~instance.*~instance: 'https\:\/\/login\.microsoftonline\.com\/'~g" /app/webui-config.js
    else
      sed -i "s~instance.*~instance: '$2'~g" /app/webui-config.js
    fi
  fi
}

set_env_vars() {

  # set app id in webui-config
  set_app_id

  # parse through all variables (Every odd variable is env var name & even variables are secret key names in Key vault).
  while test ${#} -gt 0
  do
      _key=$1
      _value=$(_get_keyvault_secret $2)

      # change webui config
      modify_webui_config $_key $_value

      shift
      shift
  done
}

main() {
  # For the script to fetch the secrets from key-vault foll. variables PCS_KEYVAULT_NAME,
  # PCS_AAD_APPID, PCS_AAD_APPSECRET must be available as "environment" variables.
  if [[ "$PCS_KEYVAULT_NAME" != "" ]] && [[ "$PCS_AAD_APPID" != "" ]] && [[ "$PCS_AAD_APPSECRET" != "" ]]; then
    set_env_vars $@
  fi
}

main $@
