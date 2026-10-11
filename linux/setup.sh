#!/usr/bin/env bash
# Houston - set up this Linux computer: connect to Houston on your Apollo and pick shortcuts.
# Run:  bash linux/setup.sh        (uses desktop dialogs if zenity is installed)
#       APOLLO_UI=terminal bash linux/setup.sh   (questions in the terminal)
exec /usr/bin/env bash "$(cd "$(dirname "$0")" && pwd)/../scripts/apollo-setup.sh" install
