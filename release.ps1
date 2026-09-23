# release.ps1 - pin lab.ps1/config.json to a tag and write go.txt (the short bootstrap) with lab.ps1's SHA256.
# Usage (in this repo):  .\release.ps1 -Tag v1.1
# Then commit, create tag <Tag> on that commit, push commit + tag (GitHub Desktop: History > right-click > Create Tag).
param([Parameter(Mandatory)][string]$Tag, [string]$User = 'X66CLRF', [string]$Repo = 'lab-setup')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false

# 1. point lab.ps1 (comments + config URL) at the new tag
$lab = [IO.File]::ReadAllText("$PSScriptRoot\lab.ps1")
$lab = $lab -replace "(raw\.githubusercontent\.com/$User/$Repo/)[^/]+/", "`${1}$Tag/"
[IO.File]::WriteAllText("$PSScriptRoot\lab.ps1", $lab, $utf8)

# 2. hash exactly what GitHub will serve (the committed blob, LF line endings)
git add lab.ps1 | Out-Null
$tmp = [IO.Path]::GetTempFileName()
cmd /c "git cat-file blob :lab.ps1 > `"$tmp`""
$hash = (Get-FileHash $tmp -Algorithm SHA256).Hash
Remove-Item $tmp

# 3. write the bootstrap served by GitHub Pages
$go = @"
# Lab setup bootstrap. Run in PowerShell as Administrator:
#   irm $($User.ToLower()).github.io/$Repo/go.txt | iex
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
`$u = 'https://raw.githubusercontent.com/$User/$Repo/$Tag/lab.ps1'
`$h = '$hash'
`$b = (Invoke-WebRequest `$u -UseBasicParsing).RawContentStream.ToArray()
`$got = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(`$b)) -replace '-'
if (`$got -ne `$h) { Write-Host "STOP: lab.ps1 hash mismatch (`$got). Not running." -ForegroundColor Red; return }
Invoke-Expression ([Text.Encoding]::UTF8.GetString(`$b).TrimStart([char]0xFEFF))
"@
[IO.File]::WriteAllText("$PSScriptRoot\go.txt", ($go -replace "`r`n", "`n"), $utf8)
if (-not (Test-Path "$PSScriptRoot\.nojekyll")) { [IO.File]::WriteAllText("$PSScriptRoot\.nojekyll", '', $utf8) }
git add lab.ps1 go.txt .nojekyll | Out-Null

Write-Host "Tag $Tag  lab.ps1 SHA256 $hash"
Write-Host "Next: commit, create tag '$Tag' on that commit, push commit + tag."
