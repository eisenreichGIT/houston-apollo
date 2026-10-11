#!/bin/bash
# Houston - double-click to set up this Mac: connect to Houston on your Apollo and pick shortcuts.
# First time: right-click this file > Open (macOS asks once because it was downloaded).
cd "$(dirname "$0")" || exit 1
/bin/bash ../scripts/apollo-setup.sh install
echo
echo "You can close this window."
