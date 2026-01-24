# TermiScope

<div align="center">
  <img src="./web/public/logo.png" width="100" />
  <h1>TermiScope</h1>
  <p>
    <strong>Modern, Lightweight Server Management & Monitoring Platform</strong>
  </p>
  <p>
    <a href="https://go.dev/"><img src="https://img.shields.io/badge/Backend-Go-blue.svg" alt="Go"></a>
    <a href="https://vuejs.org/"><img src="https://img.shields.io/badge/Frontend-Vue3-green.svg" alt="Vue 3"></a>
    <a href="https://hub.docker.com/"><img src="https://img.shields.io/badge/Docker-Ready-blue.svg" alt="Docker"></a>
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License">
  </p>
</div>

TermiScope is a powerful, self-hosted server management tool designed simplify your DevOps workflow. It combines a fully-featured web SSH terminal with comprehensive server monitoring and network traffic management.

## ✨ Features

### 🖥️ Web Terminal
- **Full SSH Client**: Built on `xterm.js`, supporting all standard SSH interactions.
- **Theme Support**: Includes 100+ VS Code-like themes (Dracula, One Dark, Monokai, etc.) with transparent background support.
- **SFTP Integration**: Drag-and-drop file uploads/downloads via Zmodem or built-in SFTP browser.
- **Session Recording**: Automatically record sessions (`.cast` format) for audit and playback.

### 📊 Server Monitoring
- **Multi-Platform Agent**: Lightweight agents for **Linux**, **Windows**, and **macOS**.
- **Real-time Metrics**: Dashboards for CPU, RAM, Disk, and Network usage.
- **Detailed Network Stats**: Monitor per-interface Rx/Tx rates and monthly traffic usage.
- **One-Click Deploy**: Automatically deploy monitoring agents to your SSH hosts via the dashboard.

### 🚦 Traffic Management
- **Traffic Limits**: Set monthly data caps (e.g., 1TB) for your servers.
- **Billing Cycle**: Configure billing reset days (e.g., reset on the 1st of every month).
- **Visual Tracking**: Progress bars and alerts for traffic usage.

### 🔒 Security
- **Two-Factor Authentication (2FA)**: Secure your account with TOTP (Google Authenticator, Authy).
- **Encryption**: Sensitive credentials (passwords, private keys) are AES-encrypted in the database.
- **Audit Logs**: Detailed login and connection history.

---

## 🚀 Quick Start

### Manual Installation     
脚本安装:   
`curl https://raw.githubusercontent.com/ihxw/TermiScope/refs/heads/main/scripts/install.sh | bash`

手动安装:
1. 下载
Download the latest release from the [Releases](https://github.com/ihxw/TermiScope/releases) page.

1. **Unzip** the archive (`TermiScope-1.2.2-linux-amd64.tar.gz`).
1. **Run** the server:
   ```bash
   chmod +x TermiScope
   ./TermiScope
   ```

---

## 🛠️ Development

### Prerequisites
- Go 1.23+
- Node.js 20+
- PowerShell (for build scripts)

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
1. Go to the **Dashboard**.
2. Click the **Deploy Monitor** button on your SSH host card.
3. TermiScope will upload and install the agent automatically.

**Manual Deployment**:
1. Download the agent binary for your OS from the release.
2. Run it on the target machine:
   ```bash
   # Linux/macOS
   chmod +x termiscope-agent
   ./termiscope-agent -server http://YOUR_TERMISCOPE_IP:8080 -secret YOUR_AppSecret -id HOST_ID
   ```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


