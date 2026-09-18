# Troubleshooting

Check status:

```powershell
.\bin\status-monitor.ps1
```

Run foreground debug mode:

```powershell
.\bin\start-monitor.ps1 -Foreground
```

Check local errors:

```powershell
Get-Content .\data\state\monitor-errors.log -Tail 50
```

If status shows stopped but PID is stale, run:

```powershell
.\bin\start-monitor.ps1
```

Reset monitor data:

```powershell
.\bin\reset-data.ps1 -ConfirmReset
```
