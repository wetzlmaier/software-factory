# Installiert die Factory-Skills einmalig global für Antigravity ($HOME\.gemini\config\skills).
# Aufruf: .\scripts\install-local-skills.ps1
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Sources = @(
  (Join-Path $Root "local-skills"),
  (Join-Path $Root "workflows\starter-kit\skills")
)

function Install-SkillsTo {
  param([Parameter(Mandatory = $true)][string]$Dest)

  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  $stamp = Get-Date -Format "yyyyMMddHHmmss"

  foreach ($src in $Sources) {
    if (-not (Test-Path $src)) { continue }
    Get-ChildItem -Path $src -Directory | ForEach-Object {
      $name = $_.Name
      $sourcePath = $_.FullName
      $targetPath = Join-Path $Dest $name

      if (Test-Path $targetPath) {
        $item = Get-Item $targetPath -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
          Remove-Item $targetPath -Force
        } else {
          Move-Item $targetPath "$targetPath.backup-$stamp"
          Write-Host "  vorhandenen Skill '$name' in $Dest gesichert"
        }
      }

      try {
        New-Item -ItemType Junction -Path $targetPath -Target $sourcePath | Out-Null
      } catch {
        Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
      }
      Write-Host "  OK $targetPath"
    }
  }
}

$GeminiSkills = Join-Path $HOME ".gemini\config\skills"
Write-Host "Installiere Factory-Skills für Antigravity ($GeminiSkills):"
Install-SkillsTo -Dest $GeminiSkills

$ClaudeDir = Join-Path $HOME ".claude"
if (Test-Path $ClaudeDir) {
  $ClaudeSkills = Join-Path $ClaudeDir "skills"
  Write-Host "Verlinke Factory-Skills zusätzlich für Claude ($ClaudeSkills):"
  Install-SkillsTo -Dest $ClaudeSkills
}

Write-Host "Fertig. Die Skills stehen in jedem Antigravity-Projekt zur Verfügung."
