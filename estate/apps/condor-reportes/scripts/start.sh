#!/usr/bin/env bash
set -euo pipefail
id -u condor-reportes >/dev/null 2>&1 || useradd --system --no-create-home condor-reportes
chown -R condor-reportes:condor-reportes /opt/condor-reportes
cp /opt/condor-reportes/deploy/condor-reportes.service /etc/systemd/system/condor-reportes.service
systemctl daemon-reload
systemctl enable condor-reportes
systemctl start condor-reportes
