# Troubleshooting Guide

Common issues and solutions for development, deployment, and runtime problems.

## Table of Contents

1. [Development Environment](#development-environment)
2. [Build Issues](#build-issues)
3. [Runtime Errors](#runtime-errors)
4. [Database Problems](#database-problems)
5. [Authentication Issues](#authentication-issues)
6. [Performance Problems](#performance-problems)
7. [Git Issues](#git-issues)

---

## Development Environment

### Issue: IDE Not Recognizing Project

**Symptoms**: IntelliSense not working, red squiggles everywhere

**Solutions**:

1. **Reload Project**
   ````````````bash
   # VS Code
   Ctrl+Shift+P → "Developer: Reload Window"
   
   # Visual Studio
   File → Close Solution, then reopen
   ````````````

2. **Clear Cache**
   ````````````bash
   # .NET
   dotnet clean
   dotnet restore
   
   # Node.js
   rm -rf node_modules package-lock.json
   npm install
   ````````````

3. **Check SDK Version**
   ````````````bash
   dotnet --version
   node --version
   ````````````

### Issue: Port Already in Use

**Symptoms**: Cannot start application, "Address already in use"

**Solutions**:

**Windows**:
````````````powershell
# Find process using port 5000
netstat -ano | findstr :5000

# Kill process
taskkill /PID <PID> /F
````````````

**Linux/Mac**:
````````````bash
# Find process
lsof -i :5000

# Kill process
kill -9 <PID>
````````````

**Or Change Port**:
- Edit \``appsettings.Development.json\`` or \``.env\``
- Set different port number

---

## Build Issues

### Issue: Build Failed with Compilation Errors

**Symptoms**: "CS0246: Type or namespace not found"

**Solutions**:

1. **Restore Dependencies**
   ````````````bash
   dotnet restore
   ````````````

2. **Clean and Rebuild**
   ````````````bash
   dotnet clean
   dotnet build
   ````````````

3. **Check NuGet Cache**
   ````````````bash
   dotnet nuget locals all --clear
   ````````````

### Issue: Missing Dependencies

**Symptoms**: Module not found, package missing

**Solutions**:

**For .NET**:
````````````bash
dotnet restore
````````````

**For Node.js**:
````````````bash
npm install
# If issues persist
rm -rf node_modules package-lock.json
npm install
````````````

**For Python**:
````````````bash
pip install -r requirements.txt
````````````

### Issue: Build Succeeds Locally but Fails in CI

**Symptoms**: CI build fails with errors not seen locally

**Common Causes**:
- Different SDK versions
- Missing environment variables
- Case-sensitive file paths (Windows vs Linux)
- Uncommitted files

**Solutions**:

1. **Check CI Logs**: Read full build output
2. **Match SDK Version**: Use same version as CI
3. **Test in Container**: 
   ````````````bash
   docker build -t test .
   ````````````

---

## Runtime Errors

### Issue: Null Reference Exception

**Symptoms**: \``NullReferenceException\`` or \``Cannot read property of undefined\``

**Solutions**:

1. **Add Null Checks**:
   ````````````csharp
   if (user == null)
       throw new ArgumentNullException(nameof(user));
   
   // Or use null-conditional
   var email = user?.Email ?? "unknown";
   ````````````

2. **Check Configuration**: Ensure all required settings exist

3. **Debug**: Add breakpoint before exception, inspect values

### Issue: Timeout Exception

**Symptoms**: Request times out, "Operation timed out"

**Solutions**:

1. **Check Network**: Verify service is reachable
   ````````````bash
   ping <hostname>
   telnet <hostname> <port>
   ````````````

2. **Increase Timeout**:
   ````````````csharp
   httpClient.Timeout = TimeSpan.FromSeconds(60);
   ````````````

3. **Optimize Query**: If database timeout, check query performance

### Issue: Out of Memory

**Symptoms**: \``OutOfMemoryException\``, application crashes

**Solutions**:

1. **Identify Memory Leak**:
   - Use memory profiler (dotMemory, Chrome DevTools)
   - Check for event handlers not unsubscribed
   - Look for large collections kept in memory

2. **Implement Pagination**: Don't load all data at once

3. **Dispose Resources**:
   ````````````csharp
   using (var connection = new SqlConnection(...))
   {
       // Use connection
   } // Automatically disposed
   ````````````

---

## Database Problems

### Issue: Connection String Invalid

**Symptoms**: "Cannot connect to database", authentication failed

**Solutions**:

1. **Verify Connection String**:
   ````````````json
   "ConnectionStrings": {
     "Default": "Server=localhost;Database=MyDb;User Id=sa;Password=YourPassword;TrustServerCertificate=true"
   }
   ````````````

2. **Test Connection**:
   - Use SQL Server Management Studio
   - Or Azure Data Studio
   - Verify server, database, credentials

3. **Check Firewall**: Ensure port 1433 (SQL) is open

### Issue: Migration Failed

**Symptoms**: "Migration ... failed to apply"

**Solutions**:

1. **Check Migration History**:
   ````````````bash
   dotnet ef migrations list
   ````````````

2. **Remove Failed Migration**:
   ````````````bash
   dotnet ef database update <last-good-migration>
   dotnet ef migrations remove
   ````````````

3. **Recreate Migration**:
   ````````````bash
   dotnet ef migrations add <MigrationName>
   dotnet ef database update
   ````````````

### Issue: Slow Query Performance

**Symptoms**: Query takes > 5 seconds, application slow

**Solutions**:

1. **Enable Query Logging**:
   ````````````csharp
   options.UseSqlServer(connectionString)
       .LogTo(Console.WriteLine, LogLevel.Information);
   ````````````

2. **Analyze Query Plan**: Look for table scans

3. **Add Indexes**:
   ````````````sql
   CREATE INDEX IX_Users_Email ON Users(Email);
   ````````````

4. **Use Eager Loading**:
   ````````````csharp
   var users = context.Users
       .Include(u => u.Orders)  // Avoid N+1
       .ToList();
   ````````````

---

## Authentication Issues

### Issue: Token Expired

**Symptoms**: "401 Unauthorized" on API calls

**Solutions**:

1. **Refresh Token**: Implement token refresh flow

2. **Check Token Expiry**:
   ````````````javascript
   const token = jwt_decode(accessToken);
   if (token.exp < Date.now() / 1000) {
       // Token expired, refresh
   }
   ````````````

3. **Verify Token Config**: Ensure expiry time is reasonable

### Issue: CORS Error

**Symptoms**: "Access blocked by CORS policy"

**Solutions**:

1. **Configure CORS** (server-side):
   ````````````csharp
   services.AddCors(options =>
   {
       options.AddPolicy("AllowDevClient",
           builder => builder
               .WithOrigins("http://localhost:3000")
               .AllowAnyHeader()
               .AllowAnyMethod());
   });
   ````````````

2. **Use Proxy** (development):
   ````````````json
   // package.json
   "proxy": "http://localhost:5000"
   ````````````

---

## Performance Problems

### Issue: Application Slow

**Symptoms**: High response times, poor user experience

**Debugging Steps**:

1. **Profile Application**:
   - Use Application Insights
   - Check logs for slow operations
   - Use performance profiler

2. **Check Common Causes**:
   - Database N+1 queries
   - Synchronous I/O on hot path
   - Large JSON serialization
   - Missing caching

3. **Add Logging**:
   ````````````csharp
   var stopwatch = Stopwatch.StartNew();
   // Operation
   stopwatch.Stop();
   _logger.LogInformation("Operation took {Ms}ms", stopwatch.ElapsedMilliseconds);
   ````````````

### Issue: High CPU Usage

**Solutions**:

1. **Profile CPU**: Use profiler to find hot paths

2. **Check for Infinite Loops**

3. **Optimize Algorithms**: O(n²) → O(n log n)

4. **Add Caching**: Cache expensive computations

---

## Git Issues

### Issue: Merge Conflict

**Symptoms**: "CONFLICT: Merge conflict in..."

**Solutions**:

1. **Abort and Start Over**:
   ````````````bash
   git merge --abort
   # or
   git rebase --abort
   ````````````

2. **Resolve Manually**:
   - Open conflicted file
   - Look for \``<<<<<<\``, \``======\``, \``>>>>>>\``
   - Edit to keep desired changes
   - Remove markers
   - \``git add <file>\``
   - \``git commit\`` or \``git rebase --continue\``

3. **Use Merge Tool**:
   ````````````bash
   git mergetool
   ````````````

### Issue: Accidentally Committed Secrets

**Solutions**:

1. **Remove from History** (if not pushed):
   ````````````bash
   git reset --soft HEAD~1
   # Edit files to remove secrets
   git add .
   git commit
   ````````````

2. **If Already Pushed**:
   - ⚠️ **ROTATE SECRETS IMMEDIATELY**
   - Use BFG Repo-Cleaner or git-filter-branch
   - Force push (coordinate with team)

3. **Prevention**: Use \``.gitignore\`` and pre-commit hooks

---

## Getting Help

### Before Asking for Help

1. ✅ **Search Documentation**: Check wiki and README
2. ✅ **Search Previous Issues**: Someone may have solved it
3. ✅ **Try Debugging**: Add logs, breakpoints
4. ✅ **Isolate Problem**: Minimal reproduction case

### When Asking for Help

**Provide**:
- Clear description of problem
- Steps to reproduce
- Expected vs actual behavior
- Error messages (full stack trace)
- Environment (OS, SDK version, etc.)
- What you've tried

**Template**:
````````````
Problem: Application crashes on startup

Environment:
- OS: Windows 11
- .NET SDK: 8.0.100
- IDE: VS Code 1.85

Steps to reproduce:
1. Clone repository
2. Run: dotnet run
3. Application crashes

Error:
System.NullReferenceException at Startup.cs:42

What I've tried:
- Cleared bin/obj folders
- Restored packages
- Checked connection string

Stack trace:
[paste full stack trace]
````````````

### Escalation Path

1. **Team Chat**: Quick questions
2. **Team Member**: Pair programming session
3. **Tech Lead**: Architectural questions
4. **External**: Stack Overflow, GitHub issues

---

**Remember**: Every issue is a learning opportunity! Document solutions you find for others.

---

## 📚 References

- [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Debugging in Visual Studio](https://learn.microsoft.com/en-us/visualstudio/debugger/)
- [Chrome DevTools](https://developer.chrome.com/docs/devtools/)
- [Troubleshooting .NET Applications](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/)
- [SQL Server Troubleshooting](https://learn.microsoft.com/en-us/sql/relational-databases/performance/performance-monitoring-and-tuning-tools)