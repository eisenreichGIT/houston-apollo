#!/bin/bash
# Houston - double-click to remove Houston's shortcuts from this Mac.
cd "$(dirname "$0")" || exit 1
/bin/bash ../scripts/apollo-setup.sh uninstall
echo
echo "You can close this window."
