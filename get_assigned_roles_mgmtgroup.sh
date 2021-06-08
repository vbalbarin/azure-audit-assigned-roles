#! /env/bin/bash

function timestamp() {
  printf "%s" "$(date -u +'%Y-%d-%mT%H:%M:%SZ')"
}


function acct_mg_cache() {
  local cache_dir="$1"

  [[ ! -d "${cache_dir}" ]] && mkdir -p "${cache_dir}"
  az account management-group list > "${cache_dir}/management_groups.json"
  az_management_groups=($( jq -r '.[] | .name' "${cache_dir}/management_groups.json"  ))
  for mg in ${az_management_groups[@]};do
    az account management-group show \
      --name "${mg}" \
      --expand \
      --query "{id: id, name: name, children: children[?type=='/subscriptions']}" > "${cache_dir}/subscriptions_${mg}.json"
  done
  az_management_group_ids=($( jq -r ".[] | .id" "${cache_dir}/management_groups.json"  ))
  # Role assignments
  for i in ${az_management_group_ids[@]}; do
    mg_name=$(echo "${i}" | cut -d '/' -f 5)
    az role assignment list  --scope "${i}" > "${cache_dir}/assignments_${mg_name}.json"
  done
  assignment_files=($( find "$(pwd)" -type f -name "assignments_*.json" ))
  az_ad_groups=($( jq -r '[ .[] | select(.principalType=="Group") | .principalName ] | unique | .[]' "${assignment_files[@]}" ))
  for g in ${az_ad_groups[@]}; do
    az ad group member list -g "${g}" --query '[].{userPrincipalName: userPrincipalName}' | jq -r '[ .[] | .userPrincipalName ]' > "${cache_dir}/ad_group_${g}.json"
  done
  printf '%s' "${cache_dir}"
}


function acct_mg_parent {
  local subscription_name="$1"
  local ret=''
  mgs=($(find . -type f -name "mgmt_subs_*.json" -exec basename {} \;))
  for mg in ${mgs[@]}; do
    s=$(jq -r ".children | .[] | select(.displayName==\"${subscription_name}\") | .displayName" "${mg}")

    if [[ "${s}" != '' ]]; then
      ret=$(jq -r ".name" "${mg}")
      break
    fi
  done
  printf "%s" ${ret}

}


IFS=$'\n'
set -f

now=$(date +%s)
max_cache_age=1800 #s or 30min
# max_cache_age=120 #s or 2min

az_subscription_json=$(az account show --query "{name: name, id:id, tenantId: tenantId}")
az_subscription=$(echo ${az_subscription_json} | jq -r '.name')


account_cache_name="account-cache-*"
account_caches=($(find . -type dir -name "${account_cache_name}"  -exec basename {} \;))
new_cache="$(pwd)/account-cache-${now}"

if [[ $(( ${#account_caches[@]} )) -ne 1 ]]; then
  printf "No valid cache found.\n"
  find . -type d -name "${account_cache_name}" -exec rm -Rf "{}" \;
  # mkdir -p "${new_cache}"
  cache=$(acct_mg_cache "${new_cache}")
else
  printf "Found cache: %s\n" "${account_caches[0]}"
  crt=$( echo ${account_caches[0]%%.*} | cut -d '-' -f 3)
  age=$(( ${now} - ${crt} ))
  if [[ ${age} -gt ${max_cache_age} ]]; then
    printf 'Cache created %d minutes ago. Recreating expired cache...\n' $(( ${age}/60 ))
    rm -Rf "${account_caches[0]}"
    cache=$(acct_mg_cache "${new_cache}")
  else
    printf "Cache created %d m ago. Valid.\n" $(( ${age}/60 ))
    cache="$(pwd)/${account_caches[0]}"
  fi
fi

printf "Cache: %s\n" "${cache}"

az_management_group_ids=($( jq -r ".[] | .id" "${cache}/management_groups.json"  ))

printf -- "%3s" | tr " " "-"; printf '\n'

for i in ${az_management_group_ids[@]}; do
mg_name=$(echo "${i}" | cut -d '/' -f 5)
mg_assignments_file="${cache}/assignments_${mg_name}.json"
printf -- "-\n"
printf -- "  timestamp: %s\n" $(timestamp)
printf -- "  id: %s\n" ${i}
printf -- "  tenant: %s\n" "$(echo ${az_subscription_json} | jq -r '.tenantId')"
printf -- "  assignments:\n"

az_assigned_rolenames=($(jq -r '[ .[] | .roleDefinitionName ] | unique | .[]' "${mg_assignments_file}"))
for r in "${az_assigned_rolenames[@]}"; do
  printf -v q '[ .[] | select(.roleDefinitionName=="%s") ]' "${r}"
  f="${r/\//-}" # substitute - for /
  f="${cache}/role_${mg_name}_${f}.json"
  jq "${q}" "${mg_assignments_file}" > "${f}"
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

done

printf -- "%3s" | tr " " "."; printf '\n'

set +f
unset IFS
