#!/usr/bin/env bash
set -euo pipefail
cp /opt/condor-tienda/deploy/condor-tienda.service /etc/systemd/system/condor-tienda.service
systemctl daemon-reload
systemctl enable condor-tienda
systemctl start condor-tienda
