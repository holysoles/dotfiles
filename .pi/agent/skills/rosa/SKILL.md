---
name: rosa
description: >-
  Use the ROSA CLI to inspect and operate Red Hat OpenShift Service on AWS
  clusters, including Hosted Control Plane clusters, image mirrors, access,
  machine pools, and cluster lifecycle.
---
# ROSA CLI

Use `rosa` for ROSA and ROSA HCP operations through the supported ROSA/OCM API.

## Login

Use the `rosa-login` helper to choose an AWS login flow. In a terminal, run it without selection flags to keep the menus:

```bash
rosa-login stage # or int / prod
```

The script runs `rh-aws-saml-login` for the selected payer first (`osd-staging-2` for int/stage, `rh-control` for prod; override with the payer-account argument or `--payer-account`). Menu choices: 1 uses the account ID and credentials returned by that SAML login directly for CLI access (no `osdctl account cli`); 2 selects the first account associated with the Kerberos user; 3 prompts for an account ID. Then choose CLI or console access. Console access still uses `osdctl account console`.

For non-interactive `osdctl` use, provide the account and method and use existing OCM credentials:

```bash
rosa-login stage --account-id 123456789012 --login-method cli --skip-ocm-login
```

The script checks the configured OCM URL and `ocm whoami`; if already authenticated to the requested environment, it skips `ocm login`. `--skip-ocm-login` bypasses that check and is required for non-interactive runs. For menu option 2, OCM credentials must already be available before starting because the script queries `osdctl account mgmt list` before its own OCM check/login. Console mode launches a browser interactively and prints the console URL when run non-interactively.

AWS credentials exported by the `osdctl` flow do not persist in the parent shell when the script is run as a command. Use `--` to run a command with the selected CLI credentials; the script verifies the AWS account before running it, and the command's exit status becomes the script's exit status:

```bash
rosa-login int osd-staging-1 --account-id 123456789012 \
  --login-method cli --skip-ocm-login -- \
  aws ssm start-session --region us-east-1 --target <instance-id>
```

The command form requires `--login-method cli`. Confirm the instance belongs to the selected account; this does not grant missing SSM permissions.

## Safe workflow

- Before an unfamiliar operation, check the installed CLI's syntax: `rosa --help`, then `rosa <group> --help` and `rosa <group> <resource> --help`. Flags and HCP support vary by CLI version.
- Confirm the target cluster and account before mutating: `rosa whoami`, `rosa list clusters`, `rosa describe cluster --cluster=<name-or-id>`. `rosa config get url` shows the configured OCM API environment; do not read or print access/refresh tokens.
- Default to read-only. Treat `create`, `edit`, `delete`, `grant`, `revoke`, `upgrade`, and cluster lifecycle commands as mutations. Show the exact target/change and get confirmation unless the user explicitly requested it. Use `--yes` only when explicitly requested.
- Never put tokens or passwords in source, logs, or shell history. Prefer the supported login flow (`rosa login --use-auth-code`, or `--use-device-code` on headless systems); use `--token` only with a protected variable or prompt.
- For AWS-related actions, confirm the AWS profile/account and region; `--profile` and `--region` are available on many commands. Do not assume the active AWS account from the cluster name.

#### Account-switch troubleshooting

- Set `REGION` explicitly and always pass `-r "$REGION"` to `osdctl account cli`; do not rely on a default region.
- If `osdctl account cli` returns a transient-looking error such as `No resources for AWS tag` or `BPTools Error: Proxy Unavailable`, retry the same command once with the same account ID and region before concluding access is unavailable. Do not switch accounts or bypass the proxy as a workaround.
- After credentials are exported, verify `aws sts get-caller-identity` and confirm the account is the intended individual test account before querying AWS. If the retry still fails, stop and report the exact error.

# HCP image mirrors

Use ROSA's image-mirror commands for HCP cluster mirror configuration rather than applying a generated `ImageDigestMirrorSet` directly. Some ROSA policies reject direct IDMS writes and direct operators to the HostedCluster/ROSA configuration API.

```sh
rosa list image-mirrors --cluster=<cluster> --output=yaml
rosa create image-mirror --cluster=<cluster> \
  --source=<upstream-registry/repository> \
  --mirrors=<mirror-registry/repository>[,<additional-mirror>]
rosa edit image-mirror --cluster=<cluster> <mirror-id> \
  --mirrors=<complete-replacement-mirror-list>
rosa delete image-mirror --cluster=<cluster> <mirror-id>
```

- The CLI documents digest mirroring as the only supported type. `edit` replaces the mirror list, so inspect the current configuration first and preserve entries that should remain.
- The create/edit commands do not expose an IDMS `mirrorSourcePolicy` option. Do not promise source-fallback or strict/no-fallback semantics based on these commands alone; verify the resulting cluster configuration and test behavior.
- After a change, verify with `rosa list image-mirrors` and, when authorized, inspect the generated IDMS and worker-node registry configuration. Confirm the cache path is populated before concluding that a pull used PTC.
- A ROSA API mutation requires appropriate OCM authorization. Backplane elevation is temporary Kubernetes access to the selected cluster; it does not grant ROSA/OCM API permissions or bypass admission policies.

## Cluster and access operations

Useful read-only discovery:

```sh
rosa whoami
rosa list clusters --output=yaml
rosa describe cluster --cluster=<name-or-id> --output=yaml
rosa list machinepools --cluster=<name-or-id>
rosa list access-request --cluster=<name-or-id> --output=yaml
rosa describe access-request --id=<request-id>
```

- The `rosa create decision --access-request <id> --decision Approved|Denied` command is for authorized approvers, not for granting oneself access. A denial requires `--justification`.
- `rosa grant user <role> --user=<username> --cluster=<cluster>` and `rosa revoke user <role> ...` mutate cluster-user roles. Do not use these to self-grant; follow the organization's access approval process.
- `rosa create admin` creates a cluster-admin login and can return a generated password. Do not put a chosen password on the command line; handle returned credentials as secrets.
- Cluster deletion, role changes, machine-pool changes, and upgrades have operational/cost impact. Read the exact command help and verify the target before proceeding.

## Troubleshooting and command reference

- Inspect `rosa logs install --cluster=<cluster>` for provisioning failures; use `rosa logs --help` for install/uninstall details.
- ROSA cluster registry allow/blocked/insecure flags control registry policy; they do not configure image mirroring.
- CAPA/Terraform manage infrastructure or provisioning sources, not an individual ROSA image-mirror API change unless the owning provisioning code explicitly models it.
- If an API or admission policy denies a change, do not try alternate direct writes to bypass it. Use the supported ROSA API or coordinate with the resource owner.
- Consult the live command help for other operations, including `rosa create cluster`, account/operator roles, identity providers, machine pools, networking, add-ons, and upgrades. This skill is not a substitute for version-specific CLI help.
