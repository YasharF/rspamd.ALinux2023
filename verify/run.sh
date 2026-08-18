#!/bin/bash
# Install the built RPMs on AL2023 and start rspamd in the foreground.
#
#   verify/run.sh /path/to/rpms
#
# Run on AL2023 as root (a container is fine). Listens on 127.0.0.1:11333
# (normal worker), :11334 (controller) and :11332 (rspamd_proxy in milter
# mode -- see README's "Milter mode" section). Runs until killed.

set -eux -o pipefail

RPMS=${1:?usage: run.sh <directory of RPMs>}

# python3 for verify.yml's milter-protocol probe; not one of rspamd's own
# runtime dependencies.
dnf -y install python3

# Everything, debuginfo included: it costs little and helps if rspamd crashes.
dnf -y install "$RPMS"/*.rpm

rspamadm configtest -c /etc/rspamd/rspamd.conf

exec rspamd -c /etc/rspamd/rspamd.conf -f
