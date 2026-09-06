# ============================================
# WikipediaFetcher.ps1
# جلب Wikitext من Wikipedia API
# ============================================

function Get-WikipediaTitleFromUrl {
    param([Parameter(Mandatory)][string]$Url)
    try {
        $uri=[System.Uri]$Url
    } catch { throw "رابط ويكيبيديا غير صالح: $Url" }
    $segments=$uri.AbsolutePath.Trim('/').Split('/')
    $wikiIndex=[Array]::IndexOf($segments,'wiki')
    if ($wikiIndex -lt 0 -or $wikiIndex -ge ($segments.Count-1)) { throw "تعذر استخراج عنوان المقال من الرابط: $Url" }
    return [System.Uri]::UnescapeDataString($segments[$wikiIndex+1]).Replace('_',' ')
}

function Get-WikipediaWikitext {
    param([Parameter(Mandatory)][string]$Title)
    $encoded=[System.Uri]::EscapeDataString($Title)
    $url="https://en.wikipedia.org/w/api.php?action=query&redirects=1&prop=revisions&rvprop=content&rvslots=main&titles=$encoded&format=json&formatversion=2"
    try {
        $response=Invoke-RestMethod -Uri $url -Method Get -Headers @{ 'User-Agent'='WikiArabicTools/1.0.0 (local tool)' } -ErrorAction Stop
    } catch { throw "فشل جلب المقال من Wikipedia API: $($_.Exception.Message)" }
    if ($response.query -and $response.query.redirects) {
        foreach ($redirect in $response.query.redirects) {
            Write-Host "Redirect: $($redirect.from) -> $($redirect.to)" -ForegroundColor DarkGray
        }
    }
    $page=$response.query.pages | Select-Object -First 1
    if (-not $page -or $page.missing) { throw "لم يFound Article: $Title" }
    $content=$page.revisions[0].slots.main.content
    if ($null -eq $content) { throw "تعذر الحصول على Wikitext للمقال: $($page.title)" }
    [PSCustomObject]@{ Title=$page.title; PageId=$page.pageid; Wikitext=$content }
}
