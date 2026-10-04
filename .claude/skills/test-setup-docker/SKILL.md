---
name: test-setup-docker
description: Run setup.sh --yes in a throwaway Fedora Docker container to verify the dependency list and install flow. Use after changing scripts/lib/deps.sh, setup.sh or dotfiles-manager.sh, or when asked to test the installer or dependencies in docker.
---

# Test setup.sh in Docker

Dependency test range for the installer. Manual use only, not a CI job.

## Run

From the repo root:

```bash
docker run --rm \
  -v "$PWD":/repo:ro \
  -v "$PWD/.claude/skills/test-setup-docker/test-setup.sh":/test.sh:ro \
  fedora:latest bash /test.sh > /tmp/setup-test.log 2>&1
grep -nE "ERROR|WARN|No match|Unable" /tmp/setup-test.log
```

Takes several minutes: the container installs the full dnf dependency list from a clean image. The repo is mounted read-only and copied inside, so the working tree is never touched.

## Read the result

Real failures (fix these):
- `No match for argument` or `Unable to find a match`: a package in `DEPS_DNF` (`scripts/lib/deps.sh`) is missing or renamed.
- `Missing dependencies:` listed after the install step: a command in `DEPS_REQUIRED` that no package in `DEPS_DNF` provides.
- Missing symlinks in the final `ls` output: broken `create_symlinks` or `setup_thumbnailers`.

Expected in a container (ignore):
- `systemctl --user daemon-reload failed` and `Battery timer install failed`: no systemd.
- `dconf-WARNING ... Cannot autolaunch D-Bus`: no session bus.
- `Avatar generation failed`: no AccountsService.
- The pre-install `Missing dependencies:` warning: the image starts empty.

Report the actual failing lines. Do not claim the install works without reading the log.
