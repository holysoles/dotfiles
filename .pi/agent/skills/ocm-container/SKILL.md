---
name: ocm-container
description: >-
  Set up and use the Red Hat ocm-container toolbox, including production,
  staging, and integration environments and its mounted OCM/Backplane configs.
  Use when running SRE CLI tools through ocm-container or troubleshooting its
  setup.
---
# ocm-container

Use `ocm-container` to run the SRE CLI tools packaged in the container, including
`oc`, `osdctl`, `ocm`, `backplane`, and `rosa`. It also mounts local configuration
for supported third-party tools. Commands run inside the container; config and
credentials remain on the host and may be mounted into it.

## Setup

Follow the team's [ocm-container how-to](~/code/ops-sop/v4/howto/ocm-container.md)
for the current setup and supported mounts. Before executing a downloaded script,
review it and its source. Do not paste, print, or commit access tokens or mounted
credentials. Add an OCM offline token locally to `~/.config/ocm-container/env.source`
from the official OpenShift token page; never ask the user to send the token here.

The usual setup includes:

- Pull `quay.io/app-sre/ocm-container` and tag it `ocm-container`.
- Install the upstream `ocm-container.sh` wrapper as `~/.local/bin/ocm-container`.
- Configure Backplane under `~/.config/backplane/` and create its session directory.
  If writing JSON configs, keep them valid JSON (no trailing commas).
- Select OCM production, staging, or integration with `--ocm-url prod|stage|int`;
  the CLI defaults to production. `OCM_CONFIG` can select an existing host OCM
  config. Successful authentication is cached in a per-environment OCM config under
  `~/.config/ocm/`.

## Use

Start the desired OCM environment, for example `ocm-container --ocm-url prod`
(or `stage` / `int`), to get a shell. ocm-container handles OCM authentication
when it starts; check it inside the container with `ocm whoami` and
`ocm config get url`. This OCM API login is separate from logging into a cluster.

`no-login: false` only enables automatic **cluster** login when a cluster ID is
provided at launch; it does not control OCM authentication. For example:

```sh
ocm-container --ocm-url stage --cluster-id <cluster-id>
```

If starting without a cluster ID, check the current Backplane target with
`ocm backplane status`. To select a cluster from inside the shell, log in and
verify the result:

```sh
ocm backplane login <cluster-id>
ocm backplane status
```

Use the CLI appropriate to the task (`ocm`, `oc`, `osdctl`, etc.). Prefer read-only
commands. Never perform cluster writes or deletes; a human must explicitly perform
any write step. Do not treat mounted credentials or a successful login as permission
to mutate a cluster.

## Troubleshooting

- If the wrapper is not found, check that `~/.local/bin` is on `PATH` and that the
  wrapper is executable.
- If a command is missing, verify it is running inside the container, which supplies
  the SRE dependencies.
- If authentication fails, check the local `env.source` and login state without
  displaying token contents. Re-authenticate through the approved local flow.
- If Backplane access fails, check the selected environment, Backplane config files,
  mounted session directory, and `ocm backplane status` before retrying.
- If a required third-party config is unavailable inside the container, check the
  corresponding mount configuration in the local wrapper; do not copy secrets into
  command output or the repository.
