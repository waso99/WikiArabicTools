# ============================================
# Test-TextTranslator.ps1
# Regression tests for safe visible-text translation.
# ============================================
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Modules\WikitextParser.ps1')
. (Join-Path $root 'Modules\TextTranslator.ps1')

$env:GEMINI_API_KEY=$null
$env:GEMINI_MODEL=$null
$env:GEMINI_FALLBACK_MODEL=$null

# Seed the cache with deterministic test translations so no API call is needed.
$cachePath=Join-Path $root 'Cache\TextTranslationCache.json'
$original=if(Test-Path $cachePath){Get-Content $cachePath -Raw -Encoding UTF8}else{'{}'}
try {
    @{
        'Buccaneering Period'='فترة البوكانير'
        'Pirate Round'='جولة القراصنة'
        'Post-Spanish Succession'='ما بعد حرب الخلافة الإسبانية'
    } | ConvertTo-Json -Depth 5 | Set-Content $cachePath -Encoding UTF8

    $input = @(';Buccaneering Period','Text','<ref> ;Do not translate this</ref>','<nowiki>;Do not translate this</nowiki>',';Pirate Round') -join "`n"
    $out = Convert-WikipediaVisibleText -Text $input

    if($out -notmatch ';فترة البوكانير'){throw 'Buccaneering Period terminology is incorrect.'}
    if($out -notmatch ';جولة القراصنة'){throw 'Pirate Round terminology is incorrect.'}
    if($out -notmatch '<ref> ;Do not translate this</ref>'){throw 'Protected ref content was modified.'}
    if($out -notmatch '<nowiki>;Do not translate this</nowiki>'){throw 'Protected nowiki content was modified.'}

    Write-Host 'Visible-text regression tests passed.' -ForegroundColor Green
}
finally {
    Set-Content $cachePath -Value $original -Encoding UTF8
}
