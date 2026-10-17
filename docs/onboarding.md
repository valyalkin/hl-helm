# Onboarding a new application

_This guide is completed in task group US7 (T074–T075). It already carries the change-review
procedure required by Principle III._

## Previewing a change before it merges

No staging cluster exists, so a human reviews the rendered diff before a change becomes real.

- **Application tier** (anything under `charts/apps/`): merging deploys it. CI renders the diff
  between `main` and your branch into the pull request's job summary. Read it, and paste it into
  the change description.
- **Infrastructure and bootstrap tiers**: a merge changes nothing on the cluster. Before running
  `bootstrap/install.sh`, preview against the running release:

  ```sh
  helm plugin install https://github.com/databus23/helm-diff   # once
  helm diff upgrade <release> charts/<tier>/<chart> -n <namespace> -f <values file>
  ```

  Record the output in the change description, then apply from a committed state only.

Run `scripts/validate.sh` locally first; it is the same gate CI enforces.
