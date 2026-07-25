# Mandala Studio — portable launcher (Windows, no Node.js required)
$ErrorActionPreference = 'Stop'
$Port = 3847
$Root = Join-Path $PSScriptRoot 'app'

if (-not (Test-Path (Join-Path $Root 'index.html'))) {
  Write-Host "ERROR: app\index.html not found." -ForegroundColor Red
  Write-Host "This folder must contain the 'app' directory from the portable package."
  Read-Host "Press Enter to exit"
  exit 1
}

# Prefer IPv4 loopback; try a few ports if busy
$listener = $null
$usedPort = $null
foreach ($tryPort in @($Port, 3848, 3849, 3850, 5173, 3000)) {
  try {
    $l = New-Object System.Net.HttpListener
    $prefix = "http://127.0.0.1:$tryPort/"
    $l.Prefixes.Add($prefix)
    $l.Start()
    $listener = $l
    $usedPort = $tryPort
    break
  } catch {
    if ($l) { try { $l.Close() } catch {} }
  }
}

if (-not $listener) {
  Write-Host "ERROR: Could not open a local port. Close other apps and try again." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

$url = "http://127.0.0.1:$usedPort/"
Write-Host "  Server: $url" -ForegroundColor Cyan
Write-Host "  Folder: $Root"
Write-Host ""
Write-Host "  Opening browser..." -ForegroundColor Green
Write-Host "  Close this window to stop Mandala Studio." -ForegroundColor Yellow
Write-Host ""

try {
  Start-Process $url
} catch {
  Write-Host "  Open this address manually: $url"
}

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.mjs'  = 'application/javascript; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.webp' = 'image/webp'
  '.ico'  = 'image/x-icon'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.ttf'  = 'font/ttf'
  '.map'  = 'application/json'
  '.txt'  = 'text/plain; charset=utf-8'
  '.wasm' = 'application/wasm'
}

$rootFull = [System.IO.Path]::GetFullPath($Root)

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
  } catch {
    break
  }

  $req = $ctx.Request
  $res = $ctx.Response

  try {
    $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($rel) -or $rel.EndsWith('/')) {
      $rel = $rel + 'index.html'
    }
    $rel = $rel -replace '/', [IO.Path]::DirectorySeparatorChar

    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
      $res.StatusCode = 403
      $buf = [Text.Encoding]::UTF8.GetBytes('Forbidden')
      $res.OutputStream.Write($buf, 0, $buf.Length)
      $res.Close()
      continue
    }

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      # SPA fallback
      $full = Join-Path $rootFull 'index.html'
    }

    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $contentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
    $bytes = [IO.File]::ReadAllBytes($full)
    $res.ContentType = $contentType
    $res.ContentLength64 = $bytes.LongLength
    $res.Headers.Add('Cache-Control', 'no-cache')
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
    try {
      $res.StatusCode = 500
      $err = [Text.Encoding]::UTF8.GetBytes("Server error: $($_.Exception.Message)")
      $res.OutputStream.Write($err, 0, $err.Length)
    } catch {}
  } finally {
    try { $res.Close() } catch {}
  }
}

try { $listener.Stop() } catch {}
try { $listener.Close() } catch {}
