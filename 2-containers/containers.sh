#!/bin/sh
# Container launcher — delegates to dtk.sh
# Usage: ./containers.sh                    # interactive
#        ./containers.sh deb-nix cli        # direct
#        ./containers.sh deb-apt gui        # direct
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec sh "$SCRIPT_DIR/../dtk.sh" containers "$@"
