#!/bin/sh
# Stage for the Hostwatch deployment preview/update workflow.
set -eu
exec sh "$(dirname "$0")/stage-hostwatch.sh" "$@"
