# TermiScope

<div align="center">
  <img src="./web/public/logo.png" width="100" />
  <h1>TermiScope</h1>
  <p>
    <strong>Modern, Lightweight Server Management & Monitoring Platform</strong>
  </p>
  <p>
    <a href="https://go.dev/"><img src="https://img.shields.io/badge/Backend-Go_1.25+-blue.svg" alt="Go"></a>
    <a href="https://vuejs.org/"><img src="https://img.shields.io/badge/Frontend-Vue3-green.svg" alt="Vue 3"></a>
    <a href="https://hub.docker.com/"><img src="https://img.shields.io/badge/Docker-Ready-blue.svg" alt="Docker"></a>
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License">
  </p>
</div>

TermiScope is a powerful, self-hosted server management tool designed to simplify your DevOps workflow. It combines a fully-featured web SSH terminal with comprehensive server monitoring and network traffic management.

## ✨ Features / 功能特性

### 🖥️ Web Terminal (Web 终端)
- **Full SSH Client**: Built on `xterm.js`, supporting all standard SSH interactions.
- **Theme Support**: Includes 100+ VS Code-like themes (Dracula, One Dark, Monokai, etc.) with transparent background support.
- **SFTP Integration**: Drag-and-drop file uploads/downloads via Zmodem or built-in SFTP browser.
- **Session Recording**: Automatic session recording for audit and playback.

### 📊 Server Monitoring (系统监控)
- **Multi-Platform Agent**: Lightweight agents for **Linux**, **Windows**, **macOS**, and **FreeBSD**.
- **Real-time Metrics**: Dashboards for CPU, RAM, Disk, and Network usage.
- **One-Click Deploy**: Automatically deploy monitoring agents to your SSH hosts via the dashboard.
- **Batch Operations**: Bulk deploy, stop, and manage monitoring agents across hundreds of hosts.

### 📉 Network Latency Monitor (网络延迟监控)
- **Connectivity Tracking**: Monitor network latency and packet loss in real-time.
- **Multi-Protocol Support**: Support for both **ICMP Ping** and **TCP Ping** to detect network quality.
- **Visual Analytics**: Interactive charts with zoom capability and historical data playback.

### 🚦 Traffic Management (流量管理)
- **Traffic Limits**: Set monthly data caps (e.g., 1TB) for your servers.
- **Billing Cycle**: Configure billing reset days.
- **Visual Tracking**: Progress bars and alerts for traffic usage.

### 🔒 Security & Management (安全与管理)
- **Two-Factor Authentication (2FA)**: Secure your account with TOTP (Google Authenticator, Authy).
- **Role-Based Access**: Granular permission control (Admin/User).
- **Encryption**: Sensitive credentials (passwords, private keys) are AES-encrypted.
- **Audit Logs**: Detailed login and connection history.

---

## 🚀 Quick Start / 快速开始

### Installation

**Script Install (Linux/macOS):**
```bash
curl -fsSL https://raw.githubusercontent.com/ihxw/TermiScope/main/scripts/install.sh | bash
```

**Manual Install:**
1. Download the latest release from the [Releases](https://github.com/ihxw/TermiScope/releases) page.
2. **Unzip** the archive.
3. **Run** the server:
   ```bash
   # Linux/macOS
   chmod +x TermiScope
   ./TermiScope
   
   # Windows
   ./server.exe
   ```
4. Access the dashboard at `http://localhost:8080`.

---

## 🛠️ Development / 开发指南

### Prerequisites
- **Go 1.25+**
- **Node.js 20+**
- **PowerShell** (Recommended for build scripts)

### Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/ihxw/TermiScope.git
   cd TermiScope
   ```

2. **Run Development Server** (Windows):
   ```powershell
   ./dev_run.ps1
   ```
   This will start both the Go backend (port 8080) and Vue frontend (port 5173).

3. **Build Release**:
   ```powershell
   ./build_release.ps1
   ```
   Artifacts will be generated in the `release/` directory.

---

## 📦 Agent Deployment

To monitor a server, you need to install the TermiScope Agent.

**Automatic Deployment**:
1. Go to the **Dashboard** -> **Hosts**.
2. Click the **Deploy Monitor** button (or use Batch Deploy for multiple hosts).
3. TermiScope will upload and install the agent automatically via SSH.

**Manual Deployment**:
1. Download the agent binary for your OS.
2. Run it on the target machine:
   ```bash
   # Linux/macOS
   chmod +x agent
   ./agent -server http://YOUR_TERMISCOPE_IP:8080 -secret YOUR_APP_SECRET -id HOST_ID
   ```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
