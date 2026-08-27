---
name: osdctl
description: detailed usage of osdctl
---
CLI toolbox for ROSA/OSD SRE operations — cluster triage, AWS account management, service logs, alerts, Hive, HCP, and RHOBS.

Source: `~/code/osdctl/`
Config: `~/.config/osdctl` (YAML, auto-created on first run)

## Setup

```bash
osdctl setup   # interactive prompt; writes ~/.config/osdctl
```

Config keys: `pd_oauth_token`, `pd_user_token`, `jira_token`, `teamIds`, `prod_jumprole_account_id`, `aws_proxy`

## Common Flags

| Flag | Description |
| ------ | ------------- |
| `-C, --cluster-id` | Internal OCM cluster ID (most commands also accept name or external ID) |
| `--reason` | Required for privilege-elevated commands — use OHSS/PD ticket |
| `-p, --profile` | AWS profile name |
| `-o, --output` | `json`, `yaml`, `env`, `table`, `text`, `csv`, `long`, `short` (varies per command) |
| `--dry-run` | Preview without applying |
| `-S, --skip-version-check` | Skip latest-release check |

---

## cluster

Cluster investigation and operations.

- `context` — full situational overview: OCM info, PD alerts, Jira, CloudTrail, service logs. Key flags: `--full`, `-d` (days of SLs), `-o long|short|json`
- `health` — node conditions and cluster operator status
- `get-env-vars` — print CLUSTER_ID, EXTERNAL_ID, management namespace (`-o env` for export-ready)
- `support status|post|delete` — check/set/remove limited support reasons (`--misconfiguration cloud|cluster`, `--all`)
- `break-glass` / `break-glass cleanup` — emergency credentials (must be on hive shard)
- `cpd` — investigate cluster provisioning delays (DNS zone, OCM errors, BYOVPC routes)
- `etcd-health-check` / `etcd-member-replace` — etcd diagnostics and node replacement
- `resize control-plane|infra|request-serving-nodes` — resize node classes
- `resync` — delete clustersync to force Hive resync (`--hive-ocm-url` to target prod Hive from staging)
- `snapshot` / `diff` — capture and compare cluster state (namespaces, nodes, operators)
- `pull-secret audit|validate|update` — pull secret diagnostics and repair
- `logging-check` — logging support status
- `verify-dns` — HCP DNS endpoint resolution tests (requires VPN)
- `hypershift-info` — AWS object relationships for HCP clusters (`-o graphviz|table`)
- `sre-operators list|describe` — current vs latest SRE operator versions
- `transfer-owner` — transfer cluster ownership (Region Lead only)
- `check-banned-user` / `validate-pull-secret` — owner/pull-secret sanity checks
- `from-infra-id` — resolve cluster ID from infrastructure ID (Splunk use)
- `ssh key` — retrieve SSH key from Hive
- `imdsv2`, `change-ebs-volume-type`, `detach-stuck-volume`, `reports`, `cad` — misc ops

```bash
osdctl cluster context -C $CLUSTER_ID --full
osdctl cluster support post -C $CLUSTER_ID --misconfiguration cluster --problem "..." --resolution "..." --evidence "OHSS-1234"
osdctl cluster resync -C $CLUSTER_ID
```

---

## hcp

ROSA HCP (Hosted Control Plane) specific operations.

- `status` — ManifestWork sync, HostedCluster conditions, certs, NodePool health (from OCM live resources)
- `must-gather` — collect must-gather (`--gather sc,mc,sc_acm,hcp`)
- `backup` — trigger Velero backup from existing daily schedule (`--label`, `--annotation`)
- `force-upgrade` — force control plane upgrade to latest z of a y-stream; requires ForceUpgrader permission (`--target-y 4.16`, `--send-service-log end-of-support`)
- `transition-to-eus` — transition even y-stream clusters from `stable` → `eus` channel; handles recurring update policy automatically
- `get-cp-autoscaling-status` — autoscaling status for all hosted clusters on a management cluster (`--show-only ready-for-migration|needs-removal|safe-to-remove-override`)

```bash
osdctl hcp status -C $CLUSTER_ID
osdctl hcp force-upgrade -C $CLUSTER_ID --target-y 4.16 --send-service-log end-of-support --dry-run
osdctl hcp transition-to-eus --clusters-file clusters.json --dry-run
```

---

## servicelog

Post and list OCM/Hive service logs.

- `list` — list SRE service logs (`--all-messages` to include automated, `--internal` for internal)
- `post` — post via template file/URL (`-t`), inline overrides (`-r`), or bulk OCM query (`-q`); `-i` for internal-only; `-p` for template params; `--dry-run`

```bash
osdctl servicelog list -C $CLUSTER_ID --all-messages
osdctl servicelog post -C $CLUSTER_ID -t ~/template.json -p ALERT_NAME="foo" --dry-run
osdctl servicelog post -q "managed='true' and state is 'ready'" -t file.json
```

---

## alert

Cluster alert management.

- `list` — list alerts by level: `warning`, `critical`, `firing`, `pending`, `all` (requires `--reason`)
- `silence add|expire|list|org` — manage Alertmanager silences

```bash
osdctl alert list -C $CLUSTER_ID --level firing --reason "PD-12345"
```

---

## account

AWS Account Operator utilities.

- `cli` — temp AWS CLI credentials (`-i $ACCOUNT_ID`, `-o env|json`)
- `console` — AWS console URL (`--launch` to open browser, `-d` duration)
- `list account|account-claim` — list Account/AccountClaim CRs with state filters
- `get account|account-claim` — get a specific CR
- `set` — patch Account CR status (flags or `--patch` JSON)
- `reset` — reset Account CR and clean up secrets
- `mgmt assign|list` — assign/list developer AWS accounts by LDAP user
- `aws-creds` — diagnose IAM credentials for a cluster
- `servicequotas` — AWS service quota interaction
- `verify-secrets`, `generate-secret`, `clean-velero-snapshots` — misc account ops

```bash
osdctl account cli -i $AWS_ACCOUNT_ID -p $PROFILE
osdctl account console -i $AWS_ACCOUNT_ID --launch
```

---

## cloudtrail

AWS CloudTrail investigation.

- `errors` — surface permission/IAM errors (`--since 1h`, `--error-types AccessDenied,Forbidden`, `--json`, `--url`)
- `write-events` — filtered write event investigation (`--after`, `--until`, `-I`/`-E` include/exclude by `username|event|resource-name|resource-type|arn`, `--print-fields`, `--url`, `--raw-event`)
- `permission-denied-events` — shortcut for permission-denied events

```bash
osdctl cloudtrail errors -C $CLUSTER_ID --since 2h --json
osdctl cloudtrail write-events -C $CLUSTER_ID -I username=john.doe -E event=AssumeRole --url
```

---

## network

Network verification and packet capture.

- `verify-egress` — check cluster egress to required URLs via osd-network-verifier; auto-detects subnet/SG from OCM; `--pod-mode` runs as Kubernetes Jobs (requires `--reason`); `--platform` to override (`aws-classic`, `aws-hcp`, `aws-hcp-zeroegress`, `gcp-classic`); `--all-subnets` for PrivateLink
- `packet-capture` (alias `pcap`) — deploy capture daemonset/pod (`--duration`, `--single-pod`)

```bash
osdctl network verify-egress -C $CLUSTER_ID
osdctl network verify-egress -C $CLUSTER_ID --pod-mode --reason "PD-12345"
```

---

## rhobs

RHOBS.next observability utilities for cluster monitoring.

- `alerts` — list or silence RHOBS alerts for a cluster
- `cell` — get the RHOBS cell for a cluster
- `hcp-dashboard` — get the HCP Grafana dashboard URL for an HCP cluster
- `logs` — fetch logs from RHOBS for a cluster or cell
- `metrics` — fetch metrics from RHOBS for a cluster
- `mcp` — RHOBS MCP server for AI agent integration

```bash
osdctl rhobs cell -C $CLUSTER_ID
osdctl rhobs hcp-dashboard -C $CLUSTER_ID
osdctl rhobs logs -C $CLUSTER_ID
```

Top-level flags: `-C` (cluster ID or name), `--hive-ocm-url production|staging|integration`

---

## org

Organization information.

- `current`, `describe`, `context`, `get`, `clusters`, `aws-accounts`, `users`, `labels`, `customers`

```bash
osdctl org clusters --org-id $ORG_ID
osdctl org context --org-id $ORG_ID
```

---

## hive

Hive cluster management (run from a hive shard).

- `clusterdeployment list` (alias `cd list`) — list ClusterDeployment CRs
- `clusterdeployment listresources` — all Hive resources for a cluster
- `clustersync-failures` (alias `csf`) — list ClusterSyncs in failure state; `-C` for single cluster; `--limited-support`, `--hibernating` to include those; `-o yaml|json|csv|text`, `--sort-by timestamp|name|failingsyncsets`

```bash
osdctl hive csf
osdctl hive csf -C $CLUSTER_ID -o json
```

---

## aao

AWS Account Operator pool status.

```bash
osdctl aao pool
```

---

## promote

Promote services and operators.

- `saas`, `dynatrace`, `managedscripts`, `rhobs`, `block`

---

## jira

Jira integration.

- `quick-task` — create a ticket
- `create-handover-announcement` — SREPHOA handover announcement

---

## Key Workflows

- **Incident triage**: `cluster context --full` → `cluster support status` → `servicelog list --all-messages` → `alert list --level firing` → `cloudtrail errors --since 2h` → `hcp status` (for HCP)
- **HCP EOL upgrade**: `hcp transition-to-eus` (even y-streams) → `hcp force-upgrade --target-y X.Y --send-service-log end-of-support`
- **Bulk service log**: `servicelog post -q "..."  -t template.json --dry-run` then drop `--dry-run`
- **Hive resync**: `hive csf -C $ID` to confirm failures → `cluster resync -C $ID`
- **AWS access**: `account cli` or `account console` for temp creds/console


