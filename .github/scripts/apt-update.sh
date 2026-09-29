#!/bin/bash
# Refresh the package lists, from Ubuntu's archive only. The runner image
# carries third-party sources (Google Chrome's, Microsoft's) whose indexes are
# republished often enough to fail `apt-get update` on a hash mismatch; this
# project installs nothing from them. Same script as ODataStore's.
set -euo pipefail

sudo rm -f /etc/apt/sources.list.d/google-chrome* \
           /etc/apt/sources.list.d/*google* \
           /etc/apt/sources.list.d/microsoft* || true

sudo apt-get -q -y -o Acquire::Retries=3 update
