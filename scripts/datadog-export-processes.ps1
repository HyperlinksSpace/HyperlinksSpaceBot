# Requires user env: DD_API_KEY, DD_APP_KEY (Datadog org keys).
# Fetches all pages from GET /api/v2/processes for host SRAIBABY, then writes unique cmdlines to repo root dd-processes-sample.txt
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

if (-not $env:DD_API_KEY -or -not $env:DD_APP_KEY) {
    Write-Error 'Set DD_API_KEY and DD_APP_KEY (user env or this session).'
}

$base = 'https://api.datadoghq.com/api/v2/processes'
$hostTag = 'host:SRAIBABY'
$pageLimit = 100
$maxPages = 500

$headers = @{
    'DD-API-KEY'         = $env:DD_API_KEY
    'DD-APPLICATION-KEY' = $env:DD_APP_KEY
    'Accept'             = 'application/json'
}

$allCmdlines = New-Object System.Collections.Generic.List[string]
$cursor = $null
$pageNum = 0

do {
    $pageNum++
    if ($pageNum -gt $maxPages) {
        Write-Error "Stopped after $maxPages pages (safety cap)."
    }

    $tagsEnc = [uri]::EscapeDataString($hostTag)
    if ($null -eq $cursor -or $cursor -eq '') {
        $uri = "${base}?page%5Blimit%5D=${pageLimit}&tags=${tagsEnc}"
    }
    else {
        $curEnc = [uri]::EscapeDataString($cursor)
        $uri = "${base}?page%5Blimit%5D=${pageLimit}&tags=${tagsEnc}&page%5Bcursor%5D=${curEnc}"
    }

    $r = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    if (-not $r.data -or $r.data.Count -eq 0) {
        Write-Host "Page ${pageNum}: 0 rows, stopping."
        break
    }

    $n = 0
    if ($r.data) {
        foreach ($row in $r.data) {
            $cmd = $row.attributes.cmdline
            if ($null -ne $cmd -and $cmd -ne '') {
                [void]$allCmdlines.Add($cmd)
                $n++
            }
        }
    }

    $cursor = $null
    if ($null -ne $r.meta -and $null -ne $r.meta.page -and $null -ne $r.meta.page.after -and $r.meta.page.after -ne '') {
        $cursor = $r.meta.page.after
    }
    Write-Host "Page ${pageNum}: $($r.data.Count) rows ($n cmdlines), next=$([bool]$cursor)"
} while ($cursor)

$unique = $allCmdlines | Sort-Object -Unique
$out = Join-Path (Get-Location) 'dd-processes-sample.txt'
$unique | Set-Content -Encoding utf8 $out

Write-Host "Wrote $out - total rows: $($allCmdlines.Count), unique cmdlines: $($unique.Count), pages: $pageNum"
