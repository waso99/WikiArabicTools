#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipApiKeyPrompt
)

$ErrorActionPreference = 'Stop'

# NOTE: If this script is blocked by an AllSigned execution policy, run SETUP.cmd
# instead. SETUP.cmd starts this script with a Process-scoped Bypass, without
# changing the user's or system-wide execution policy.

$ProjectRoot = $PSScriptRoot
$VersionFile = Join-Path $ProjectRoot 'VERSION.txt'
$Version = if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw -Encoding UTF8).Trim() } else { 'unknown' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '                 WikiArabicTools Setup' -ForegroundColor Cyan
Write-Host "                         v$Version" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# Show the effective execution policy for diagnostics. The setup does not change
# the user's or system-wide execution policy.
try {
    $effectivePolicy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if ($effectivePolicy -eq 'AllSigned') {
        Write-Host 'Execution Policy: AllSigned' -ForegroundColor Yellow
        Write-Host 'This script is normally started through SETUP.cmd when AllSigned blocks unsigned scripts.' -ForegroundColor Yellow
    }
} catch {}

# Check PowerShell edition/version.
$major = $PSVersionTable.PSVersion.Major
if ($major -lt 5) {
    throw 'PowerShell 5.1 or newer is required.'
}
Write-Host "PowerShell: $($PSVersionTable.PSVersion) [$($PSVersionTable.PSEdition)]" -ForegroundColor Green

# Create required directories.
foreach ($dir in @('Modules','Cache')) {
    $path = Join-Path $ProjectRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Created: $dir\" -ForegroundColor Green
    }
}

# Ensure the project scripts are not blocked after extraction/download.
Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object {
        try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {}
    }

# Check UTF-8 BOM on PowerShell scripts. Windows PowerShell 5.1 is most reliable with BOM.
$badEncoding = @()
Get-ChildItem -Path $ProjectRoot -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        $badEncoding += $_.FullName
    }
}
if ($badEncoding.Count -gt 0) {
    Write-Warning 'The following PowerShell files do not have a UTF-8 BOM:'
    $badEncoding | ForEach-Object { Write-Warning "  $_" }
    Write-Warning 'This can cause encoding/parser issues in Windows PowerShell 5.1.'
} else {
    Write-Host 'PowerShell script encoding: UTF-8 BOM OK' -ForegroundColor Green
}

# Verify core files.
$required = @(
    'WikiArabicTools.ps1',
    'Modules\WikitextParser.ps1',
    'Modules\WikipediaFetcher.ps1',
    'Modules\Wikidata.ps1',
    'Modules\LinkTranslator.ps1',
    'Cache\WikidataCache.json',
    'Cache\GeminiDisplayCache.json',
    'input.wiki'
)
$missing = @($required | Where-Object { -not (Test-Path (Join-Path $ProjectRoot $_)) })
if ($missing.Count -gt 0) {
    Write-Warning 'Missing project files:'
    $missing | ForEach-Object { Write-Warning "  $_" }
} else {
    Write-Host 'Core project files: OK' -ForegroundColor Green
}

# API key is intentionally NOT stored in this release package.
$apiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY','Process')
if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY','User') }
if ([string]::IsNullOrWhiteSpace($apiKey)) { $apiKey = [Environment]::GetEnvironmentVariable('GEMINI_API_KEY','Machine') }

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host ''
    Write-Host 'GEMINI_API_KEY: not configured' -ForegroundColor Yellow
    Write-Host 'Gemini is optional. Wikidata/Wikipedia processing can still run where applicable.' -ForegroundColor DarkGray

    if (-not $SkipApiKeyPrompt) {
        $answer = Read-Host 'Set GEMINI_API_KEY now for your Windows user? [Y/N]'
        if ($answer -match '^(Y|y)$') {
            $secure = Read-Host 'Enter your Gemini API key' -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                if ([string]::IsNullOrWhiteSpace($plain)) {
                    Write-Warning 'No key entered. GEMINI_API_KEY was not changed.'
                } else {
                    [Environment]::SetEnvironmentVariable('GEMINI_API_KEY',$plain,'User')
                    $env:GEMINI_API_KEY = $plain
                    Write-Host 'GEMINI_API_KEY: configured for the current Windows user.' -ForegroundColor Green
                    Write-Host 'The key is not written to any project file.' -ForegroundColor DarkGray
                }
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                Remove-Variable plain -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    Write-Host 'GEMINI_API_KEY: configured' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Setup completed.' -ForegroundColor Green
Write-Host ''
Write-Host 'Run the tool from this folder:' -ForegroundColor Cyan
Write-Host '  .\WikiArabicTools.ps1' -ForegroundColor White
Write-Host ''
Write-Host 'If your execution policy is AllSigned, use the supplied launcher:' -ForegroundColor Yellow
Write-Host '  .\RUN.cmd' -ForegroundColor White
Write-Host ''
Write-Host 'Examples:' -ForegroundColor Cyan
Write-Host '  .\WikiArabicTools.ps1 -Title "Dutch Revolt"' -ForegroundColor White
Write-Host '  .\WikiArabicTools.ps1 -Url "https://en.wikipedia.org/wiki/Dutch_Revolt"' -ForegroundColor White
Write-Host ''
Write-Host 'Important: if you set the API key in Setup, it is stored as a User environment variable.' -ForegroundColor DarkGray
Write-Host 'Open a new PowerShell window if another application does not see the new variable yet.' -ForegroundColor DarkGray
Write-Host ''
