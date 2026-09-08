# ============================================
# LinkTranslator.ps1
# ترجمة روابط ويكيبيديا باستخدام Wikidata
# ============================================

$script:LinkStats=[ordered]@{Total=0;Converted=0;IllWD2=0;NoWikidata=0;NoArabic=0;Ignored=0;Protected=0;SectionLinks=0;DisplayTranslated=0}
$script:UntranslatedLinks=@()

function New-ArabicWikipediaLink {
    param([Parameter(Mandatory)][string]$ArabicTitle,[string]$Section,[string]$Display)
    $target=$ArabicTitle.Trim()
    if(-not [string]::IsNullOrWhiteSpace($Section)){$target += "#$Section"}
    if([string]::IsNullOrEmpty($Display)){return "[[$target]]"}
    return "[[$target|$Display]]"
}
function Add-UntranslatedLink {
    param([Parameter(Mandatory)]$Link,[string]$QID,[Parameter(Mandatory)][string]$Reason)
    $script:UntranslatedLinks += [PSCustomObject]@{Title=$Link.Target;QID=$QID;Section=$Link.Section;Display=$Link.Display;Reason=$Reason}
}
# ============================================

function Get-DisplayTranslationMap {
    if ($null -ne $script:DisplayTranslationMapCache) { return $script:DisplayTranslationMapCache }
    $path = Join-Path $PSScriptRoot '..\Templates\DisplayTranslationMap.json'
    if (-not (Test-Path -LiteralPath $path)) { $script:DisplayTranslationMapCache = @{}; return @{} }
    try {
        $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $map = @{}
        foreach ($item in @($obj)) {
            if ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.Source)) {
                $map[[string]$item.Source] = [string]$item.Target
            }
        }
        $script:DisplayTranslationMapCache = $map
        return $map
    } catch {
        Write-Warning "Could not read DisplayTranslationMap.json: $($_.Exception.Message)"
        $script:DisplayTranslationMapCache = @{}
        return @{}
    }
}

function Get-DeterministicArabicDisplay {
    param(
        [string]$Display,
        [string]$EnglishTitle,
        [string]$ArabicTitle,
        [string]$ArabicWikidataLabel
    )

    if ([string]::IsNullOrWhiteSpace($Display)) { return $null }
    $displayTrimmed = $Display.Trim()

    $map = Get-DisplayTranslationMap
    if ($map.ContainsKey($displayTrimmed) -and -not [string]::IsNullOrWhiteSpace([string]$map[$displayTrimmed])) {
        return [string]$map[$displayTrimmed]
    }

    # If visible text exactly matches the English source title,
    # use the resolved Arabic page title or Arabic Wikidata label.
    if (-not [string]::IsNullOrWhiteSpace($EnglishTitle) -and
        [string]::Equals($displayTrimmed, $EnglishTitle.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace($ArabicTitle)) { return $ArabicTitle.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($ArabicWikidataLabel) -and $ArabicWikidataLabel -match '[\u0600-\u06FF]') {
            return $ArabicWikidataLabel.Trim()
        }
    }
    return $null
}

function Convert-WikipediaLinks {
    param([Parameter(Mandatory)][string]$Text)
    $script:LinkStats=[ordered]@{Total=0;Converted=0;IllWD2=0;NoWikidata=0;NoArabic=0;Ignored=0;Protected=0;SectionLinks=0;DisplayTranslated=0}
    $script:UntranslatedLinks=@()
    Write-Host "`nAnalyzing Wikitext..." -ForegroundColor Cyan
    $tokens=Get-WikitextTokens -Text $Text
    $links=@(Get-WikitextInternalLinks -Tokens $tokens)
    $script:LinkStats.Total=$links.Count
    Write-Host "Found $($links.Count) processable links." -ForegroundColor Gray
    if($links.Count -eq 0){return $Text}
    $uniqueTitles=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach($link in $links){[void]$uniqueTitles.Add($link.Target)}
    Write-Host "Unique titles: $($uniqueTitles.Count)" -ForegroundColor Gray
    $resolution=Resolve-WikipediaLinksBatch -EnglishTitles @($uniqueTitles)

    # For links with no Arabic Wikipedia page, retrieve the Arabic Wikidata label
    # so they can be represented with {{Ill-WD2|...|id=Q...|نص=...}}.
    $illWdLabels=@{}
    $illWdQids=[System.Collections.Generic.List[string]]::new()
    foreach($candidate in $links){
        if(-not $resolution.ContainsKey($candidate.Target)){ continue }
        $candidateResolution=$resolution[$candidate.Target]
        $candidateQid=[string]$candidateResolution.QID
        $candidateArabicTitle=[string]$candidateResolution.ArabicTitle
        if(-not [string]::IsNullOrWhiteSpace($candidateQid) -and [string]::IsNullOrWhiteSpace($candidateArabicTitle)){
            if(-not $illWdQids.Contains($candidateQid)){ [void]$illWdQids.Add($candidateQid) }
        }
    }
    if($illWdQids.Count -gt 0){
        $illWdLabels=Get-ArabicWikidataLabelsBatch -WikidataIds @($illWdQids)
        if($null -ne $script:WikidataLabelCacheStats){
            Write-Host "Arabic Wikidata labels: cache hits = $($script:WikidataLabelCacheStats.Hits) | misses = $($script:WikidataLabelCacheStats.Misses) | API requests = $($script:WikidataLabelCacheStats.ApiRequests)" -ForegroundColor DarkGray
        }
    }

    $replacements=@{}
    foreach($link in $links){
        $title=$link.Target
        if(-not $resolution.ContainsKey($title)){
            $script:LinkStats.NoWikidata++;Add-UntranslatedLink -Link $link -Reason 'لا يوجد عنصر Wikidata مرتبط بالصفحة.';continue
        }
        $qid=[string]$resolution[$title].QID
        $arabicTitle=$resolution[$title].ArabicTitle
        if([string]::IsNullOrWhiteSpace([string]$arabicTitle)){
            $script:LinkStats.NoArabic++

            # No Arabic sitelink, but an Arabic Wikidata label exists: use Ill-WD2.
            $wdLabel=$null
            if(-not [string]::IsNullOrWhiteSpace($qid) -and $illWdLabels.ContainsKey($qid)){
                $wdLabel=[string]$illWdLabels[$qid]
            }

            # Use Ill-WD2 only when Wikidata has a genuine Arabic label.
            # A non-empty label written only in Latin/other scripts is not enough.
            $hasArabicWikidataLabel = (
                -not [string]::IsNullOrWhiteSpace($wdLabel) -and
                $wdLabel -match '[\u0600-\u06FF]'
            )

            if($hasArabicWikidataLabel){
                $illTarget=$wdLabel.Trim()
                if(-not [string]::IsNullOrWhiteSpace($link.Section)){
                    $illTarget += "#$($link.Section)"
                    $script:LinkStats.SectionLinks++
                }

                $displayText=[string]$link.Display
                if(-not [string]::IsNullOrEmpty($displayText)){
                    $deterministicDisplay=Get-DeterministicArabicDisplay `
                        -Display $displayText `
                        -EnglishTitle ([string]$link.Target) `
                        -ArabicTitle $null `
                        -ArabicWikidataLabel $wdLabel
                    if(-not [string]::IsNullOrWhiteSpace([string]$deterministicDisplay)){
                        $displayText=$deterministicDisplay
                    }
                }

                if([string]::IsNullOrEmpty($displayText)){
                    $newLink="{{Ill-WD2|$illTarget|id=$qid}}"
                }
                else {
                    $newLink="{{Ill-WD2|$illTarget|id=$qid|نص=$displayText}}"
                }

                if($newLink -ne $link.Text){
                    $replacements[[int]$link.Start]=$newLink
                    $script:LinkStats.IllWD2++
                    $script:LinkStats.Converted++
                }
                continue
            }

            Add-UntranslatedLink -Link $link -QID $qid -Reason 'No Arabic Wikipedia page and no Arabic Wikidata label.'
            continue
        }
        if(-not [string]::IsNullOrWhiteSpace($link.Section)){$script:LinkStats.SectionLinks++}
        $arabicDisplay=Get-DeterministicArabicDisplay `
            -Display ([string]$link.Display) `
            -EnglishTitle ([string]$link.Target) `
            -ArabicTitle ([string]$arabicTitle) `
            -ArabicWikidataLabel $null

        $newLink=New-ArabicWikipediaLink -ArabicTitle $arabicTitle -Section $link.Section -Display $arabicDisplay

        if($newLink -eq $link.Text){continue}

        $replacements[[int]$link.Start]=$newLink
        $script:LinkStats.Converted++
    }
    Write-Host "`nRebuilding Wikitext..." -ForegroundColor Cyan
    return Rebuild-Wikitext -Text $Text -Tokens $tokens -Replacements $replacements
}
