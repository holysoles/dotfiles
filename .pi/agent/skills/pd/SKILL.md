---
name: pd
description: >-
  Working with the `pd` CLI for PagerDuty. Use for incidents, schedules,
  on-call, services, escalation policies, users, and teams.
---
# PagerDuty CLI

Use the `pd` CLI (pagerduty-cli) for all PagerDuty operations. Prefer CLI
over REST calls; fall back to `pd rest` only for operations the CLI doesn't
cover.

### Auth

```sh
pd login          # browser OAuth
pd auth set       # paste a token directly
```

Always pass `-b <alias>` if the user has multiple accounts configured.

### Common flags (most commands)

| Flag              | Meaning                                             |
| ----------------- | --------------------------------------------------- |
| `--output=json`   | Clean JSON output — pipe to `jq` for filtering      |
| `-p` / `--pipe`  | Emit or read IDs for command chaining                |
| `-m` / `--me`    | Scope results to the authenticated user              |

### Incidents

```sh
# Get a single incident by ID (response fields are under .incident)
pd rest get -e /incidents/<ID> | jq '.incident'

# Get the incident timeline, including notes
pd rest get -e '/incidents/<ID>/log_entries?is_overview=false&include[]=channels&limit=100'

# Extract notes from the timeline
pd rest get -e '/incidents/<ID>/log_entries?is_overview=false&include[]=channels&limit=100' |
  jq -r '.log_entries[] | select(.type == "annotate_log_entry") | .channel.content'

# Get alerts for an incident (prefer this over REST)
pd incident alerts -i <ID>
pd incident alerts -i <ID> -j   # full JSON detail

# List open incidents
pd incident list

# My open incidents
pd incident list -m

# Filter by service or team
pd incident list -S "my-service"
pd incident list -T "my-team"

# Acknowledge / resolve by ID (pipe-friendly)
pd incident ack    -i <ID>
pd incident resolve -i <ID>

# Acknowledge all triggered incidents assigned to me
pd incident list -m -s triggered -p | pd incident ack -p

# Create an incident
pd incident create --title "Something broke" --service "my-service"

# Add a note
pd incident notes -i <ID> --note "Investigating"

# Assign / reassign
pd incident assign -i <ID> -U user@example.com

# Merge duplicates
pd incident merge -i <primary_ID> -i <dupe_ID>
```

### Schedules & On-call

```sh
pd schedule list
pd schedule show -i <ID>
pd schedule oncall -i <ID>        # who's on call for a schedule
pd user oncall -e user@example.com # on-call shifts for a user
```

### Escalation Policies

```sh
pd ep list
pd ep oncall -i <ID>             # current on-call for a policy
pd ep open -i <ID>               # open in browser
```

### Services

```sh
pd service list
pd service list --output=json | jq '.[].name'
pd service disable -n "my-service"
pd service enable  -n "my-service"
```

### Users & Teams

```sh
pd user list
pd user list --output=json | jq '.[] | {id, email: .email}'
pd team list
```

### Raw REST (escape hatch)

```sh
# Embed query params directly in the URL — the -p flag does NOT work for pd rest get
pd rest get  -e '/incidents?status=triggered&urgency=high&limit=10'
pd rest post -e /incidents -d @payload.json
```

### Tips

- Pipe `-p` output between commands (IDs on stdout) to chain bulk actions.
- Use `--output=json` for machine-readable output; unlike `-j`, it doesn't mix progress lines into stdout. Other options: `csv`, `yaml`.
- Do not merge stderr into stdout (`2>&1`) before piping JSON to `jq`; PagerDuty progress messages can make the stream invalid JSON.
- **Incident urgency is only `high` or `low`** — there's no "critical" value. Alert severity (Critical/Warning) lives in the alert title or alert body, not the incident urgency field. To find the most critical incidents, filter by title: `select(.title | test("CRITICAL"; "i"))`.
- `pd incident list --since 2h` scopes to recent incidents (duration strings accepted).
- Use `pd incident list --limit <N>` for bounded queries; it disables full pagination.
- `pd log` shows the domain-level audit log for recent activity.
