# Exit codes: 0 = available, 10 = running Flutter frontend, 20 = unavailable.
$ErrorActionPreference = 'Stop'
$frontendPort = 51168
try {
    $listeners = @(Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq $frontendPort })
    if ($listeners.Count -eq 0) { exit 0 }

    foreach ($listener in $listeners) {
        $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
        if ($listenerProcess.CommandLine -notmatch 'flutter_tools\.snapshot["\s]+run\s' -or
            $listenerProcess.CommandLine -notmatch '--web-port(?:=|\s+)51168(?:\s|$)') {
            Write-Host 'Another program is using port 51168. No processes were stopped.'
            exit 20
        }
    }

    $response = Invoke-WebRequest 'http://localhost:51168/' -UseBasicParsing -TimeoutSec 8
    if ($response.StatusCode -eq 200) {
        Write-Host 'The Flutter application is already running.'
        exit 10
    }
    exit 20
} catch {
    Write-Host 'Could not verify the local frontend. No second copy was started.'
    exit 20
}
