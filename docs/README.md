# Documentation Index

Welcome to the Gitlab2DevOps documentation! This directory contains comprehensive guides, references, and best practices for using the migration tool.

---

## 📚 Documentation Structure

```
docs/
├── Getting Started
│   ├── quickstart.md              # 5-minute quick start
│   ├── QUICK_SETUP.md             # Detailed setup guide
│   └── cli-usage.md               # CLI automation examples
│
├── Configuration
│   ├── env-configuration.md       # Environment variables
│   └── guides/
│       ├── BULK_MIGRATION_CONFIG.md   # Bulk migration setup
│       ├── SYNC_MODE_GUIDE.md         # Sync mode usage
│       └── TEAM_PRODUCTIVITY_GUIDE.md # Team initialization
│
├── Reference
│   ├── WORK_ITEM_TEMPLATES.md     # Work item reference
│   ├── USER_EXPORT_IMPORT.md      # User import/export
│   ├── api-errors.md              # API error reference
│   └── reference/
│       ├── QUICK_REFERENCE.md     # Command quick reference
│       └── PROJECT_SUMMARY.md     # Project overview
│
└── Architecture
    ├── architecture/limitations.md # Known limitations
    └── BEST_PRACTICES_ALIGNMENT.md # Best practices
```

---

## 🚀 Quick Links

### For First-Time Users
- **[Quick Start Guide](quickstart.md)** - Get up and running in 5 minutes
- **[Installation Guide](QUICK_SETUP.md)** - Detailed setup instructions
- **[Limitations](architecture/limitations.md)** - What this tool does NOT do

### For Automation
- **[CLI Usage Guide](cli-usage.md)** - Command-line examples
- **[Bulk Migration Config](guides/BULK_MIGRATION_CONFIG.md)** - Bulk migration setup
- **[Environment Configuration](env-configuration.md)** - Environment variables

### For Team Setup
- **[Team Productivity Guide](guides/TEAM_PRODUCTIVITY_GUIDE.md)** - Initialize teams
- **[Work Item Templates](WORK_ITEM_TEMPLATES.md)** - Work item reference
- **[User Import/Export](USER_EXPORT_IMPORT.md)** - User management

### For Troubleshooting
- **[API Error Reference](api-errors.md)** - Common API errors and solutions
- **[Best Practices](BEST_PRACTICES_ALIGNMENT.md)** - Recommended approaches

---

## 📖 Documentation by Topic

### Migration Workflows

| Document | Description | Audience |
|----------|-------------|----------|
| [Quick Start](quickstart.md) | 5-minute quick start | Everyone |
| [CLI Usage](cli-usage.md) | Automation examples | DevOps Engineers |
| [Bulk Migration](guides/BULK_MIGRATION_CONFIG.md) | Multi-project migration | Administrators |

### Configuration

| Document | Description | Audience |
|----------|-------------|----------|
| [Environment Setup](env-configuration.md) | PATs, URLs, Git LFS | Administrators |
| [Bulk Config](guides/BULK_MIGRATION_CONFIG.md) | JSON configuration | DevOps Engineers |

### Team Management

| Document | Description | Audience |
|----------|-------------|----------|
| [Team Productivity](guides/TEAM_PRODUCTIVITY_GUIDE.md) | Team initialization | Team Leads |
| [Work Items](WORK_ITEM_TEMPLATES.md) | Work item templates | Product Owners |
| [User Management](USER_EXPORT_IMPORT.md) | Import/export users | Administrators |

### Reference

| Document | Description | Audience |
|----------|-------------|----------|
| [Quick Reference](reference/QUICK_REFERENCE.md) | Command cheat sheet | Everyone |
| [API Errors](api-errors.md) | Error troubleshooting | DevOps Engineers |
| [Project Summary](reference/PROJECT_SUMMARY.md) | Project overview | Developers |

### Architecture

| Document | Description | Audience |
|----------|-------------|----------|
| [Limitations](architecture/limitations.md) | What's not supported | Everyone |
| [Best Practices](BEST_PRACTICES_ALIGNMENT.md) | Recommended patterns | Developers |

---

## 🎯 Documentation by Use Case

### "I want to migrate a single project"
1. Read [Quick Start Guide](quickstart.md)
2. Configure [Environment Variables](env-configuration.md)
3. Run the migration
4. Check [Limitations](architecture/limitations.md) if issues occur

### "I want to migrate multiple projects"
1. Read [Bulk Migration Config](guides/BULK_MIGRATION_CONFIG.md)
2. Create bulk configuration JSON
3. Run bulk preparation and execution
4. Review [CLI Usage](cli-usage.md) for automation

### "I want to set up a team workspace"
1. Read [Team Productivity Guide](guides/TEAM_PRODUCTIVITY_GUIDE.md)
2. Choose team pack (Business/Dev/Security/Management)
3. Run team initialization
4. Review [Work Item Templates](WORK_ITEM_TEMPLATES.md)

### "I'm getting API errors"
1. Check [API Error Reference](api-errors.md)
2. Review [Best Practices](BEST_PRACTICES_ALIGNMENT.md)
3. Verify environment configuration
4. Check Azure DevOps/GitLab server status

### "I want to automate migrations"
1. Read [CLI Usage Guide](cli-usage.md)
2. Create configuration files
3. Set up environment variables
4. Run in automation mode with `-Mode` parameter

---

## 💡 Tips for Reading Documentation

### Icons and Conventions

- 📘 **Getting Started** - Beginner-friendly guides
- ⚙️ **Configuration** - Setup and configuration
- 🔧 **Technical** - Developer documentation
- ⚠️ **Important** - Critical information
- 💡 **Tip** - Helpful suggestions
- 🐛 **Troubleshooting** - Problem solving

### Code Examples

```powershell
# Comments explain what the code does
.\Gitlab2DevOps.ps1 -Mode Migrate -Source "group/project"
```

### Placeholders

- `{YourValue}` - Replace with your actual value
- `<required>` - Required parameter
- `[optional]` - Optional parameter

---

## 🔄 Keeping Documentation Updated

Documentation is updated with each release:

- **Version 2.1.0** (Current) - November 8, 2025
  - Self-contained folder structures
  - 43 wiki templates
  - 4 team initialization packs
  - PowerShell approved verbs

Check [CHANGELOG.md](../CHANGELOG.md) for version-specific documentation changes.

---

## 🤝 Contributing to Documentation

Found a typo? Have a suggestion? See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to contribute to documentation.

**Documentation guidelines:**
- Use clear, concise language
- Include practical examples
- Add screenshots where helpful
- Keep formatting consistent
- Update table of contents

---

## 📞 Getting Help

- **Start here**: [Quick Start Guide](quickstart.md)
- **API Issues**: [API Error Reference](api-errors.md)
- **GitHub Issues**: [Report a bug or request documentation](https://github.com/magedfarag/Gitlab2DevOps/issues)

---

<div align="center">

**Need something specific?** Check the [Quick Reference](reference/QUICK_REFERENCE.md) for a command cheat sheet.

Made with ❤️ for DevOps teams

</div>
