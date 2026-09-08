# ============================================
# Test-ArabicSitelinkResponse.ps1
# ============================================

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Modules\Wikidata.ps1')

$arrayMock = @([pscustomobject]@{
    id = 'Q123'
    sitelinks = [pscustomobject]@{ arwiki = [pscustomobject]@{ title = 'عنوان عربي' } }
})

$objectMock = [pscustomobject]@{
    Q123 = [pscustomobject]@{
        id = 'Q123'
        sitelinks = [pscustomobject]@{ arwiki = [pscustomobject]@{ title = 'عنوان عربي' } }
    }
    Q456 = [pscustomobject]@{ id = 'Q456'; sitelinks = [pscustomobject]@{} }
}

foreach($shape in @($arrayMock, $objectMock)) {
    $items = @(Get-WikidataEntitiesCollection -Entities $shape)
    $found = $false
    foreach($entity in $items){
        if([string]$entity.id -eq 'Q123' -and [string]$entity.sitelinks.arwiki.title -eq 'عنوان عربي'){ $found = $true }
    }
    if(-not $found){ throw 'Arabic sitelink response parsing regression test failed for one of the supported response shapes.' }
}

Write-Host 'Arabic sitelink response regression tests passed.'
