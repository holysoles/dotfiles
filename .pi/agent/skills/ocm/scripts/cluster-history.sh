#!/usr/bin/env bash
set -euo pipefail

id=${1:?usage: check-cluster-history.sh <ocm-cluster-id>}

subscription=$(
  ocm get /api/accounts_mgmt/v1/subscriptions \
    -p "search=cluster_id='$id'" |
    jq -e '.items[0]'
)

ocm get "/api/clusters_mgmt/v1/clusters/$id" >/dev/null 2>&1 &&
  active=true || active=false

jq -n --argjson subscription "$subscription" --argjson active "$active" '
  $subscription | {
    existed: true,
    currently_in_ocm: $active,
    name: .display_name,
    cluster_id,
    external_cluster_id,
    status,
    created_at,
    deprovisioned_at_estimate: (
      if .status == "Deprovisioned" then .updated_at else null end
    ),
    region: .region_id,
    cloud_account_id,
    organization_id,
    subscription_id: .id
  }'
