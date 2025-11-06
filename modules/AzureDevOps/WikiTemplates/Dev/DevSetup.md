# Development Environment Setup

Complete guide for setting up your local development environment.

## Prerequisites

### Required Software

- **Git**: Version 2.30+
  - Download: https://git-scm.com/
  - Verify: \``git --version\``

- **IDE/Editor**:
  - Visual Studio Code (recommended)
  - Visual Studio 2022
  - JetBrains Rider/IntelliJ

- **Runtime/SDK**:
  - .NET 8.0 SDK (for .NET projects)
  - Node.js 18+ LTS (for Node projects)
  - Python 3.11+ (for Python projects)
  - Docker Desktop (for containerized development)

### Optional Tools

- **Postman** or **Insomnia** (API testing)
- **Azure Data Studio** or **SQL Server Management Studio** (database)
- **Redis Desktop Manager** (cache debugging)

## Repository Setup

### 1. Clone the Repository

````````````bash
# Clone with HTTPS
git clone https://dev.azure.com/your-org/$Project/_git/$Project

# Or with SSH
git clone git@ssh.dev.azure.com:v3/your-org/$Project/$Project

cd $Project
````````````

### 2. Install Dependencies

#### For .NET Projects
````````````bash
dotnet restore
dotnet build
````````````

#### For Node.js Projects
````````````bash
npm install
# or
yarn install
````````````

#### For Python Projects
````````````bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
````````````

### 3. Configure Local Settings

````````````bash
# Copy configuration template
cp appsettings.Development.json.template appsettings.Development.json
# or
cp .env.example .env

# Edit with your local settings
code appsettings.Development.json
````````````

### 4. Database Setup

````````````bash
# Run migrations
dotnet ef database update
# or
npm run migrate
````````````

### 5. Run the Application

````````````bash
# .NET
dotnet run --project src/MyApp.Api

# Node.js
npm run dev

# Python
python manage.py runserver
````````````

## Verification

### Health Check

After starting the application, verify it's running:

````````````bash
curl http://localhost:5000/health
# Should return: {"status": "healthy"}
````````````

### Run Tests

````````````bash
# .NET
dotnet test

# Node.js
npm test

# Python
pytest
````````````

## Common Issues

### Issue: Port Already in Use

**Solution**: Change port in configuration or kill existing process
````````````bash
# Windows
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Linux/Mac
lsof -i :5000
kill -9 <PID>
````````````

### Issue: Database Connection Failed

**Solution**: Verify connection string and ensure database server is running

### Issue: SSL Certificate Errors

**Solution**: Trust development certificate
````````````bash
dotnet dev-certs https --trust
````````````

## IDE Configuration

### Visual Studio Code

**Recommended Extensions**:
- C# (for .NET)
- ESLint (for JavaScript)
- Python
- Docker
- GitLens
- Azure Repos

**Settings** (\``.vscode/settings.json\``):
````````````json
{
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true
  }
}
````````````

### Launch Configuration (\``.vscode/launch.json\``)

Configuration for debugging will be project-specific. See repository for examples.

## Getting Help

- **Wiki**: Check [Troubleshooting](/Development/Troubleshooting)
- **Team**: Ask in team chat or daily standup
- **Documentation**: See [API Documentation](/Development/API-Documentation)

---

**Next Steps**: After setup, review [Git Workflow](/Development/Git-Workflow) and [Code Review Checklist](/Development/Code-Review-Checklist).