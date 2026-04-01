# protected git daemon

written with assistance from Claude Code

serve your non-bare repos over the git protocol with destructive operations disabled, allowing safe write access from any sandboxed AI agents

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

run tests directly: `./test/bats/bin/bats test/test.bats`

run tests with nix:

make sure nixbld user can create rootless containers

```
for i in $(seq 1 32); do
  echo "nixbld${i}:$(( 100000 + (i-1)*65536 )):65536" >> /etc/subuid
  echo "nixbld${i}:$(( 100000 + (i-1)*65536 )):65536" >> /etc/subgid
done
```

run:

```
nix flake check --option sandbox false
```
