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

### Environment preflight

- Before RHOBS work, check `ocm config get url` and use a cluster ID from the same environment as the data.
- `--hive-ocm-url` selects the Hive lookup environment; it does not switch the current OCM API environment. For a one-shot production call, use `OCM_URL=https://api.openshift.com` (use `https://api.stage.openshift.com` for stage); `OCM_URL` takes a URL, not the alias `production`.
- For RHOBS cell resolution, use an HCP cluster ID in the target environment, not a Hive MC name. Confirm `osdctl rhobs cell -C <hcp-id>` returns a cell before running metrics queries. A cell lookup failure means the environment/cluster route is unresolved, not that there are no metrics.

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

### RHOBS rules promotion

Promote a single tenant-rules commit with its SaaS service ID and source-repo SHA:

```bash
osdctl promote rhobs \
  --serviceId saas-hcp-rules \
  --gitHash "$RULES_SHA" \
  --appInterfaceDir ~/code/app-interface \
  --configRepoDir ~/code/rosa-rhobs-rules
```

Use `saas-mc-rules` or `saas-sc-rules` for those rule families. The app-interface checkout must be clean. The command creates a branch and commit; push it and open an MR. For tenant rules, it promotes the initial production wave; later waves use their existing soak and post-deploy gates.

For this service-specific flow, `--configRepoDir` overrides the resource-template repo used to resolve the SHA. Point it at the rules repo checkout and make sure that checkout has fetched the commit. Do not use `--latest` or omit `--serviceId` for a single `rosa-rhobs-rules` commit; those are for bulk RHOBS configuration promotion.

New rules labeled `severity: soaking` already route through the RHOBS soaking receiver; no separate Alertmanager route change is needed just to deploy one.

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

### Backplane reports

```bash
osdctl cluster reports list -C "$CLUSTER_ID" --last 5
osdctl cluster reports get -C "$CLUSTER_ID" --report-id "$REPORT_ID"
osdctl cluster reports create -C "$CLUSTER_ID" \
  --summary "Test report" --data "Report contents"
```

`get` is read-only; omit `--report-id` to retrieve the latest report. Incident
notes may include a report ID and the matching cluster ID. `--data` accepts
plain text and is base64-encoded by osdctl; use `--file` for file contents.
Creating a report writes to the configured backplane-api environment, not to
the cluster. Check the Backplane URL and proxy config before creating test
data; report access requires an authorized Backplane role. Reports persist, and
osdctl has no report-delete command, so use a test cluster for test data.

`OCM_URL=staging` selects staging OCM; `BACKPLANE_URL` explicitly selects the
staging Backplane API.

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

Use `-p KEY=VALUE` to fill template placeholders, and confirm the template's stated cause applies before posting. Review dry-run output and matched clusters before dropping `--dry-run`.

### HCP upgrade

```bash
osdctl hcp transition-to-eus --clusters-file clusters.json --dry-run
osdctl hcp force-upgrade -C "$CLUSTER_ID" --target-y 4.16 \
  --send-service-log end-of-support --dry-run
```

### AWS access

`account cli` requires an AWS account ID and assumes that account's
`OrganizationAccountAccessRole`. Its default output is shell exports and its
default region is `us-east-1`; set `-r` to the target resource's region.

```bash
eval "$(osdctl account cli -p "${PROFILE}" -i "${AWS_ACCOUNT_ID}" \
  -r "${REGION}" -o env)"
aws sts get-caller-identity
osdctl account console -i "${AWS_ACCOUNT_ID}" -p "${PROFILE}" \
  -r "${REGION}" --launch
```

### Network verification

```bash
osdctl network verify-egress -C "$CLUSTER_ID"
osdctl network verify-egress -C "$CLUSTER_ID" --pod-mode --reason "$TICKET"
```

Pod mode creates Kubernetes Jobs and requires elevation when using a cluster ID.


