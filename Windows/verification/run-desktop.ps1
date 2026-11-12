param([ValidateSet('dotnet','tauri')][string]$Target = 'dotnet', [switch]$DesktopWorker, [switch]$Cleanup)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$evidence = Join-Path $root "Windows\artifacts\$Target-live"
New-Item -ItemType Directory -Force $evidence | Out-Null
if (!$DesktopWorker) {
    if ($Cleanup) {
        # Registering over SSH can create a task that the limited desktop token
        # cannot delete. Cleanup runs with the original launcher's authority.
        Get-ScheduledTask | Where-Object {
            $_.TaskName -like "AppReveal-$Target-verification-*" -and
            ($_.Actions.Arguments -like "*$PSCommandPath*")
        } | ForEach-Object {
            if ($_.State -eq 'Running') { throw "Verification task is still running: $($_.TaskName)" }
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
        }
        Remove-Item (Join-Path $evidence 'task-name.txt') -ErrorAction SilentlyContinue
        return
    }
    # SSH/session 0 is not a usable desktop. Run only this fixture in the existing user's session.
    $taskName = "AppReveal-$Target-verification-$PID"
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $evidence /inheritance:r /grant:r "${user}:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect verification session files' }
    Remove-Item (Join-Path $evidence 'exit-code.txt') -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute (Get-Command pwsh.exe).Source -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Target $Target -DesktopWorker"
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
    # Record the exact task for bounded launcher cleanup.
    Set-Content (Join-Path $evidence 'task-name.txt') $taskName
    Start-ScheduledTask $taskName
    Write-Output "Started $taskName; results: $evidence"
    $deadline = [DateTime]::UtcNow.AddSeconds(55)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Test-Path (Join-Path $evidence 'exit-code.txt')) -and (Get-ScheduledTask -TaskName $taskName).State -ne 'Running') {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Remove-Item (Join-Path $evidence 'task-name.txt') -ErrorAction SilentlyContinue
            return
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Output "Worker still running; inspect results, then rerun with -Target $Target -Cleanup after it exits."
    return
}
$exitCode = 1
$hostProcess = $null
try {
    if ($Target -eq 'dotnet') {
        & (Join-Path $root 'Windows\verification\dotnet\bin\Debug\net8.0-windows\WindowsVerification.exe') --ui *> (Join-Path $evidence 'checks.log')
        $exitCode = $LASTEXITCODE
    } else {
        $sessionFile = Join-Path $evidence 'session.private'
        Remove-Item $sessionFile -ErrorAction SilentlyContinue
        $env:APPREVEAL_VERIFICATION_SESSION = $sessionFile
        $hostProcess = Start-Process (Join-Path $root 'Windows\appreveal-tauri\target\debug\appreveal-windows-verification.exe') -PassThru -RedirectStandardOutput (Join-Path $evidence 'host.log') -RedirectStandardError (Join-Path $evidence 'host-error.log')
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        while (!(Test-Path $sessionFile) -and [DateTime]::UtcNow -lt $deadline -and !$hostProcess.HasExited) { Start-Sleep -Milliseconds 250 }
        if (!(Test-Path $sessionFile)) { throw 'Tauri host did not create a session' }
        Start-Sleep -Seconds 2
        & (Join-Path $PSScriptRoot 'tauri-http.ps1') -SessionFile $sessionFile *> (Join-Path $evidence 'checks.log')
        $exitCode = 0
    }
} catch {
    # Do not serialize a PowerShell request object containing the session URL.
    Add-Content (Join-Path $evidence 'checks.log') ("FAIL " + $_.Exception.Message)
} finally {
    if ($hostProcess -and !$hostProcess.HasExited) { Stop-Process -Id $hostProcess.Id }
    Remove-Item (Join-Path $evidence 'session.private') -ErrorAction SilentlyContinue
    Set-Content (Join-Path $evidence 'exit-code.txt') $exitCode

}
exit $exitCode
