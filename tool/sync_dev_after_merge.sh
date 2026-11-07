#!/usr/bin/env bash
set -euo pipefail

: "${MERGED_DEV_SHA:?MERGED_DEV_SHA is required}"
: "${MERGE_SHA:?MERGE_SHA is required}"

master_sha="$(git rev-parse refs/remotes/origin/master)"
dev_sha="$(git rev-parse --verify --quiet refs/remotes/origin/dev || true)"

if [[ "$dev_sha" == "$master_sha" ]]; then
  echo "dev already points to master."
  exit 0
fi
if [[ -z "$dev_sha" || "$dev_sha" != "$MERGED_DEV_SHA" ]]; then
  echo "::notice::dev changed or was deleted after the merge. Skipping the sync."
  exit 0
fi
if ! git merge-base --is-ancestor "$MERGE_SHA" "$master_sha"; then
  echo "::error::The pull request merge commit is no longer in master."
  exit 1
fi

sync_sha="$master_sha"
if ! git merge-base --is-ancestor "$dev_sha" "$master_sha"; then
  # Squash/rebase merges do not retain the original dev commits on master.
  # Retain both histories, using master's already merged content exactly.
  sync_sha="$(git \
    -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit-tree "$master_sha^{tree}" -p "$dev_sha" -p "$master_sha" \
    -m 'Sync master into dev after release merge')"
fi

# A lease prevents racing with new work or recreating a deleted dev branch.
# The ancestry check guarantees a fast-forward; no history is force-pushed.
git merge-base --is-ancestor "$dev_sha" "$sync_sha"
git push --force-with-lease="refs/heads/dev:$dev_sha" origin "$sync_sha:refs/heads/dev"
