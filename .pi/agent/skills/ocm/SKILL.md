---
name: ocm
description: >-
  Working with the `ocm` CLI for OpenShift Cluster Manager. Use for clusters,
  machine pools, add-ons, IDPs, upgrade policies, account/org info, and raw REST
  calls to the OCM API.
---
# OCM CLI

Use the `ocm` CLI for all OCM API operations. Named subcommands cover most
common tasks; fall back to `ocm get/post/patch/delete` for anything else.

### Auth

```sh
# Preferred: offline token from https://console.redhat.com/openshift/token
ocm login --token=<token>

# Browser-based OAuth (interactive)
ocm login --use-auth-code

# Device code (headless/remote)
ocm login --use-device-code

ocm logout
ocm whoami          # print current account info (JSON)
ocm token           # print current access token (pipe to curl etc.)
ocm token --payload # decode JWT payload
```

### Config

```sh
ocm config get url                          # current API endpoint
ocm config set url production               # aliases: production, staging, integration
ocm config set url https://api.openshift.com

# Config file: ~/.config/ocm/ocm.json (override with OCM_CONFIG env var)
# Pager: ocm config set pager less
```

### Clusters

### Deleted cluster check

Deleted clusters return 404 from Clusters Management, but their subscription may remain:

```sh
~/.pi/agent/skills/ocm/scripts/cluster-history.sh <OCM_CLUSTER_ID>
```

For deprovisioned clusters, `updated_at` is an estimate—not a confirmed deletion time.

```sh
# List clusters (all columns by default)
ocm list clusters

# Filter by name substring
ocm list clusters mycluster

# Filter with SQL LIKE search
ocm list clusters -p "search=name like '%rosa%'"
ocm list clusters -p "search=state='ready' and product.id='rosa'"

# Custom columns
ocm list clusters --columns "id, name, state, region.id, product.id, hypershift.enabled"

# Describe a cluster (name, ID, or external ID)
ocm describe cluster mycluster
ocm describe cluster 1abc2def3ghi           # internal ID
ocm describe cluster --json mycluster | jq '.state'

# Cluster status
ocm cluster status mycluster
```

### Cluster Resources

```sh
# Add-ons
ocm list addons -c mycluster
ocm list addons -c mycluster --columns "id, name, state"

# Identity providers
ocm list idps -c mycluster

# Ingresses
ocm list ingresses -c mycluster

# Machine pools
ocm list machinepools -c mycluster

# Upgrade policies
ocm list upgradepolicies -c mycluster

# Users
ocm list users -c mycluster
```

### Create / Edit Resources

```sh
# Machine pool (pool ID is positional)
ocm create machinepool -c mycluster --instance-type m5.xlarge --replicas 2 mp-extra
ocm edit   machinepool -c mycluster --replicas 3 mp-extra

# IDP
ocm create idp -c mycluster --type github --name github-idp --client-id <id> --client-secret <secret> --organizations myorg

# Private ingress
ocm create ingress -c mycluster --private

# User access (username is positional)
ocm create user -c mycluster --group dedicated-admins alice

# Upgrade policy (interactive)
ocm create upgrade-policy -c mycluster
```

### Account & Org

```sh
ocm account status           # current account + subscription
ocm account orgs             # organizations the account belongs to
ocm account users            # users in the org
ocm account roles            # available roles

ocm list organization        # list organizations (supports -p search=...)
ocm list quota -c mycluster  # quota consumed by a cluster
ocm list region              # available cloud provider regions
ocm list versions            # supported OCP versions (default: stable channel)
ocm list versions --channel-group candidate
```

### Hibernate / Resume

```sh
ocm hibernate cluster mycluster
ocm resume    cluster mycluster
```

### Cluster Login (console / API)

```sh
ocm cluster login mycluster              # opens kubeconfig/browser login
ocm cluster login mycluster --console    # open web console in browser
ocm cluster login mycluster --token      # display API login token
```

### Raw REST (escape hatch)

Use `ocm get/post/patch/delete` for anything the named commands don't cover.
The path is relative to the API root (`https://api.openshift.com`). Before
POST/PATCH/DELETE, verify `ocm config get url`, resolve resource IDs, show the
target and payload, and get confirmation unless the user explicitly requested
the mutation.

```sh
# GET — browse or query any resource
ocm get /api/clusters_mgmt/v1/clusters | jq '.items[].id'
ocm get /api/clusters_mgmt/v1/clusters -p "search=name='mycluster'" | jq '.items[0]'
ocm get /api/clusters_mgmt/v1/clusters/<ID>
ocm get /api/clusters_mgmt/v1/clusters/<ID>/credentials
ocm get /api/clusters_mgmt/v1/clusters/<ID>/logs/install | jq -r '.content'
ocm get /api/clusters_mgmt/v1/clusters/<ID>/logs/uninstall | jq -r '.content'
ocm get /api/clusters_mgmt/v1/clusters/<ID>/addons
ocm get /api/clusters_mgmt/v1/clusters/<ID>/upgrade_policies
ocm get /api/accounts_mgmt/v1/subscriptions -p "search=cluster_id='<ID>'" | jq '.items[0]'
ocm get /api/accounts_mgmt/v1/organizations/<ORG_ID>/quota_cost | jq '.items'

# POST — create resources via JSON body
echo '{"name":"mp-2","instance_type":"m5.large","replicas":2}' | \
  ocm post /api/clusters_mgmt/v1/clusters/<ID>/machine_pools

# PATCH — update resources
echo '{"replicas":3}' | \
  ocm patch /api/clusters_mgmt/v1/clusters/<ID>/machine_pools/<MP_ID>

# DELETE
ocm delete /api/clusters_mgmt/v1/clusters/<ID>/machine_pools/<MP_ID>
```

### Tips & Gotchas

- **`--parameter search=`** uses SQL LIKE syntax: `%` wildcard, `=` exact, `and`/`or`.  
  Always quote the value: `-p "search=name like 'rosa-%'"`.
- **`--json`** on `describe cluster` dumps the full JSON struct; pipe to `jq`.
- **`--debug`** prints raw HTTP requests and responses — useful for discovering undocumented API paths.
- **`--columns`** on list commands accepts dot-path notation into the JSON struct (e.g. `cloud_provider.id`, `hypershift.enabled`).
- **`ocm token`** emits only the access token string — pipe directly into `Authorization: Bearer` headers for `curl` calls to the OCM API.
- **Env aliases** for `--url` / `ocm config set url`: `production` (default), `staging`, `integration`.
- **ID types**: OCM internal ID (alphanumeric, e.g. `1abc2def`), external ID (UUID), and display name are all accepted by most commands.  
  Use `ocm describe cluster --json <name> | jq '.id,.external_id'` to resolve them.
- **Pagination**: `ocm list` commands paginate automatically. For bounded queries against large result sets, use `ocm get` with `-p "size=10"` and `-p "page=1"`.


