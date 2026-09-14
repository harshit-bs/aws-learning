#!/bin/bash
# ============================================================
# EC2 User Data Script — Project 2
# Ye script EC2 launch hote waqt automatically chalta hai
# Kaam: Node.js install + app deploy + systemd service start
# ============================================================

set -e
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "========================================="
echo " EC2 Bootstrap Starting — $(date)"
echo "========================================="

# ─────────────────────────────
# 1. System Update
# ─────────────────────────────
echo "📦 System update..."
yum update -y

# ─────────────────────────────
# 2. Node.js 20 Install (via NodeSource)
# ─────────────────────────────
echo "⬇️  Installing Node.js 20..."
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

echo "✅ Node.js version: $(node --version)"
echo "✅ npm version: $(npm --version)"

# ─────────────────────────────
# 3. CloudWatch Agent Install
# (Memory metrics EC2 se push karega)
# ─────────────────────────────
echo "📊 Installing CloudWatch Agent..."
yum install -y amazon-cloudwatch-agent

# CloudWatch Agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "metrics": {
    "namespace": "AWS-Learning/EC2",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      },
      "cpu": {
        "totalcpu": true,
        "measurement": ["cpu_usage_active"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/server.log",
            "log_group_name": "/aws-learning/project-2/app",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "✅ CloudWatch Agent started!"

# ─────────────────────────────
# 4. App Directory Setup
# ─────────────────────────────
echo "📁 Setting up app directory..."
mkdir -p /var/app
mkdir -p /var/log/app

# ─────────────────────────────
# 5. App Code — S3 se download (ya seedha embed)
# ─────────────────────────────
# Option A: S3 se download (CI/CD ke baad)
# aws s3 cp s3://YOUR-DEPLOY-BUCKET/app.tar.gz /var/app/
# tar -xzf /var/app/app.tar.gz -C /var/app/

# Option B: Seedha yahan likho (quick start ke liye)
cat > /var/app/server.js << 'APPCODE'
const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

app.get('/', (req, res) => {
  res.json({
    message: '🚀 Hello from EC2!',
    hostname: os.hostname(),
    instance_id: process.env.INSTANCE_ID || 'local',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', hostname: os.hostname() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server on port ${PORT} | Host: ${os.hostname()}`);
});
APPCODE

cat > /var/app/package.json << 'PKGJSON'
{"name":"aws-p2","version":"1.0.0","main":"server.js","dependencies":{"express":"^4.18.2"}}
PKGJSON

cd /var/app
npm install --production
echo "✅ App installed!"

# ─────────────────────────────
# 6. Systemd Service — App always running rahe
# (EC2 restart ho toh bhi app auto-start ho)
# ─────────────────────────────
echo "⚙️  Creating systemd service..."

cat > /etc/systemd/system/nodeapp.service << 'SERVICE'
[Unit]
Description=Node.js AWS Learning App
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/var/app
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
StandardOutput=append:/var/log/app/server.log
StandardError=append:/var/log/app/server.log
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable nodeapp
systemctl start nodeapp

echo "✅ nodeapp service started!"
echo "✅ Status: $(systemctl is-active nodeapp)"

# ─────────────────────────────
# 7. Verify
# ─────────────────────────────
sleep 3
if curl -s http://localhost:3000/health | grep -q "healthy"; then
  echo "🎉 App is HEALTHY and running!"
else
  echo "❌ App health check failed — check /var/log/app/server.log"
fi

echo "========================================="
echo " Bootstrap Complete — $(date)"
echo "========================================="
