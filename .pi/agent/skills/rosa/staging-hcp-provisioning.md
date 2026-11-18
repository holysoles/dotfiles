# Staging ROSA HCP provisioning (personal workflow)

Run in one shell. This provisions AWS networking, OIDC configuration, account roles, and a billable cluster; confirm the intended staging OCM environment, AWS account, region, name, and CLI flags before running. Set a unique `CLUSTER_NAME` yourself. This example uses one AZ, `us-west-2`, and `10.0.0.0/16`.

## 1. Log in and select the AWS account

The existing `rosa-login` helper can replace the manual login/account-selection flow. Source it so credentials remain in this shell; choose **your AWS account** (option 2), not the payer. Pass `osd-staging-1` explicitly to match this workflow (the helper defaults to `osd-staging-2`):

```bash
export REGION=us-west-2 AWS_REGION=us-west-2
KERB_ID=$(klist -l | awk -F '@' '/@/ {print $1}')
AWS_ACC_ID=$(osdctl account mgmt list -u "$KERB_ID" --output json | jq -er '.accounts[0]')
source ~/.local/bin/rosa-login stage osd-staging-1 --account-id $AWS_ACC_ID
# The helper exports AWS_ACC_ID for --billing-account.
export CLUSTER_NAME="replace-with-unique-name"
aws sts get-caller-identity | jq -r .Account
rosa whoami
```

Alternatively, do the login manually:

```bash
ocm login --use-auth-code --url=staging
export $(RH_AWS_SESSION_TIMEOUT=350 rh-aws-saml-login osd-staging-1 --output env)
aws sts get-caller-identity | jq -r .Account  # payer account at this point
KERB_ID=$(klist -l | awk -F '@' '/@/ {print $1}')
AWS_ACC_ID=$(osdctl account mgmt list -u "$KERB_ID" --output json | jq -er '.accounts[0]')
export REGION=us-west-2 AWS_REGION=us-west-2
export CLUSTER_NAME="replace-with-unique-name"
export $(osdctl account cli -i "$AWS_ACC_ID" -o env -r "$REGION" -S)
rosa whoami
```

Before creating anything, confirm `aws sts get-caller-identity --query Account --output text` matches `$AWS_ACC_ID` (the individual test account), and `ocm config get url` points to staging. If account switching fails, see the retry guidance in [SKILL.md](SKILL.md#account-switch-troubleshooting).

## 2. Create VPC and find subnets

```bash
rosa create network rosa-quickstart-default-vpc \
  --param Region="$REGION" \
  --param Name="$CLUSTER_NAME-stack" \
  --param AvailabilityZoneCount=1 \
  --param VpcCidr=10.0.0.0/16

VPCID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$CLUSTER_NAME-stack" | jq -r '.Vpcs[].VpcId')
PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" | jq -r '.Subnets | map(select(.Tags[] | select(.Key=="Name") | .Value | contains("Private")))[].SubnetId')
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" | jq -r '.Subnets | map(select(.Tags[] | select(.Key=="Name") | .Value | contains("Public")))[].SubnetId')
```

Check that `VPCID`, `PRIVATE_SUBNET_ID`, and `PUBLIC_SUBNET_ID` each resolve to exactly one ID before continuing; a reused name or extra subnets can yield multiple IDs.

## 3. Create OIDC config and account roles

```bash
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -er '.id')
CHANNEL_GROUP=stable
VERSION=$(ocm list version --channel-group "$CHANNEL_GROUP" | tail -n 1)
rosa create account-roles --region "$REGION" --version "${VERSION%."${VERSION#*.*.}"}" --hosted-cp -f --mode auto --yes
```

Confirm `OIDC_ID` and `VERSION` are nonempty and the selected version is the intended stable release. Check the installed CLI's help for flags that may have changed.

## 4. Create cluster and access it

```bash
rosa create cluster \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --version "$VERSION" \
  --billing-account "$AWS_ACC_ID" \
  --subnet-ids "$PRIVATE_SUBNET_ID,$PUBLIC_SUBNET_ID" \
  --channel-group "$CHANNEL_GROUP" \
  --oidc-config-id "$OIDC_ID" \
  --compute-machine-type m5.xlarge \
  --machine-cidr 10.0.0.0/16 \
  --hosted-cp --sts --yes --mode auto

rosa describe cluster -c "$CLUSTER_NAME" --watch
ocm backplane login "$CLUSTER_NAME"
```

Provisioning commonly takes ~15–20 minutes. Backplane login requires its own authorization; it is not the same as creating cluster credentials.
