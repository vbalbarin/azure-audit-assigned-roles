#! /env/bin/bash

now=$(date +%s)
cache_dir="$(pwd)/cache"
[[ -not (-d ${cache_dir}) ]];; then mkdir -p "${cache_dir}"; fi


function timestamp() {
  printf "%s" "$(date -u +'%Y-%d-%mT%H:%M:%SZ')"
}

function acct_mg_cache() {
  local cache="$1"
  az account management-group list > "${cache}"
  az_management_groups=($( jq -r '.[] | .name' "${cache}"  ))
  for mg in ${az_management_groups[@]};do
    az account management-group show \
      --name "${mg}" \
      --expand \
      --query "{id: id, name: name, children: children[?type=='/subscriptions']}" > "acct_mg_subs_${mg}-${now}.json"
  done
  printf '%s' "${cache}"
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

az_subscription_json=$(az account show --query "{name: name, id:id, tenantId: tenantId}")
az_subscription=$(echo ${az_subscription_json} | jq -r '.name')

acct_mg_files=($(find . -type f -name "acct_mg_groups-*.json" -exec basename {} \;))

if [[ $(( ${#acct_mg_files[@]} )) -ne 1 ]]; then
  find . -type f -name "mgmt_*.json" -exec rm -f "{}" \;
  mgmt_file=$(acct_mg_cache "acct_mg_groups-${now}.json")
else
  crt=$( echo ${acct_mg_files[0]%%.*} | cut -d '-' -f 2)
  age=$(( ${now} - ${crt} ))
  printf 'Cache created %d minutes ago.\n' $(( ${age}/60 ))
  if [[ ${age} -gt 1800 ]]; then
    printf 'Cache created %d minutes ago. Recreating...\n' $(( ${age}/60 ))
    find . -type f -name "mgmt_*.json" -exec rm -f "{}" \;
    mgmt_file=$(acct_mg_cache "acct_mg_groups-${now}.json")
  else
    mgmt_file=${acct_mg_files[0]}
  fi
fi

# echo $(acct_mg_parent "${az_subscription}")
# acct_mg_file=$(find . -type f -name "acct_mg_groups-*.json" -exec basename {} \;)
az_management_group_ids=($( jq -r ".[] | .id" "${mgmt_file}"  ))

printf -- "%3s" | tr " " "-"; printf '\n'

for i in ${az_management_group_ids[@]}; do
mg_name=$(echo "${i}" | cut -d '/' -f 5)
mg_assignments_fn="acct_mg_assignments_${mg_name}-${now}.json"
az role assignment list  --scope "${i}"> "${mg_assignments_fn}"
printf -- "-\n"
printf -- "  timestamp: %s\n" $(timestamp)
printf -- "  id: %s\n" ${i}
printf -- "  tenant: %s\n" "$(echo ${az_subscription_json} | jq -r '.tenantId')"
printf -- "  assignments:\n"

az_assigned_rolenames=($(jq -r '[ .[] | .roleDefinitionName ] | unique | .[]' "${mg_assignments_fn}"))
for r in "${az_assigned_rolenames[@]}"; do
  printf -v q '[ .[] | select(.roleDefinitionName=="%s") ]' "${r}"
  f="${r/\//-}" # substitute - for /
  jq "${q}" "${mg_assignments_fn}" > "${f}.json"
  az_ad_users=($(jq -r '.[] | select(.principalType=="User") | .principalName' "${f}.json"))
  az_ad_sps=($(jq -r '.[] | select(.principalType=="ServicePrincipal") | .principalName' "${f}.json"))
  az_ad_groups=($(jq -r '.[] | select(.principalType=="Group") | .principalName' "${f}.json"))

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
  members=($(az ad group member list -g "${g}" --query '[].{userPrincipalName: userPrincipalName}' | jq -r '.[] | .userPrincipalName'))
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

set +f
unset IFS


