#!/usr/bin/env bash
# Houston - remove Houston's shortcuts from this Linux computer.
exec /usr/bin/env bash "$(cd "$(dirname "$0")" && pwd)/../scripts/apollo-setup.sh" uninstall
