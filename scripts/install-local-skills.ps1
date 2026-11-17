# Installiert die lokalen Factory-Skills (init, write-spec, to-factory) einmalig global für Antigravity ($HOME\.gemini\config\skills).
# Aufruf: .\scripts\install-local-skills.ps1
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Src = Join-Path $Root "local-skills"
$Dest = Join-Path $HOME ".gemini\config\skills"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$stamp = Get-Date -Format "yyyyMMddHHmmss"

Get-ChildItem -Path $Src -Directory | ForEach-Object {
  $name = $_.Name
  $sourcePath = $_.FullName
  $targetPath = Join-Path $Dest $name

  if (Test-Path $targetPath) {
    $item = Get-Item $targetPath -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      Remove-Item $targetPath -Force
    } else {
      Move-Item $targetPath "$targetPath.backup-$stamp"
      Write-Host "  vorhandenen Skill '$name' gesichert"
    }
  }

  try {
    New-Item -ItemType Junction -Path $targetPath -Target $sourcePath | Out-Null
  } catch {
    Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
  }
  Write-Host "  OK /$name"
}

Write-Host "Fertig. Die Skills stehen in jedem Antigravity-Projekt zur Verfügung."
