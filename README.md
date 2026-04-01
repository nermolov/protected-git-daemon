# protected git daemon

written with assistance from Claude Code

serve your locally checked out (non-bare) repos over the git protocol with destructive operations disabled, allowing safe write access from any sandboxed AI agents. support for bare repos is intentionally omitted, as the restrictions here apply to remote pushes (via the `pre-receive` hook) while allowing any writes to the local/primary tree.

```bash
podman build -t git .
podman run \
  -it --rm -p 9418:9418 \
  --name git \
  -v /your-repo:/repos/your-repo:Z \
  -v /another-repo:/repos/another-repo:Z \
  git
```

use `git://hostname/your-repo/.git` as your remote in the sandbox

run tests: `./test/bats/bin/bats test/test.bats`
