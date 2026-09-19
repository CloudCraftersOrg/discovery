#!/usr/bin/env bash
set -euo pipefail
cd /opt/condor-tienda
python3 -m venv venv
venv/bin/pip install -r requirements.txt
