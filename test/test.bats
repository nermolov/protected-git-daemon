#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

git_config() {
    git -C "$1" config user.email test@test.com
    git -C "$1" config user.name Test
}

make_commit() {
    local dir=$1 msg=${2:-"commit"}
    echo "$msg" > "$dir/${msg// /_}.txt"
    git -C "$dir" add .
    git -C "$dir" commit -m "$msg"
}

# ---------------------------------------------------------------------------
# One-time setup: build image, create repos, start container
# ---------------------------------------------------------------------------

setup_file() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    # Build the container image
    run podman build -q -t git "$BATS_TEST_DIRNAME/.."
    assert_success

    # Scratch space for repos and working clones
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "$tmpdir" > "$BATS_FILE_TMPDIR/tmpdir"
    mkdir -p "$tmpdir/repos"

    # --- non-bare repo with an initial commit ---
    git init -b main "$tmpdir/repos/nonbare"
    git_config "$tmpdir/repos/nonbare"
    make_commit "$tmpdir/repos/nonbare" "initial"

    # --- non-bare repo with a feature branch checked out (for denyCurrentBranch tests) ---
    git init -b feat/locked "$tmpdir/repos/nonbare2"
    git_config "$tmpdir/repos/nonbare2"
    make_commit "$tmpdir/repos/nonbare2" "initial"

    # --- pick a free non-privileged port ---
    local port
    port=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
    echo "$port" > "$BATS_FILE_TMPDIR/port"

    # --- start the container ---
    local cid
    cid=$(podman run -d --rm \
        -p "$port:9418" \
        -v "$tmpdir/repos/nonbare:/repos/nonbare:Z" \
        -v "$tmpdir/repos/nonbare2:/repos/nonbare2:Z" \
        git)
    echo "$cid" > "$BATS_FILE_TMPDIR/container_id"

    # --- wait for daemon to accept connections ---
    local nonbare_url="git://localhost:$port/nonbare/.git"
    local ready=0
    for _ in $(seq 1 30); do
        if git ls-remote "$nonbare_url" &>/dev/null; then
            ready=1
            break
        fi
        sleep 1
    done
    if [ "$ready" -eq 0 ]; then
        echo "git daemon did not become ready in time" >&2
        exit 1
    fi
}

teardown_file() {
    local cid port tmpdir
    cid=$(cat "$BATS_FILE_TMPDIR/container_id" 2>/dev/null || true)
    tmpdir=$(cat "$BATS_FILE_TMPDIR/tmpdir" 2>/dev/null || true)
    [ -n "$cid" ] && podman stop "$cid" &>/dev/null || true
    [ -n "$tmpdir" ] && rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Per-test setup: read shared state, build remote URLs, make a work dir
# ---------------------------------------------------------------------------

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'

    TEST_TMPDIR=$(cat "$BATS_FILE_TMPDIR/tmpdir")
    PORT=$(cat "$BATS_FILE_TMPDIR/port")
    NONBARE="git://localhost:$PORT/nonbare/.git"
    NONBARE2="git://localhost:$PORT/nonbare2/.git"
    WORK=$(mktemp -d "$TEST_TMPDIR/work.XXXXXX")
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# Control — operations that must succeed
# ---------------------------------------------------------------------------

@test "normal push to new branch succeeds (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b feat/allowed
    make_commit "$WORK/clone" "allowed commit"
    run bash -c "git -C '$WORK/clone' push origin feat/allowed 2>&1"
    assert_success
}

@test "creating a new tag succeeds (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b feat/tag-create
    make_commit "$WORK/clone" "tag base commit"
    git -C "$WORK/clone" push origin feat/tag-create
    git -C "$WORK/clone" tag v0.1-new
    run bash -c "git -C '$WORK/clone' push origin v0.1-new 2>&1"
    assert_success
}

# ---------------------------------------------------------------------------
# Denial — non-bare repo
# ---------------------------------------------------------------------------

@test "branch deletion denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b feat/deletion
    make_commit "$WORK/clone" "deletion branch commit"
    git -C "$WORK/clone" push origin feat/deletion
    run bash -c "git -C '$WORK/clone' push origin --delete feat/deletion 2>&1"
    assert_failure
    assert_output --partial "Deletion of"
}

@test "force push denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b feat/force
    make_commit "$WORK/clone" "force commit a"
    git -C "$WORK/clone" push origin feat/force
    # Rewrite history: different commit at the same position (non-fast-forward)
    git -C "$WORK/clone" reset --hard HEAD~1
    make_commit "$WORK/clone" "force commit b"
    run bash -c "git -C '$WORK/clone' push --force origin feat/force 2>&1"
    assert_failure
    assert_output --partial "Force push"
}

@test "push to refs/replace/ denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    local initial
    initial=$(git -C "$WORK/clone" rev-parse HEAD)
    make_commit "$WORK/clone" "replacement commit"
    local replacement
    replacement=$(git -C "$WORK/clone" rev-parse HEAD)
    git -C "$WORK/clone" replace "$initial" "$replacement"
    run bash -c "git -C '$WORK/clone' push origin 'refs/replace/$initial' 2>&1"
    assert_failure
    assert_output --partial "refs/replace/"
}

@test "tag mutation denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b feat/tag-mutation
    make_commit "$WORK/clone" "tag mutation commit a"
    git -C "$WORK/clone" push origin feat/tag-mutation
    git -C "$WORK/clone" tag v0.2
    git -C "$WORK/clone" push origin v0.2
    # Advance the tag to a descendant commit — ancestry check would pass,
    # only the explicit tag-immutability block catches this
    make_commit "$WORK/clone" "tag mutation commit b"
    git -C "$WORK/clone" tag -f v0.2 HEAD
    run bash -c "git -C '$WORK/clone' push --force origin v0.2 2>&1"
    assert_failure
    assert_output --partial "Updating existing tag"
}

@test "push to checked-out branch denied (non-bare)" {
    git clone "$NONBARE2" "$WORK/clone"
    git_config "$WORK/clone"
    make_commit "$WORK/clone" "checked-out branch commit"
    run bash -c "git -C '$WORK/clone' push origin feat/locked 2>&1"
    assert_failure
    assert_output --partial "refusing to update checked out branch"
}

@test "push to main denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    make_commit "$WORK/clone" "nonbare main direct commit"
    run bash -c "git -C '$WORK/clone' push origin main 2>&1"
    assert_failure
    assert_output --partial "Direct pushes to"
}

@test "push to master denied (non-bare)" {
    git clone "$NONBARE" "$WORK/clone"
    git_config "$WORK/clone"
    git -C "$WORK/clone" checkout -b master
    make_commit "$WORK/clone" "nonbare master commit"
    run bash -c "git -C '$WORK/clone' push origin master 2>&1"
    assert_failure
    assert_output --partial "Direct pushes to"
}

# ---------------------------------------------------------------------------
# Entrypoint guard
# ---------------------------------------------------------------------------

@test "entrypoint rejects bare repo" {
    local bare
    bare=$(mktemp -d)
    git init --bare "$bare/repo"
    run podman run --rm \
        -v "$bare/repo:/repos/repo:Z" \
        git
    assert_failure
    assert_output --partial "is not a non-bare git repository"
    rm -rf "$bare"
}
