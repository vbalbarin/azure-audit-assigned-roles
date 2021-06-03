#! /env/bin/bash

now=$(date +%s)

function timestamp() {
  printf "%s" "$(date -u +'%Y-%d-%mT%H:%M:%SZ')"
}

function acct_mg_cache() {
  local cache="$1"
  az account management-group list > "${cache}"
  az_management_groups=($( jq -r '.[] | .name' "${cache}"  ))
  for mg in ${az_management_groups[@]};do
    #az account management-group show --name "${mg}" --expand --query "[].{displayName: displayName, children: children[?type=='/subscriptions']}" > mgmt_subs_${mg}-${now}.json
    az account management-group show --name "${mg}" --expand --query "{id: id, name: name, children: children[?type=='/subscriptions']}" > mgmt_subs_${mg}-${now}.json
  done
  # fn=$(find . -type f -name "mgmt_groups-*.json" -exec basename {} \;)
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

mgmt_files=($(find . -type f -name "mgmt_groups-*.json" -exec basename {} \;))

if [[ $(( ${#mgmt_files[@]} )) -ne 1 ]]; then
  find . -type f -name "mgmt_*.json" -exec rm -f "{}" \;
  mgmt_file=$(acct_mg_cache "mgmt_groups-${now}.json")
else
  crt=$( echo ${mgmt_files[0]%%.*} | cut -d '-' -f 2)
  age=$(( ${now} - ${crt} ))
  printf 'Cache created %d minutes ago.\n' $(( ${age}/60 ))
  if [[ ${age} -gt 1800 ]]; then
    printf 'Cache created %d minutes ago. Recreating...\n' $(( ${age}/60 ))
    find . -type f -name "mgmt_*.json" -exec rm -f "{}" \;
    mgmt_file=$(acct_mg_cache "mgmt_groups-${now}.json")
  else
    mgmt_file=${mgmt_files[0]}
  fi
fi

# echo $(acct_mg_parent "${az_subscription}")
# mgmt_file=$(find . -type f -name "mgmt_groups-*.json" -exec basename {} \;)
az_management_group_ids=($( jq -r ".[] | .id" "${mgmt_file}"  ))

printf -- "%3s" | tr " " "-"; printf '\n'

for i in ${az_management_group_ids[@]}; do
az role assignment list  --scope "${i}"> mgmt_assignments-.json
printf -- "-\n"
printf -- "  timestamp: %s\n" $(timestamp)
printf -- "  id: %s\n" ${i}
printf -- "  tenant: %s\n" "$(echo ${az_subscription_json} | jq -r '.tenantId')"
#printf -- "  assignments:\n"
done

set +f
unset IFS


