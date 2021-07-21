#!/usr/bin/env bash

function timestamp() {
  printf "%s" "$(date -u +'%Y-%d-%mT%H:%M:%SZ')"
}


function acct_sub_cache() {
  local cache_dir="$1"

  [[ ! -d "${cache_dir}" ]] && mkdir -p "${cache_dir}"
  # Role assignments
  az role assignment list  > "${cache_dir}/assignments_subscription.json"
  assignment_files=($( find "$(pwd)" -type f -name "assignments_*.json" ))
  az_ad_groups=($( jq -r '[ .[] | select(.principalType=="Group") | .principalName ] | unique | .[]' "${assignment_files[@]}" ))
  for g in ${az_ad_groups[@]}; do
    az ad group member list -g "${g}" --query '[].{userPrincipalName: userPrincipalName}' | jq -r '[ .[] | .userPrincipalName ]' > "${cache_dir}/ad_group_${g}.json"
  done
  printf '%s' "${cache_dir}"
}


IFS=$'\n'
set -f

az_subscription_json=$(az account show --query "{name: name, id:id, tenantId: tenantId}")
subscription_name="$( echo ${az_subscription_json} | jq -r '.name')"

now=$(date +%s)
max_cache_age=1800 #s or 30min
# max_cache_age=120 #s or 2min

cache_dir="subscription-${subscription_name}-cache-*"
caches=($(find . -type d -name "${cache_dir}"  -exec basename {} \;))
new_cache_dir="$(pwd)/subscription-${subscription_name}-cache-${now}"

if [[ $(( ${#caches[@]} )) -ne 1 ]]; then
  printf "No valid cache found.\n"
  find . -type d -name "${cache_dir}" -exec rm -Rf "{}" \;
  # mkdir -p "${new_cache_dir}"
  cache=$(acct_sub_cache "${new_cache_dir}")
else
  printf "Found cache: %s\n" "${caches[0]}"
  crt=$( echo ${caches[0]%%.*} | cut -d '-' -f 3)
  age=$(( ${now} - ${crt} ))
  if [[ ${age} -gt ${max_cache_age} ]]; then
    printf 'Cache created %d minutes ago. Recreating expired cache...\n' $(( ${age}/60 ))
    rm -Rf "${caches[0]}"
    cache=$(acct_sub_cache "${new_cache_dir}")
  else
    printf "Cache created %d m ago. Valid.\n" $(( ${age}/60 ))
    cache="$(pwd)/${caches[0]}"
  fi
fi
printf "Cache: %s\n" "${cache}"


# explanation:
#   (iterate over nodes | select roleDefinitionName property value); transform to a list | filter unique elements in list | transform list to indidual
#  elements

az_assigned_rolenames=($(jq -r '[ .[] | .roleDefinitionName ] | unique | .[]' "${cache}/assignments_subscription.json"))
az_ad_sps=($(jq -r '.[] | select(.principalType=="ServicePrincipal") | .principalName' "${cache}/assignments_subscription.json"))
az_ad_users=($(jq -r '.[] | select(.principalType=="User") | .principalName' "${cache}/assignments_subscription.json"))
az_ad_group=($(jq -r '.[] | select(.principalType=="Group") | .principalName' "${cache}/assignments_subscription.json"))

printf "%3s" | tr " " "-"; printf '\n'
printf -- "-\n"
printf -- "  timestamp: %s\n" $(timestamp)
printf -- "  subscription: %s\n" "$(echo ${az_subscription_json} | jq -r '.name')"
printf -- "  id: %s\n" "$(echo ${az_subscription_json} | jq -r '.id')"
printf -- "  tenant: %s\n" "$(echo ${az_subscription_json} | jq -r '.tenantId')"
printf -- "  assignments:\n"

for r in "${az_assigned_rolenames[@]}"; do
  printf -v q '[ .[] | select(.roleDefinitionName=="%s") ]' "${r}"
  f="${r/\//-}" # substitute - for /
  f="${cache}/role_${subscription_name}_${f}.json"
  jq "${q}" "${cache}/assignments_subscription.json" > "${f}"
  az_ad_users=($(jq -r '.[] | select(.principalType=="User") | .principalName' "${f}"))
  az_ad_sps=($(jq -r '.[] | select(.principalType=="ServicePrincipal") | .principalName' "${f}"))
  az_ad_groups=($(jq -r '.[] | select(.principalType=="Group") | .principalName' "${f}"))

  printf -- "  -\n"
  printf -- "    role: %s\n" ${r}
  printf -- "    users:"
  if [[ ${#az_ad_users[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for u in ${az_ad_users[@]}; do
  printf -- "    - %s\n" ${u}
  done
  fi
  printf -- "    service_principals:"
  if [[ ${#az_ad_sps[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for s in ${az_ad_sps[@]}; do
  printf -- "    - %s\n" ${s}
  done
  fi
  printf -- "    groups:"
  if [[ ${#az_ad_groups[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for g in ${az_ad_groups[@]}; do
  printf -- "    -\n"
  printf -- "      %s:" ${g}
  #members=($(az ad group member list -g "${g}" --query '[].{userPrincipalName: userPrincipalName}' | jq -r '.[] | .userPrincipalName'))
  members=($( jq -r ".[]" "${cache}/ad_group_${g}.json" ))
  if [[ ${#members[@]} = 0 ]]; then
  printf -- " []\n"
  else
  printf -- "\n"
  for m in ${members[@]}; do
  printf -- "      - %s\n" "${m}"
  done
  fi
  done
  fi
  # printf -- "\n"

done

printf "%3s" | tr " " "."; printf '\n'

set +f
unset IFS