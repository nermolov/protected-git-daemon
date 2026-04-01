#!/bin/sh
set -e

echo "Setting up git daemon export markers and hooks..."

# Touch git-daemon-export-ok and install pre-receive hook in each repository
for repo in /repos/*; do
    if [ ! -d "$repo/.git" ]; then
        echo "Error: $repo is not a non-bare git repository" >&2
        exit 1
    fi
    echo "Enabling daemon export for $repo"
    touch "$repo/.git/git-daemon-export-ok"
    mkdir -p "$repo/.git/hooks"
    cp /usr/local/bin/enforce-safe-writes.sh "$repo/.git/hooks/pre-receive"
    chmod +x "$repo/.git/hooks/pre-receive"
    # Block pushes to the checked-out branch (would desync working tree from HEAD)
    git -C "$repo" config receive.denyCurrentBranch refuse
done

echo "Starting git daemon..."
echo "Repositories will be accessible at git://hostname/<repo-name>"

# Start git daemon with push enabled
exec git daemon \
    --verbose \
    --reuseaddr \
    --base-path=/repos \
    --export-all \
    --enable=receive-pack \
    /repos
