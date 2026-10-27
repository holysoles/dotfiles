#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: cleanup-cluster-aws-resources.sh <cluster-id|cluster-name|all> [--apply]

Find stale ROSA VPCs in the current AWS account, across opted-in regions.
Defaults to a dry-run. --apply prompts for the exact VPC count before deleting.
Requires aws, ocm, and jq; OCM must be authenticated to the matching environment.

Only dedicated, non-default VPCs identified by cluster tags/names are candidates.
Active OCM clusters and resources tagged for another OCM environment are skipped.
CloudFormation stacks are deleted only when they contain network resource types.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [[ ${1:-} == -h || ${1:-} == --help ]]; then usage; exit 0; fi
[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 2; }
target=$1
apply=false
if [[ ${2:-} == --apply ]]; then apply=true; elif [[ $# -eq 2 ]]; then usage >&2; exit 2; fi

for command in aws ocm jq; do command -v "$command" >/dev/null || fail "required command not found: $command"; done
account=$(aws sts get-caller-identity --query Account --output text)
ocm_url=$(ocm config get url)
ocm whoami >/dev/null || fail "OCM authentication failed for $ocm_url"
case "$ocm_url" in
  *api.stage.openshift.com*) current_env=staging ;;
  *api.integration.openshift.com*) current_env=integration ;;
  *api.openshift.com*) current_env=production ;;
  *) current_env=unknown ;;
esac

# Treat only OCM's explicit not-found response as stale; auth, network, and API errors abort.
cluster_is_active() {
  local ref=$1 output
  if output=$(ocm describe cluster --json "$ref" 2>&1); then return 0; fi
  if [[ $output == *"There are no subscriptions or clusters with identifier or name"* ]]; then return 1; fi
  fail "could not verify OCM cluster '$ref': $output"
}

candidate_matches() {
  local vpc_json=$1 groups_json=$2
  jq -e --arg target "$target" --argjson all "$([[ $target == all ]] && echo true || echo false)" --argjson groups "$groups_json" '
    def values($tags; $key): [$tags[]? | select(.Key == $key) | .Value];
    def has_cluster_tags($tags):
      (values($tags; "api.openshift.com/id") | length > 0) or
      (values($tags; "api.openshift.com/name") | length > 0) or
      (values($tags; "red-hat-clustertype") | any(. == "rosa")) or
      (values($tags; "service") | any(. == "ROSA")) or
      (values($tags; "cluster_name") | length > 0);
    . as $v | ($v.Tags // []) as $vt |
    [$groups.SecurityGroups[]? | select(.VpcId == $v.VpcId) | .Tags[]?] as $gt |
    if $all then has_cluster_tags($vt) or has_cluster_tags($gt)
    else
      ([values($vt; "api.openshift.com/id")[], values($vt; "api.openshift.com/name")[], values($vt; "cluster_name")[], values($vt; "Name")[], values($vt; "aws:cloudformation:stack-name")[],
        values($gt; "api.openshift.com/id")[], values($gt; "api.openshift.com/name")[], values($gt; "cluster_name")[], values($gt; "Name")[], values($gt; "Cluster")[]] |
        any(. == $target or startswith($target + "-"))) or
      ([$gt[] | select(.Key | startswith("kubernetes.io/cluster/")) | .Key | sub("^kubernetes.io/cluster/"; "")] | any(. == $target))
    end
  ' <<<"$vpc_json" >/dev/null
}

# shortcut: non-network stack resources are refused; add a resource-specific cleanup before widening this allowlist.
assert_network_stack() {
  local region=$1 stack_name=$2 resources bad
  resources=$(aws cloudformation list-stack-resources --region "$region" --stack-name "$stack_name" --output json)
  bad=$(jq -r '[.StackResourceSummaries[].ResourceType | select(. as $t | [
    "AWS::EC2::VPC","AWS::EC2::Subnet","AWS::EC2::RouteTable","AWS::EC2::Route",
    "AWS::EC2::SubnetRouteTableAssociation","AWS::EC2::VPCGatewayAttachment","AWS::EC2::InternetGateway",
    "AWS::EC2::SecurityGroup","AWS::EC2::SecurityGroupIngress","AWS::EC2::SecurityGroupEgress",
    "AWS::EC2::EIP","AWS::EC2::EIPAssociation","AWS::EC2::NatGateway","AWS::EC2::VPCEndpoint",
    "AWS::EC2::NetworkAcl","AWS::EC2::NetworkAclEntry","AWS::EC2::NetworkAclAssociation"
  ] | index($t) == null)] | unique | .[]' <<<"$resources")
  [[ -z $bad ]] || fail "stack $stack_name contains non-network resources; refusing deletion: $bad"
}

get_stack_status() {
  local region=$1 stack=$2 output
  if output=$(aws cloudformation describe-stacks --region "$region" --stack-name "$stack" --output json 2>&1); then
    jq -r '.Stacks[0].StackStatus // empty' <<<"$output"
  elif [[ $output == *"does not exist"* ]]; then
    printf ''
  else
    fail "could not inspect CloudFormation stack $region/$stack: $output"
  fi
}

candidate_file=$(mktemp)
trap 'rm -f "$candidate_file"' EXIT
regions=$(aws ec2 describe-regions --all-regions --query 'Regions[?OptInStatus==`opt-in-not-required` || OptInStatus==`opted-in`].RegionName' --output text)
for region in $regions; do
  vpcs=$(aws ec2 describe-vpcs --region "$region" --output json)
  while IFS= read -r vpc_json; do
    vpc_id=$(jq -r '.VpcId' <<<"$vpc_json")
    groups=$(aws ec2 describe-security-groups --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --output json)
    candidate_matches "$vpc_json" "$groups" || continue

    refs=$(jq -r --argjson groups "$groups" '
      . as $v | (($v.Tags // []) + [$groups.SecurityGroups[]? | select(.VpcId == $v.VpcId) | .Tags[]?]) |
      [.[] | select(.Key == "api.openshift.com/id" or .Key == "api.openshift.com/name" or .Key == "cluster_name") | .Value] | unique[]
    ' <<<"$vpc_json")
    envs=$(jq -r --argjson groups "$groups" '
      . as $v | (($v.Tags // []) + [$groups.SecurityGroups[]? | select(.VpcId == $v.VpcId) | .Tags[]?]) |
      [.[] | select(.Key == "api.openshift.com/environment") | .Value] | unique[]
    ' <<<"$vpc_json")
    if [[ -n $envs ]] && grep -Fxqv "$current_env" <<<"$envs"; then
      printf 'Skipping %s/%s: OCM environment tag does not match current environment (%s).\n' "$region" "$vpc_id" "$current_env" >&2
      continue
    fi

    if [[ -z $refs ]]; then
      [[ $target != all ]] || { printf 'Skipping %s/%s: no cluster identity tag to verify with OCM.\n' "$region" "$vpc_id" >&2; continue; }
      refs=$target
    fi
    active=false
    while IFS= read -r ref; do
      [[ -n $ref ]] || continue
      if cluster_is_active "$ref"; then
        active=true
        printf 'Skipping %s/%s: OCM cluster %s still exists.\n' "$region" "$vpc_id" "$ref" >&2
        break
      fi
    done <<<"$refs"
    [[ $active == false ]] || continue

    name=$(jq -r '[.Tags[]? | select(.Key == "Name") | .Value][0] // "-"' <<<"$vpc_json")
    stack=$(jq -r '[.Tags[]? | select(.Key == "aws:cloudformation:stack-name") | .Value][0] // "-"' <<<"$vpc_json")
    printf '%s\t%s\t%s\t%s\n' "$region" "$vpc_id" "$name" "$stack" >>"$candidate_file"
  done < <(jq -c '.Vpcs[] | select(.IsDefault == false)' <<<"$vpcs")
done

count=$(wc -l <"$candidate_file" | tr -d ' ')
printf 'AWS account: %s\nOCM environment: %s (%s)\n' "$account" "$current_env" "$ocm_url"
if [[ $count -eq 0 ]]; then echo 'No stale matching VPCs found.'; exit 0; fi
printf '\nCandidates (region, VPC, Name, CloudFormation stack):\n'
while IFS=$'\t' read -r region vpc name stack; do printf '  %s  %s  %s  stack=%s\n' "$region" "$vpc" "$name" "$stack"; done <"$candidate_file"
if [[ $apply == false ]]; then
  printf '\nDry-run only. Re-run with --apply to delete these VPCs and their network dependencies.\n'
  exit 0
fi
# Preflight every candidate before the first mutation.
while IFS=$'\t' read -r region vpc_id _ stack; do
  instances=$(aws ec2 describe-instances --region "$region" --filters "Name=vpc-id,Values=$vpc_id" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])' --output text)
  [[ $instances == 0 ]] || fail "$region/$vpc_id has EC2 instances; refusing cleanup"
  peer_count=$(aws ec2 describe-vpc-peering-connections --region "$region" --query "length(VpcPeeringConnections[?RequesterVpcInfo.VpcId=='$vpc_id' || AccepterVpcInfo.VpcId=='$vpc_id'])" --output text)
  tgw_count=$(aws ec2 describe-transit-gateway-vpc-attachments --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'length(TransitGatewayVpcAttachments)' --output text)
  vpn_count=$(aws ec2 describe-vpn-gateways --region "$region" --query "length(VpnGateways[?VpcAttachments[?VpcId=='$vpc_id']])" --output text)
  [[ $peer_count == 0 && $tgw_count == 0 && $vpn_count == 0 ]] || fail "$region/$vpc_id has peering or gateway attachments; refusing cleanup"
  enis=$(aws ec2 describe-network-interfaces --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --output json)
  unknown_enis=$(jq -r '[.NetworkInterfaces[] | select((.Description // "") | test("VPC Endpoint Interface|Interface for NAT Gateway|ClientVPN Endpoint resource") | not) | .NetworkInterfaceId] | .[]' <<<"$enis")
  [[ -z $unknown_enis ]] || fail "$region/$vpc_id has unmanaged network interfaces; refusing cleanup: $unknown_enis"
  if [[ $stack != - ]]; then
    stack_status=$(get_stack_status "$region" "$stack")
    if [[ -n $stack_status && $stack_status != DELETE_COMPLETE ]]; then
      [[ $stack_status != *IN_PROGRESS ]] || [[ $stack_status == DELETE_IN_PROGRESS ]] || fail "$region/$stack is $stack_status; wait for it to settle and retry"
      [[ $stack_status == DELETE_IN_PROGRESS ]] || assert_network_stack "$region" "$stack"
    fi
  fi
done <"$candidate_file"

confirmation="DELETE $count VPCS IN $account"
printf '\nThis removes the listed VPCs, attached Client VPN associations/endpoints, VPC endpoints, NAT gateways, and network resources.\nType exactly: %s\n> ' "$confirmation"
IFS= read -r answer
[[ $answer == "$confirmation" ]] || fail 'confirmation did not match; nothing deleted'

wait_for_client_vpn_disassociation() {
  local endpoint=$1 association=$2 status attempt
  for attempt in $(seq 1 60); do
    status=$(aws ec2 describe-client-vpn-target-networks --region "$region" --client-vpn-endpoint-id "$endpoint" --query "ClientVpnTargetNetworks[?AssociationId=='$association'].Status.Code | [0]" --output text)
    [[ $status == None || -z $status ]] && return 0
    sleep 5
  done
  fail "timed out disassociating $association from $endpoint"
}

remove_client_vpn_associations() {
  local endpoint association vpc
  local endpoints
  endpoints=$(aws ec2 describe-client-vpn-endpoints --region "$region" --query 'ClientVpnEndpoints[].ClientVpnEndpointId' --output text)
  [[ -z $endpoints || $endpoints == None ]] && return 0
  for endpoint in $endpoints; do
    local networks
    networks=$(aws ec2 describe-client-vpn-target-networks --region "$region" --client-vpn-endpoint-id "$endpoint" --output json)
    while IFS=$'\t' read -r association vpc; do
      [[ -n $association ]] || continue
      [[ $vpc == "$vpc_id" ]] || continue
      aws ec2 disassociate-client-vpn-target-network --region "$region" --client-vpn-endpoint-id "$endpoint" --association-id "$association" >/dev/null
      wait_for_client_vpn_disassociation "$endpoint" "$association"
      # An endpoint with no remaining target networks is no longer serving another VPC.
      remaining=$(aws ec2 describe-client-vpn-target-networks --region "$region" --client-vpn-endpoint-id "$endpoint" --query 'length(ClientVpnTargetNetworks)' --output text)
      if [[ $remaining == 0 ]]; then
        aws ec2 delete-client-vpn-endpoint --region "$region" --client-vpn-endpoint-id "$endpoint" >/dev/null
        for attempt in $(seq 1 60); do
          status=$(aws ec2 describe-client-vpn-endpoints --region "$region" --query "ClientVpnEndpoints[?ClientVpnEndpointId=='$endpoint'].Status.Code | [0]" --output text)
          [[ $status == None || -z $status ]] && break
          sleep 5
        done
        [[ $status == None || -z $status ]] || fail "timed out deleting Client VPN endpoint $endpoint"
      fi
    done < <(jq -r '.ClientVpnTargetNetworks[]? | [.AssociationId,.VpcId] | @tsv' <<<"$networks")
  done
}

remove_external_vpc_endpoints() {
  local endpoints endpoint stack_resources
  endpoints=$(aws ec2 describe-vpc-endpoints --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'VpcEndpoints[].VpcEndpointId' --output text)
  [[ -z $endpoints || $endpoints == None ]] && return 0
  stack_resources=$(aws cloudformation list-stack-resources --region "$region" --stack-name "$stack" --query 'StackResourceSummaries[?ResourceType==`AWS::EC2::VPCEndpoint`].PhysicalResourceId' --output text)
  for endpoint in $endpoints; do
    [[ $endpoint == None ]] && continue
    [[ " $stack_resources " == *" $endpoint "* ]] && continue
    aws ec2 delete-vpc-endpoints --region "$region" --vpc-endpoint-ids "$endpoint" >/dev/null
    for attempt in $(seq 1 60); do
      state=$(aws ec2 describe-vpc-endpoints --region "$region" --vpc-endpoint-ids "$endpoint" --query 'VpcEndpoints[0].State' --output text 2>/dev/null || true)
      [[ $state == None || -z $state ]] && break
      sleep 5
    done
    [[ $state == None || -z $state ]] || fail "timed out deleting VPC endpoint $endpoint"
  done
}

remove_tagged_rosa_groups() {
  local groups group
  groups=$(aws ec2 describe-security-groups --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default' && Tags[?Key=='red-hat-clustertype' && Value=='rosa']].GroupId" --output text)
  for group in $groups; do [[ $group == None ]] || aws ec2 delete-security-group --region "$region" --group-id "$group" >/dev/null; done
}

cleanup_unmanaged_vpc() {
  local ids id nat_json nat allocations igw subnet rt sg eni_count attempt state
  ids=$(aws ec2 describe-vpc-endpoints --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'VpcEndpoints[].VpcEndpointId' --output text)
  if [[ -n $ids && $ids != None ]]; then
    aws ec2 delete-vpc-endpoints --region "$region" --vpc-endpoint-ids $ids >/dev/null
    for id in $ids; do
      for attempt in $(seq 1 60); do
        state=$(aws ec2 describe-vpc-endpoints --region "$region" --vpc-endpoint-ids "$id" --query 'VpcEndpoints[0].State' --output text 2>/dev/null || true)
        [[ $state == None || -z $state ]] && break
        sleep 5
      done
      [[ $state == None || -z $state ]] || fail "timed out deleting VPC endpoint $id"
    done
  fi
  nat_json=$(aws ec2 describe-nat-gateways --region "$region" --filter "Name=vpc-id,Values=$vpc_id" --output json)
  while IFS=$'\t' read -r nat allocations; do
    [[ -n $nat ]] || continue
    aws ec2 delete-nat-gateway --region "$region" --nat-gateway-id "$nat" >/dev/null
    for attempt in $(seq 1 120); do
      state=$(aws ec2 describe-nat-gateways --region "$region" --nat-gateway-ids "$nat" --query 'NatGateways[0].State' --output text)
      [[ $state == deleted ]] && break
      sleep 5
    done
    [[ $state == deleted ]] || fail "timed out deleting NAT gateway $nat"
    for id in $allocations; do aws ec2 release-address --region "$region" --allocation-id "$id" >/dev/null; done
  done < <(jq -r '.NatGateways[]? | [.NatGatewayId,([.NatGatewayAddresses[]?.AllocationId] | join(" "))] | @tsv' <<<"$nat_json")

  for igw in $(aws ec2 describe-internet-gateways --region "$region" --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[].InternetGatewayId' --output text); do
    [[ $igw == None ]] && continue
    aws ec2 detach-internet-gateway --region "$region" --internet-gateway-id "$igw" --vpc-id "$vpc_id"
    aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw"
  done
  for igw in $(aws ec2 describe-egress-only-internet-gateways --region "$region" --query "EgressOnlyInternetGateways[?Attachments[?VpcId=='$vpc_id']].EgressOnlyInternetGatewayId" --output text); do
    [[ $igw == None ]] && continue
    aws ec2 delete-egress-only-internet-gateway --region "$region" --egress-only-internet-gateway-id "$igw"
  done
  for attempt in $(seq 1 60); do
    eni_count=$(aws ec2 describe-network-interfaces --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'length(NetworkInterfaces)' --output text)
    [[ $eni_count == 0 ]] && break
    sleep 5
  done
  [[ $eni_count == 0 ]] || fail "$region/$vpc_id still has $eni_count network interface(s); inspect them before retrying"
  for subnet in $(aws ec2 describe-subnets --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text); do [[ $subnet == None ]] || aws ec2 delete-subnet --region "$region" --subnet-id "$subnet"; done
  for rt in $(aws ec2 describe-route-tables --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --output json | jq -r '.RouteTables[] | select([.Associations[]?.Main] | any | not) | .RouteTableId'); do [[ $rt == None ]] || aws ec2 delete-route-table --region "$region" --route-table-id "$rt"; done
  for acl in $(aws ec2 describe-network-acls --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text); do [[ $acl == None ]] || aws ec2 delete-network-acl --region "$region" --network-acl-id "$acl"; done
  for sg in $(aws ec2 describe-security-groups --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do [[ $sg == None ]] || aws ec2 delete-security-group --region "$region" --group-id "$sg"; done
  aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id"
}

while IFS=$'\t' read -r region vpc_id name stack; do
  printf '\nCleaning %s/%s (%s)\n' "$region" "$vpc_id" "$name"
  remove_client_vpn_associations
  if [[ $stack != - ]]; then
    stack_status=$(get_stack_status "$region" "$stack")
  else
    stack_status=
  fi
  if [[ -n $stack_status && $stack_status != DELETE_COMPLETE ]]; then
    remove_external_vpc_endpoints
    remove_tagged_rosa_groups
    if [[ $stack_status == DELETE_IN_PROGRESS ]]; then
      aws cloudformation wait stack-delete-complete --region "$region" --stack-name "$stack"
    else
      aws cloudformation delete-stack --region "$region" --stack-name "$stack"
      aws cloudformation wait stack-delete-complete --region "$region" --stack-name "$stack"
    fi
  else
    cleanup_unmanaged_vpc
  fi
  exists=$(aws ec2 describe-vpcs --region "$region" --filters "Name=vpc-id,Values=$vpc_id" --query 'length(Vpcs)' --output text)
  if [[ $exists != 0 ]]; then cleanup_unmanaged_vpc; fi
done <"$candidate_file"

echo 'Cleanup finished.'
