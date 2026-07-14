<#
.SYNOPSIS
  Dump a complete inventory of the metrics, logs, and traces flowing into a
  ClickStack (HyperDX + ClickHouse) install, so the dashboards can be tailored
  to exactly what THIS environment emits.

.DESCRIPTION
  Enumerates, straight from ClickHouse:
    - every metric name (gauge / sum / histogram) with point counts
    - log severities (text + number) and top log/resource attribute keys
    - trace services, span kinds, status codes, top span names, and
      span/resource attribute keys

  Two ways to reach ClickHouse (pick whichever works in your environment):

    1. kubectl exec (DEFAULT - no port-forward needed). The script finds the
       ClickHouse pod automatically and runs clickhouse-client inside it using
       the in-cluster 'default' user (no password).

    2. HTTP - set CH_URL (e.g. http://localhost:8123 via
       `kubectl port-forward svc/<clickhouse-headless> 8123:8123`). Optionally
       set CH_USER / CH_PASSWORD.

  The result is written to a single text file (default: inventory.txt) that you
  can hand back for dashboard tailoring.

.PARAMETER LookbackHours
  How far back to look. Default 24. Use a bigger window for low-traffic envs.

.PARAMETER Namespace
  Kubernetes namespace of the ClickHouse pod. Auto-detected if omitted.

.PARAMETER Pod
  ClickHouse pod name. Auto-detected if omitted.

.PARAMETER Database
  ClickHouse database holding the otel_* tables. Default 'default'.

.PARAMETER OutFile
  Output file path. Default 'inventory.txt' in the current directory.

.PARAMETER TopAttrs
  Max attribute keys to list per category. Default 60.

.PARAMETER TopSpanNames
  Max span names to list. Default 50.

.EXAMPLE
  ./inventory.ps1
  # auto-discovers the ClickHouse pod and writes inventory.txt

.EXAMPLE
  $env:CH_URL = "http://localhost:8123"; ./inventory.ps1 -LookbackHours 72
  # uses a port-forwarded ClickHouse over HTTP instead of kubectl exec
#>
[CmdletBinding()]
param(
  [int]$LookbackHours = 24,
  [string]$Namespace,
  [string]$Pod,
  [string]$Database = "default",
  [string]$OutFile = "inventory.txt",
  [int]$TopAttrs = 60,
  [int]$TopSpanNames = 50
)

$ErrorActionPreference = "Stop"

$ChUrl      = $env:CH_URL
$ChUser     = if ($env:CH_USER)     { $env:CH_USER }     else { "default" }
$ChPassword = if ($env:CH_PASSWORD) { $env:CH_PASSWORD } else { "" }
$useHttp    = [bool]$ChUrl

# ----- ClickHouse query helpers ---------------------------------------------

function Invoke-ChHttp([string]$sql) {
  $headers = @{ "X-ClickHouse-User" = $ChUser }
  if ($ChPassword) { $headers["X-ClickHouse-Key"] = $ChPassword }
  $uri = ($ChUrl.TrimEnd('/')) + "/?database=$Database"
  return Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $sql
}

function Invoke-ChExec([string]$sql) {
  # clickhouse-client inside the pod; -d selects the database
  $out = kubectl exec -n $Namespace $Pod -- clickhouse-client -d $Database -q $sql 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($out | Out-String) }
  return ($out | Out-String)
}

function Query([string]$sql) {
  if ($useHttp) { return (Invoke-ChHttp $sql) } else { return (Invoke-ChExec $sql) }
}

# ----- Locate ClickHouse pod (kubectl exec mode) ----------------------------

if (-not $useHttp) {
  if (-not $Pod) {
    Write-Host "Locating ClickHouse pod ..." -ForegroundColor Cyan
    $lines = kubectl get pods -A --no-headers 2>&1 | Out-String
    $match = $lines -split "`r?`n" | Where-Object {
      $_ -match "clickhouse" -and $_ -notmatch "operator" -and $_ -match "Running"
    } | Select-Object -First 1
    if (-not $match) {
      throw "Could not find a running ClickHouse pod. Specify -Namespace/-Pod, or set CH_URL for HTTP mode."
    }
    $cols = ($match -split "\s+") | Where-Object { $_ -ne "" }
    if (-not $Namespace) { $Namespace = $cols[0] }
    $Pod = $cols[1]
    Write-Host "  Using pod '$Pod' in namespace '$Namespace'." -ForegroundColor Green
  } elseif (-not $Namespace) {
    throw "-Pod specified without -Namespace. Provide both."
  }
}

$srcDesc = if ($useHttp) { "HTTP $ChUrl (db=$Database, user=$ChUser)" } else { "kubectl exec $Namespace/$Pod (db=$Database)" }
$tsMetric = "TimeUnix >= now() - INTERVAL $LookbackHours HOUR"
$tsSignal = "Timestamp >= now() - INTERVAL $LookbackHours HOUR"

# ----- Build the report ------------------------------------------------------

$sb = New-Object System.Text.StringBuilder
function Line([string]$s = "") { [void]$sb.AppendLine($s) }
function Section([string]$title) { Line ""; Line "==================================================================="; Line $title; Line "===================================================================" }

Line "ClickStack telemetry inventory"
Line "Generated : $(Get-Date -Format o)"
Line "Source    : $srcDesc"
Line "Lookback  : ${LookbackHours}h"

Write-Host "Enumerating metrics ..." -ForegroundColor Cyan
Section "METRICS"
foreach ($t in @("gauge","sum","histogram")) {
  $table = "otel_metrics_$t"
  Line ""
  Line "--- $table ---"
  try {
    $sql = "SELECT MetricName, count() AS points FROM $table WHERE $tsMetric GROUP BY MetricName ORDER BY MetricName FORMAT TabSeparated"
    $res = (Query $sql).TrimEnd()
    if ($res) {
      foreach ($row in ($res -split "`r?`n")) {
        $p = $row -split "`t"
        Line ("  {0,-55} {1,12}" -f $p[0], $p[1])
      }
      $n = ($res -split "`r?`n").Count
      Line "  ($n metric names)"
    } else { Line "  (none in window)" }
  } catch { Line "  ERROR: $($_.Exception.Message)" }
}

Write-Host "Enumerating logs ..." -ForegroundColor Cyan
Section "LOGS"
Line ""
Line "--- severities (SeverityText / SeverityNumber / count) ---"
try {
  $sql = "SELECT SeverityText, SeverityNumber, count() AS c FROM otel_logs WHERE $tsSignal GROUP BY SeverityText, SeverityNumber ORDER BY SeverityNumber, SeverityText FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-16} num={1,-4} {2,14}" -f ($(if($p[0]){$p[0]}else{'(empty)'})), $p[1], $p[2]) } }
  else { Line "  (no logs in window)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- top services by log volume ---"
try {
  $sql = "SELECT ServiceName, count() AS c FROM otel_logs WHERE $tsSignal GROUP BY ServiceName ORDER BY c DESC LIMIT 40 FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-45} {1,14}" -f ($(if($p[0]){$p[0]}else{'(empty)'})), $p[1]) } }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- log attribute keys (LogAttributes) ---"
try {
  $sql = "SELECT DISTINCT arrayJoin(mapKeys(LogAttributes)) AS k FROM otel_logs WHERE $tsSignal ORDER BY k LIMIT $TopAttrs FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($k in ($res -split "`r?`n")) { Line "  $k" } } else { Line "  (none)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- log resource attribute keys (ResourceAttributes) ---"
try {
  $sql = "SELECT DISTINCT arrayJoin(mapKeys(ResourceAttributes)) AS k FROM otel_logs WHERE $tsSignal ORDER BY k LIMIT $TopAttrs FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($k in ($res -split "`r?`n")) { Line "  $k" } } else { Line "  (none)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Write-Host "Enumerating traces ..." -ForegroundColor Cyan
Section "TRACES"
Line ""
Line "--- services x span kind x status (count) ---"
try {
  $sql = "SELECT ServiceName, SpanKind, StatusCode, count() AS c FROM otel_traces WHERE $tsSignal GROUP BY ServiceName, SpanKind, StatusCode ORDER BY c DESC LIMIT 100 FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-30} {1,-10} {2,-8} {3,12}" -f $p[0], $p[1], $p[2], $p[3]) } }
  else { Line "  (no traces in window - no spans are flowing)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- span kinds present ---"
try {
  $sql = "SELECT SpanKind, count() AS c FROM otel_traces WHERE $tsSignal GROUP BY SpanKind ORDER BY c DESC FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-12} {1,14}" -f ($(if($p[0]){$p[0]}else{'(empty)'})), $p[1]) } }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- status codes present ---"
try {
  $sql = "SELECT StatusCode, count() AS c FROM otel_traces WHERE $tsSignal GROUP BY StatusCode ORDER BY c DESC FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-12} {1,14}" -f ($(if($p[0]){$p[0]}else{'(empty)'})), $p[1]) } }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- top span names ---"
try {
  $sql = "SELECT SpanName, count() AS c FROM otel_traces WHERE $tsSignal GROUP BY SpanName ORDER BY c DESC LIMIT $TopSpanNames FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($row in ($res -split "`r?`n")) { $p = $row -split "`t"; Line ("  {0,-55} {1,12}" -f $p[0], $p[1]) } }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- span attribute keys (SpanAttributes) ---"
try {
  $sql = "SELECT DISTINCT arrayJoin(mapKeys(SpanAttributes)) AS k FROM otel_traces WHERE $tsSignal ORDER BY k LIMIT $TopAttrs FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($k in ($res -split "`r?`n")) { Line "  $k" } } else { Line "  (none)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

Line ""
Line "--- trace resource attribute keys (ResourceAttributes) ---"
try {
  $sql = "SELECT DISTINCT arrayJoin(mapKeys(ResourceAttributes)) AS k FROM otel_traces WHERE $tsSignal ORDER BY k LIMIT $TopAttrs FORMAT TabSeparated"
  $res = (Query $sql).TrimEnd()
  if ($res) { foreach ($k in ($res -split "`r?`n")) { Line "  $k" } } else { Line "  (none)" }
} catch { Line "  ERROR: $($_.Exception.Message)" }

# ----- Write file ------------------------------------------------------------

$text = $sb.ToString()
$outPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location) $OutFile }
[System.IO.File]::WriteAllText($outPath, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "Wrote inventory to: $OutFile" -ForegroundColor Green
Write-Host "Share that file back to tailor the dashboards to this environment." -ForegroundColor Green
