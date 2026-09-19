#!/usr/bin/env bash
set -euo pipefail
id -u condor-tienda >/dev/null 2>&1 || useradd --system --no-create-home condor-tienda
chown -R condor-tienda:condor-tienda /opt/condor-tienda
cp /opt/condor-tienda/deploy/condor-tienda.service /etc/systemd/system/condor-tienda.service
systemctl daemon-reload
systemctl enable condor-tienda
systemctl start condor-tienda
