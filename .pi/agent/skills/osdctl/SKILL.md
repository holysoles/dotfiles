---
name: osdctl
description: >-
  Operate and troubleshoot ROSA/OSD with the `osdctl` CLI. Use for cluster
  triage, HCP, Hive, AWS accounts, alerts, service logs, CloudTrail, networking,
  RHOBS, organization lookup, and SRE operational workflows.
---
# osdctl

Use `osdctl` for ROSA/OSD SRE operations.

Source: `~/code/osdctl/`
Config: `~/.config/osdctl` (created by `osdctl setup`)

## Rules

- Run `osdctl <group> <command> --help` before uncommon operations; flags vary by command.
- Use the complete internal OCM cluster ID unless command help explicitly accepts a name or external ID.
- Privileged commands require `--reason` with an OHSS/PD ticket.
- Before mutating state, show the target and command, use `--dry-run` when available, and get confirmation unless the user explicitly requested the mutation.
- `-S, --skip-version-check` is the only universal operational flag.

## Setup

```bash
osdctl setup
```

## Task routing

| Task | Command group |
| --- | --- |
| Cluster overview, health, support, resync, pull secrets | `osdctl cluster` |
| Hosted control plane status, backup, upgrade | `osdctl hcp` |
| Service logs | `osdctl servicelog` |
| Alerts and silences | `osdctl alert` |
| AWS account credentials, console, claims | `osdctl account` |
| AWS audit events | `osdctl cloudtrail` |
| Egress verification and packet capture | `osdctl network` |
| RHOBS alerts, dashboards, logs, metrics | `osdctl rhobs` |
| Organization lookup | `osdctl org` |
| Hive ClusterDeployments and ClusterSync failures | `osdctl hive` |
| AWS Account Operator pool | `osdctl aao` |
| Jira helpers | `osdctl jira` |
| app-interface SAAS file promotions | `osdctl promote` |

Use `osdctl --help` for less-common groups such as `cost`, `env`, `evidence`,
`iampermissions`, `mc`, and `swarm`.

## Core workflows

### Incident triage

```bash
osdctl cluster context -C "$CLUSTER_ID" --full
osdctl cluster support status -C "$CLUSTER_ID"
osdctl servicelog list -C "$CLUSTER_ID" --all-messages
osdctl alert list -C "$CLUSTER_ID" --level firing --reason "$TICKET"
osdctl cloudtrail errors -C "$CLUSTER_ID" --since 2h --json
osdctl hcp status -C "$CLUSTER_ID" # HCP only
```

`cluster context --full` can return partial results after collection errors;
a failed check means unknown, not empty.

### Hive resync

```bash
osdctl hive csf -C "$CLUSTER_ID" -o json
osdctl cluster resync -C "$CLUSTER_ID"
```

`resync` deletes the ClusterSync to force recreation. Confirm before running.
Use `--hive-ocm-url production` only when intentionally resolving Hive in a
different environment from the target cluster.

### Service logs

```bash
osdctl servicelog post -C "$CLUSTER_ID" -t template.json --dry-run
osdctl servicelog post -q "managed='true' and state is 'ready'" -t template.json --dry-run
```

Review dry-run output and matched clusters before dropping `--dry-run`.

### HCP upgrade

```bash
osdctl hcp transition-to-eus --clusters-file clusters.json --dry-run
osdctl hcp force-upgrade -C "$CLUSTER_ID" --target-y 4.16 \
  --send-service-log end-of-support --dry-run
```

### AWS access

```bash
osdctl account cli -i "$AWS_ACCOUNT_ID" -p "$PROFILE"
osdctl account console -i "$AWS_ACCOUNT_ID" --launch
```

### Network verification

```bash
osdctl network verify-egress -C "$CLUSTER_ID"
osdctl network verify-egress -C "$CLUSTER_ID" --pod-mode --reason "$TICKET"
```

Pod mode creates Kubernetes Jobs and requires elevation when using a cluster ID.


