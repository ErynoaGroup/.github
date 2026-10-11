#!/usr/bin/env bash
# Local hook. Install in a repo:  git config core.hooksPath .erynoa/hooks
# and copy this file + scan.sh + patterns.txt into .erynoa/hooks/ (or use .pre-commit-hooks.yaml).
# Optional extra patterns: export LEAK_EXTRA_FILE=~/.config/erynoa/leak-extra.txt
exec "$(dirname "$0")/scan.sh" --staged
