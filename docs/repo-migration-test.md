# Repository migration test: blueprint metadata

Runbook for verifying that blueprint catalog metadata is unchanged after a
connected repository is re-pointed to a new Git URL (for example, moving
from github.com to a self-managed GitHub Enterprise or GitLab instance).

Test subject: [`blueprints/repo-migration-test.yaml`](../blueprints/repo-migration-test.yaml).
Space used in the demo account: `PAN-repo-swap-test`. Repository name in
Torque: `torque-takehome-justo`.

## 1. What is actually under test

Torque holds blueprint metadata in two different places. The migration can
only break the second kind, so the test is designed to set both and tell
them apart.

| Field (Automation Inventory column) | Where it comes from | Set by |
|---|---|---|
| Display Name | `metadata.display-name` in the YAML | file |
| Icon | `metadata.icon.path` (`graphics/repo-migration-test.svg`) | file |
| Labels `migration-test`, `cloud: gcp`, `iac: terraform` | `metadata.blueprint-labels` in the YAML | file |
| Instructions tab, description, environment labels | `instructions`, `description`, `labels` in the YAML | file |
| Self-Service | publish state stored by Torque | UI or API |
| Building Block | asset-library membership stored by Torque | UI or API |
| Label `ui-added` | label association stored by Torque | UI or API |
| Catalog settings (max duration, max active environments, policies) | stored by Torque | UI or API |

File-derived fields are re-read from the repository on every sync. If the
new repository contains the same commit they will match by construction.

Torque-persisted fields are stored against the key
`space + repository name + blueprint name`. This is the part that a
migration can lose, and the reason the test must keep the repository
**name** stable if the goal is a transparent swap.

Two facts from the public API that matter for planning the swap:

- The update-repository call (`PUT /api/spaces/{space}/repositories/{name}`)
  accepts `credential_name`, `agents`, `use_all_agents` and
  `eac_auto_registration` only. There is no `repository_url` field. If the
  UI's edit dialog does not allow changing the URL either, the swap is a
  remove-and-re-add, and the test then shows whether re-adding under the
  same name recovers the persisted state.
- Every grain's `source.store` references the repository by its Torque name.
  If the migration re-registers the repository under a different name, every
  blueprint in the repo has to be edited, regardless of what the catalog
  rows show.

## 2. Setup before the swap

1. Push this commit and let Torque sync the repository. In Automation
   Inventory > Blueprints confirm that `repo-migration-test` shows the custom
   bucket icon, display name `Repo Migration Test (GCS Bucket)` and the three
   YAML labels.
2. Publish it to the self-service catalog (the publish button on the
   blueprint page). The Self-Service column should now be selected.
3. Mark it as a Building Block from the blueprint page. The Building Block
   column should now be selected.
4. In Catalog Design, add one extra label that does not exist in the YAML,
   for example `ui-added` (create it with Manage Space labels if needed).
5. Optional, for one more persisted field: set a max duration under the
   blueprint's Policies tab.
6. Take the "before" snapshot (next section) and a screenshot of the
   Automation Inventory row and of the Catalog Design tab.

Steps 2 to 4 can be scripted instead. All calls use
`Authorization: Bearer $TORQUE_API_TOKEN` against `https://portal.qtorque.io`
(adjust the host if the demo account lives elsewhere).

```bash
SPACE=PAN-repo-swap-test
REPO=torque-takehome-justo
BP=repo-migration-test
H="Authorization: Bearer $TORQUE_API_TOKEN"
BASE=https://portal.qtorque.io

# Self-Service: publish to the catalog
curl -s -X POST "$BASE/api/spaces/$SPACE/catalog" -H "$H" -H 'Content-Type: application/json' \
  -d "{\"blueprint_name\":\"$BP\",\"repository_name\":\"$REPO\"}"

# Building Block: add to the space asset library
curl -s -X POST "$BASE/api/spaces/$SPACE/asset-library/$BP?repository_name=$REPO" -H "$H"
```

## 3. Snapshot script

Run once before the swap and once after. The jq filter keeps only the
fields the test cares about, so the diff is readable.

```bash
snapshot() {
  curl -s -H "$H" "$BASE/api/spaces/$SPACE/blueprints" \
  | jq -S --arg bp "$BP" '[.[] | select(.name == $bp) | {
      name, display_name, repository_name, repository_url, relative_path,
      enabled, asset_library, custom_icon, icon, color, labels,
      description, commit, last_synced }]' > "$1"
  curl -s -H "$H" "$BASE/api/spaces/$SPACE/catalog/$BP?repository_name=$REPO" \
  | jq -S . > "$1.catalog.json"
}

snapshot before.json
# ... perform the swap and wait for status Connected ...
snapshot after.json
diff before.json after.json
diff before.json.catalog.json after.json.catalog.json
```

Field meaning in the blueprint list response: `enabled` is the published
(Self-Service) state and `asset_library` is the Building Block state.
`custom_icon`, `labels` and `display_name` are the other three columns.

## 4. Perform the swap

Use whichever path the customer will use in production, and record which
one it was:

- **Edit in place.** Repositories > the repo > edit, change URL and
  credentials, keep the name `torque-takehome-justo`, save, wait for the
  status to return to Connected.
- **Remove and re-add.** Delete the repository from the space, add the new
  URL under the exact same name, wait for the first sync to finish.

Check the repository status with
`GET /api/spaces/$SPACE/repositories/repository?repository_name=$REPO`
(`status` is one of NotAvailable, Connected, Syncing, SyncFailed,
Disconnected) before taking the "after" snapshot.

## 5. Expected result and how to read a failure

Expected diff between the two snapshots: only `repository_url`, `commit` and
`last_synced` change. Everything else is identical, and the Automation
Inventory row looks the same as the "before" screenshot.

| Symptom after the swap | Likely cause |
|---|---|
| Display name, icon or YAML labels differ | The new repository does not contain the same commit, or the sync has not finished. Not a migration bug. |
| Self-Service or Building Block cleared, `ui-added` label gone | Torque-persisted state was not carried over. This is the finding to report, together with which swap path was used. |
| Blueprint missing entirely | Repository name changed, or the blueprint folder is not being scanned (check `relative_path`). |
| Blueprint present but shows a validation error | `source.store` no longer matches the repository name. |

## 6. Optional launch sanity check

Launching confirms that `source.store` still resolves to the migrated
repository. It needs the same prerequisites as the original blueprint: a
connected Kubernetes agent and the `gcp_sa_key_json` Space Parameter
holding a service-account key (see the main README). The environment
creates one private, versioned GCS bucket and exposes a console link
output. End the environment afterwards; `force_destroy` is set so the bucket
is removed cleanly.

## Notes

- `metadata.self-service` is deliberately commented out in the YAML. Setting
  it in the file publishes the blueprint automatically, but the schema
  documents that once it is set in YAML it can no longer be changed from
  the UI or API in any space, and it would also make the Self-Service column
  pass trivially (re-read from the file) instead of testing persisted state.
- Allowed `initial-color` values for blueprint labels, per the Torque
  Terraform provider: `aws`, `darkGray`, `frogGreen`, `pink`, `orange`,
  `blueGray`, `blue`, `bordeaux`, `teal`, `grey`.
- Icons must be SVG. Torque looks for them under the repository's
  `graphics/` directory. A YAML icon does not apply to blueprints stored in
  Torque rather than in Git.
