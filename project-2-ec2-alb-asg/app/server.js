const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 3000;

// ─────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────
app.use(express.json());

// ─────────────────────────────────────────
// ROUTE 1: Home Page
// ─────────────────────────────────────────
app.get('/', (req, res) => {
  res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>AWS Project 2 — EC2 + ALB + ASG</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
      font-family: 'Segoe UI', sans-serif;
      background: #0a0e1a; color: #e2e8f0;
      min-height: 100vh; display: flex;
      flex-direction: column; align-items: center; justify-content: center;
    }
    .badge {
      background: linear-gradient(135deg,#ff9900,#ff6600);
      color:#fff; font-size:11px; font-weight:700;
      letter-spacing:2px; padding:6px 16px;
      border-radius:20px; text-transform:uppercase; margin-bottom:20px;
    }
    h1 { font-size:2.8rem; font-weight:800;
      background:linear-gradient(135deg,#ff9900,#fff);
      -webkit-background-clip:text; -webkit-text-fill-color:transparent;
      margin-bottom:10px;
    }
    .subtitle { color:#94a3b8; margin-bottom:30px; font-size:1rem; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr));
      gap:16px; max-width:700px; width:100%; margin-bottom:24px;
    }
    .card {
      background:#111827; border:1px solid #1e293b;
      border-radius:12px; padding:20px;
    }
    .card h3 { color:#ff9900; font-size:0.8rem; text-transform:uppercase;
      letter-spacing:1px; margin-bottom:10px;
    }
    .card p { font-family:monospace; font-size:0.85rem; color:#cbd5e1; line-height:1.8; }
    .card .val { color:#4ade80; font-weight:bold; }
    .alb-banner {
      background:#0a1628; border:1px solid #1e3a5f;
      border-radius:12px; padding:20px 30px;
      max-width:700px; width:100%; margin-bottom:20px;
      text-align:center; font-family:monospace; font-size:0.85rem;
    }
    .alb-banner .flow { color:#38bdf8; line-height:2.2; }
    .alb-banner .arrow { color:#4ade80; }
    footer { color:#334155; font-size:0.75rem; margin-top:10px; }
    .ping { display:inline-block; width:8px; height:8px;
      background:#4ade80; border-radius:50%; margin-right:6px;
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0%,100% { opacity:1; } 50% { opacity:0.3; }
    }
  </style>
</head>
<body>

  <div class="badge">🖥️ AWS Project 2 — EC2 + ALB + ASG</div>
  <h1>Running on EC2!</h1>
  <p class="subtitle">
    <span class="ping"></span>
    Node.js · Express · Amazon EC2 · Auto Scaling · ALB
  </p>

  <!-- ALB Flow -->
  <div class="alb-banner">
    <div class="flow">
      <span style="color:#ff9900">Internet</span>
      <span class="arrow"> ──► </span>
      <span style="color:#ff9900">ALB</span>
      <span style="color:#64748b"> (Load Balancer)</span>
      <span class="arrow"> ──► </span>
      <span style="color:#4ade80">THIS EC2</span>
      <span style="color:#64748b"> (one of many!)</span>
    </div>
    <div style="color:#64748b; font-size:0.75rem; margin-top:8px;">
      ALB automatically routes traffic to healthy EC2 instances
    </div>
  </div>

  <!-- Server Info Cards -->
  <div class="grid">
    <div class="card">
      <h3>🖥️ This EC2 Instance</h3>
      <p>
        Hostname: <span class="val">${os.hostname()}</span><br/>
        Platform: <span class="val">${os.platform()}</span><br/>
        Arch:     <span class="val">${os.arch()}</span><br/>
        CPUs:     <span class="val">${os.cpus().length} cores</span>
      </p>
    </div>
    <div class="card">
      <h3>💾 Memory (Live)</h3>
      <p>
        Total: <span class="val">${(os.totalmem()/1024/1024/1024).toFixed(1)} GB</span><br/>
        Free:  <span class="val">${(os.freemem()/1024/1024/1024).toFixed(2)} GB</span><br/>
        Used:  <span class="val">${((1-(os.freemem()/os.totalmem()))*100).toFixed(1)}%</span><br/>
        Uptime:<span class="val"> ${Math.floor(os.uptime()/60)} mins</span>
      </p>
    </div>
    <div class="card">
      <h3>🌐 Request Info</h3>
      <p>
        IP:      <span class="val">${req.ip || req.socket.remoteAddress}</span><br/>
        Method:  <span class="val">${req.method}</span><br/>
        Path:    <span class="val">${req.path}</span><br/>
        Time:    <span class="val">${new Date().toLocaleTimeString()}</span>
      </p>
    </div>
    <div class="card">
      <h3>⚙️ App Info</h3>
      <p>
        Node.js: <span class="val">${process.version}</span><br/>
        PID:     <span class="val">${process.pid}</span><br/>
        Port:    <span class="val">${PORT}</span><br/>
        Env:     <span class="val">${process.env.NODE_ENV || 'production'}</span>
      </p>
    </div>
  </div>

  <footer>AWS Learning Series · Project 2 of 6 · EC2 + ALB + ASG</footer>
</body>
</html>
  `);
});

// ─────────────────────────────────────────
// ROUTE 2: Health Check (ALB use karta hai)
// ALB ye endpoint hit karta hai — agar 200 aaya → EC2 healthy!
// ─────────────────────────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    hostname: os.hostname(),
    uptime: os.uptime(),
    timestamp: new Date().toISOString(),
    memory: {
      total: os.totalmem(),
      free: os.freemem(),
      usedPercent: ((1 - os.freemem() / os.totalmem()) * 100).toFixed(1)
    }
  });
});

// ─────────────────────────────────────────
// ROUTE 3: Simulate CPU Load (ASG test!)
// Ye route CPU spike karta hai → ASG trigger hoga → naya EC2 aayega
// ─────────────────────────────────────────
app.get('/stress', (req, res) => {
  const seconds = parseInt(req.query.seconds) || 30;
  const end = Date.now() + (seconds * 1000);

  // CPU busy loop
  while (Date.now() < end) {
    Math.sqrt(Math.random() * 999999);
  }

  res.json({
    message: `CPU stressed for ${seconds} seconds!`,
    hostname: os.hostname(),
    tip: 'Check CloudWatch → CPU spike dikhega! ASG scale-out trigger hoga!'
  });
});

// ─────────────────────────────────────────
// ROUTE 4: Instance Metadata (EC2 info)
// ─────────────────────────────────────────
app.get('/info', (req, res) => {
  res.json({
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
    cpus: os.cpus().length,
    memory: {
      totalGB: (os.totalmem() / 1024 / 1024 / 1024).toFixed(2),
      freeGB: (os.freemem() / 1024 / 1024 / 1024).toFixed(2),
      usedPercent: ((1 - os.freemem() / os.totalmem()) * 100).toFixed(1)
    },
    process: {
      pid: process.pid,
      nodeVersion: process.version,
      uptime: process.uptime()
    },
    timestamp: new Date().toISOString()
  });
});

// ─────────────────────────────────────────
// START SERVER
// ─────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server running on port ${PORT}`);
  console.log(`🖥️  Hostname: ${os.hostname()}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
});
