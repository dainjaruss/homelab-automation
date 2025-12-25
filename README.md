# Home Lab Automation

## 🏠 Overview

This repository contains automation workflows and scripts for managing a home lab infrastructure running on **ollivanders.home** (192.168.1.142). The project migrates traditional cron-based automation to [n8n](https://n8n.io/), a powerful workflow automation tool, enabling better monitoring, notification handling, and maintainability.

## 🎯 Project Goals

- **Replace cron jobs** with visual, maintainable n8n workflows
- **Centralized monitoring** via Uptime Kuma integration
- **Proactive notifications** through Telegram
- **Version-controlled automation** with Git
- **Iterative migration** to minimize disruption

## 🖥️ Infrastructure

| Component | Details |
|-----------|--------|
| **Server** | ollivanders.home (192.168.1.142) |
| **OS** | Red Hat Enterprise Linux 10.1 (Coughlan) |
| **Architecture** | x86_64, Intel i9-13900HK, 46.56 GB RAM |
| **Services** | Plex, Sonarr, Radarr, Overseerr, Tautulli, Uptime Kuma |
| **Remote Host** | 192.168.4.99 (dainja) - Sabnzbd |

## 📊 Current Status: Phase 1

### ✅ Phase 1: Container Health Monitoring (Active)

**Status:** In Development

**What's Included:**
- n8n installation with PostgreSQL backend
- Container health check workflow (replaces `check_media_containers.sh`)
- Monitors: Plex, Sonarr, Radarr, Overseerr, Tautulli
- Runs every 5 minutes
- Integrations:
  - ✅ Uptime Kuma push API
  - ✅ Telegram notifications on failures
- Complete setup documentation for beginners

**Files:**
- `n8n/docker-compose.yml` - n8n stack configuration
- `n8n/.env.example` - Environment variable template
- `workflows/container-health-check.json` - Health check workflow
- `docs/PHASE1_SETUP_GUIDE.md` - Step-by-step setup instructions

## 🚀 Quick Start

If you're new to Git and n8n, follow the comprehensive guide:

👉 **[Phase 1 Setup Guide](docs/PHASE1_SETUP_GUIDE.md)**

For experienced users:

```bash
# 1. Clone this repository
git clone <your-repo-url>
cd homelab-automation

# 2. Set up n8n
cd n8n
cp .env.example .env
# Edit .env with your credentials
nano .env

# 3. Start n8n
docker compose up -d

# 4. Access n8n at http://192.168.1.142:5678
# 5. Import workflow from workflows/container-health-check.json
# 6. Configure credentials (SSH, Telegram)
# 7. Activate workflow
```

## 📁 Repository Structure

```
homelab-automation/
├── README.md                          # This file
├── scripts/                           # Legacy shell scripts
│   ├── backup_media_stack.sh          # Weekly backup (Phase 2)
│   ├── check_media_containers.sh      # Container checks (migrated in Phase 1)
│   └── docker_weekly_pull.sh          # Docker updates (Phase 3)
├── n8n/                               # n8n configuration
│   ├── docker-compose.yml             # n8n + PostgreSQL setup
│   └── .env.example                   # Environment template
├── workflows/                         # n8n workflows (JSON exports)
│   └── container-health-check.json    # Phase 1: Health monitoring
└── docs/                              # Documentation
    └── PHASE1_SETUP_GUIDE.md          # Complete Phase 1 guide
```

## 🗺️ Migration Roadmap

### Phase 1: Container Health Checks (Current) ✨
- **Script:** `check_media_containers.sh`
- **Schedule:** Every 5 minutes
- **Complexity:** Low - Single host, simple checks
- **Status:** In Development

### Phase 2: Media Stack Backups (Planned)
- **Script:** `backup_media_stack.sh`
- **Schedule:** Weekly (Sundays at midnight)
- **Complexity:** Medium - Multi-host, requires downtime coordination
- **Enhancements:**
  - Backup verification
  - Remote backup rotation
  - Failure notifications with details

### Phase 3: Docker Image Updates (Planned)
- **Script:** `docker_weekly_pull.sh`
- **Schedule:** Weekly (Sundays at 2 AM)
- **Complexity:** Medium - Multi-host, version tracking
- **Enhancements:**
  - Image version tracking
  - Changelog notifications
  - Rollback capability

### Phase 4: Advanced Features (Future)
- Resource monitoring (CPU, disk, memory)
- Certificate expiration tracking
- Automatic issue remediation
- Dashboard creation

## 🛠️ Technologies Used

- **[n8n](https://n8n.io/)** - Workflow automation platform
- **[Docker](https://www.docker.com/)** - Container runtime
- **[PostgreSQL](https://www.postgresql.org/)** - Database for n8n
- **[Uptime Kuma](https://github.com/louislam/uptime-kuma)** - Monitoring platform
- **[Telegram](https://telegram.org/)** - Notification service
- **Bash** - Shell scripting (legacy/reference)

## 📚 Documentation

- [Phase 1 Setup Guide](docs/PHASE1_SETUP_GUIDE.md) - Complete beginner-friendly setup
- [n8n Official Docs](https://docs.n8n.io/) - n8n documentation
- [Docker Compose Reference](https://docs.docker.com/compose/) - Docker Compose docs

## 🤝 Contributing

This is a personal home lab project, but feel free to:
- Open issues for bugs or suggestions
- Submit pull requests for improvements
- Use this as a template for your own home lab automation

## 📝 License

MIT License - Feel free to use and modify for your own home lab.

## 🙏 Acknowledgments

- [n8n community](https://community.n8n.io/) for workflow inspiration
- [Uptime Kuma](https://github.com/louislam/uptime-kuma) for excellent monitoring
- Home lab community for shared knowledge

---

**Last Updated:** December 2024  
**Maintainer:** Home Lab Administrator  
**Server:** ollivanders.home (192.168.1.142)
