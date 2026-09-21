#!/bin/bash
set -euo pipefail

JENKINS_VERSION=2.516.1
JENKINS_HOME=/var/lib/jenkins

# Nitro instances expose the first additional EBS volume as nvme1n1; fall
# back to the Xen device name for anything non-Nitro.
if [ -e /dev/nvme1n1 ]; then
  DEVICE=/dev/nvme1n1
else
  DEVICE=/dev/xvdf
fi
if ! blkid "$DEVICE" >/dev/null 2>&1; then
  mkfs -t ext4 "$DEVICE"
fi
mkdir -p "$JENKINS_HOME"
mount "$DEVICE" "$JENKINS_HOME"
grep -q "$DEVICE" /etc/fstab || echo "$DEVICE $JENKINS_HOME ext4 defaults,nofail 0 2" >> /etc/fstab

amazon-linux-extras install -y java-openjdk17 || yum install -y java-17-amazon-corretto-headless
yum install -y wget git

# No agents (AK-PIP-10): builds run on the controller. AL2's yum maven
# (3.0.5) is too old for surefire 3.3.1 (needs 3.6.3+) - confirmed live.
wget -q -O /tmp/maven.tar.gz https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz
mkdir -p /opt/maven
tar -xzf /tmp/maven.tar.gz -C /opt/maven --strip-components=1
ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn

# AL2's yum python3 is 3.7.16 - too old for Tienda's Flask 3.0.3 (Requires-Python
# >=3.8, confirmed live: pip silently filters to <=2.2.5). No python3.8+ extras
# topic on this AL2 image either. Portable build instead of compiling from
# source - AL2's glibc 2.26 satisfies python-build-standalone's baseline.
PYTHON_URL=$(curl -s https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
  | python3 -c '
import json, sys
d = json.load(sys.stdin)
m = [a["browser_download_url"] for a in d["assets"]
     if "3.12" in a["name"]
     and "x86_64-unknown-linux-gnu-install_only.tar.gz" in a["name"]
     and "noopt" not in a["name"]
     and "debug" not in a["name"]
     and "freethreaded" not in a["name"]]
print(m[0] if m else "")
')
curl -fsSL "$PYTHON_URL" -o /tmp/cpython312.tar.gz
mkdir -p /opt/python3.12
tar -xzf /tmp/cpython312.tar.gz -C /opt/python3.12 --strip-components=1
rm -f /tmp/cpython312.tar.gz
ln -sf /opt/python3.12/bin/python3.12 /usr/local/bin/python3.12

useradd --system --no-create-home --home-dir "$JENKINS_HOME" --shell /sbin/nologin jenkins || true

# git-client's known_hosts verification strategy fails the multibranch scan
# without this - confirmed live.
mkdir -p "$JENKINS_HOME/.ssh"
ssh-keyscan -t rsa,ed25519 github.com >> "$JENKINS_HOME/.ssh/known_hosts" 2>/dev/null
chmod 700 "$JENKINS_HOME/.ssh"
chmod 600 "$JENKINS_HOME/.ssh/known_hosts"

mkdir -p /opt/jenkins
wget -q -O /opt/jenkins/jenkins.war "https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war"

# jenkins-plugin-manager resolves the dependency graph for this exact core
# version, pinning only matrix-auth to the vulnerable release under test
# (PLANTED: AK-PIP-10) — everything else resolves to whatever's current and
# compatible so the demo doesn't accidentally plant extra findings.
PLUGIN_MANAGER_URL=$(curl -s https://api.github.com/repos/jenkinsci/plugin-installation-manager-tool/releases/latest \
  | grep browser_download_url | grep '\.jar"' | cut -d '"' -f4)
wget -q -O /opt/jenkins/plugin-manager.jar "$PLUGIN_MANAGER_URL"
mkdir -p "$JENKINS_HOME/plugins"
java -jar /opt/jenkins/plugin-manager.jar \
  --war /opt/jenkins/jenkins.war \
  --plugin-download-directory "$JENKINS_HOME/plugins" \
  --plugins git workflow-aggregator credentials credentials-binding configuration-as-code pipeline-aws matrix-auth:3.2.9

mkdir -p "$JENKINS_HOME/init.groovy.d"
ADMIN_PASSWORD=$(openssl rand -hex 16)
echo -n "$ADMIN_PASSWORD" > "$JENKINS_HOME/.admin-password"
chmod 600 "$JENKINS_HOME/.admin-password"

cat > "$JENKINS_HOME/init.groovy.d/010-security.groovy" <<GROOVY
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()

def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount('admin', '${ADMIN_PASSWORD}')
realm.createAccount('dp-reader', UUID.randomUUID().toString())
instance.setSecurityRealm(realm)

def strategy = new GlobalMatrixAuthorizationStrategy()
strategy.add(Jenkins.ADMINISTER, 'admin')
strategy.add(Jenkins.READ, 'dp-reader')
strategy.add(hudson.model.Item.READ, 'dp-reader')
strategy.add(hudson.model.Item.EXTENDED_READ, 'dp-reader')
strategy.add(com.cloudbees.plugins.credentials.CredentialsProvider.VIEW, 'dp-reader')
instance.setAuthorizationStrategy(strategy)

instance.save()
GROOVY

cat > "$JENKINS_HOME/init.groovy.d/020-executors.groovy" <<'GROOVY'
import jenkins.model.*
Jenkins.get().setNumExecutors(2)
Jenkins.get().save()
GROOVY

# Suppresses the first-run setup wizard (PLANTED: AK-PIP-10 covers the
# stale LTS + no-agents shape; this just keeps first boot non-interactive).
touch "$JENKINS_HOME/jenkins.install.UpgradeWizard.state"
echo "${JENKINS_VERSION}" > "$JENKINS_HOME/jenkins.install.InstallUtil.lastExecVersion"

chown -R jenkins:jenkins "$JENKINS_HOME"

cat > /etc/systemd/system/jenkins.service <<'UNIT'
[Unit]
Description=Jenkins (condor-jenkins, LTS 2.516.1 — PLANTED: AK-PIP-10)
After=network.target

[Service]
User=jenkins
Environment=JENKINS_HOME=/var/lib/jenkins
ExecStart=/usr/bin/java -Djenkins.install.runSetupWizard=false -jar /opt/jenkins/jenkins.war --httpPort=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins
