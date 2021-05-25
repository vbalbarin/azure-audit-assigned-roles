#! /env/bin/bash

function timestamp() {
  printf "%s" "$(date -u +'%Y-%d-%mT%H:%M:%SZ')"
}

IFS=$'\n'
set -f

az_subscription_json=$(az account show --query "{name: name, id:id, tenantId: tenantId}")

az role assignment list  > assignments.json

# explanation:
#   (iterate over nodes | select roleDefinitionName property value); transform to a list | filter unique elements in list | transform list to indidual
#  elements

az_assigned_rolenames=($(jq -r '[ .[] | .roleDefinitionName ] | unique | .[]' assignments.json))

az_ad_sps=($(jq -r '.[] | select(.principalType=="ServicePrincipal") | .principalName' assignments.json))

az_ad_users=($(jq -r '.[] | select(.principalType=="User") | .principalName' assignments.json))

az_ad_group=($(jq -r '.[] | select(.principalType=="Group") | .principalName' assignments.json))

printf "%3s" | tr " " "-"; printf '\n'
printf -- "- timestamp: %s\n\n" $(timestamp)
printf -- "  subscription: %s\n" "$(echo ${az_subscription_json} | jq -r '.name')"
printf -- "  id: %s\n" "$(echo ${az_subscription_json} | jq -r '.id')"
printf -- "  tenant: %s\n\n" "$(echo ${az_subscription_json} | jq -r '.tenantId')"
printf -- "  assignments:\n\n"

for r in "${az_assigned_rolenames[@]}"; do
  printf -v q '[ .[] | select(.roleDefinitionName=="%s") ]' "${r}"
  f="${r/\//-}" # substitute - for /
  jq "${q}" assignments.json > "${f}.json"
  az_ad_users=($(jq -r '.[] | select(.principalType=="User") | .principalName' "${f}.json"))
  az_ad_sps=($(jq -r '.[] | select(.principalType=="ServicePrincipal") | .principalName' "${f}.json"))
  az_ad_groups=($(jq -r '.[] | select(.principalType=="Group") | .principalName' "${f}.json"))

  printf -- "    - role: %s\n" ${r}
  printf -- "      users:"
  if [[ ${#az_ad_users[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for u in ${az_ad_users[@]}; do
  printf -- "      - %s\n" ${u}
  done
  fi
  printf -- "      service_principals:"
  if [[ ${#az_ad_sps[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for s in ${az_ad_sps[@]}; do
  printf -- "      - %s\n" ${s}
  done
  fi
  printf -- "      groups:"
  if [[ ${#az_ad_groups[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for g in ${az_ad_groups[@]}; do
  printf -- "      - %s:" ${g}
  # printf -- "        members:"
  members=($(az ad group member list -g "${g}" --query '[].{userPrincipalName: userPrincipalName}' | jq -r '.[] | .userPrincipalName'))
  if [[ ${#members[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for m in ${members[@]}; do
  printf -- "        - %s\n" "${m}"
  done
  fi
  done
  fi
  printf -- "\n"

done

set +f
unset IFS
