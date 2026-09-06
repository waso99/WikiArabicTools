# ============================================
# Wikidata.ps1
# Wikidata / Wikipedia API
# Batch + Cache + Error Handling
# ============================================


# ============================================
# المسارات
# ============================================

$CacheDirectory =
    Join-Path `
        $PSScriptRoot `
        "..\Cache"

$CacheFile =
    Join-Path `
        $CacheDirectory `
        "WikidataCache.json"


if (-not (Test-Path $CacheDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $CacheDirectory |
        Out-Null
}


# ============================================
# تحميل Cache
# ============================================

if (Test-Path $CacheFile) {

    try {

        $content =
            Get-Content `
                -Path $CacheFile `
                -Raw `
                -Encoding UTF8

        if (
            [string]::IsNullOrWhiteSpace($content)
        ) {

            $script:WikidataCache =
                [PSCustomObject]@{}
        }
        else {

            $script:WikidataCache =
                $content |
                ConvertFrom-Json
        }
    }
    catch {

        Write-Warning `
            "تعذر قراءة Cache. سيتم إنشاء Cache جديد."

        $script:WikidataCache =
            [PSCustomObject]@{}
    }
}
else {

    $script:WikidataCache =
        [PSCustomObject]@{}
}


# ============================================
# حالة API
# ============================================

$script:ApiStats = [ordered]@{

    WikipediaRequests =
        0

    WikidataRequests =
        0

    SuccessfulRequests =
        0

    FailedRequests =
        0
}


# ============================================
# إعدادات API
# ============================================

$script:ApiSettings = @{

    MaxRetries =
        4

    RetryDelaySeconds =
        10

    BatchSize =
        50

    MinRequestIntervalSeconds =
        3
}


# ============================================
# حفظ Cache
# ============================================

function Save-WikidataCache {

    $script:WikidataCache |
        ConvertTo-Json -Depth 10 |
        Set-Content `
            -Path $CacheFile `
            -Encoding UTF8
}


# ============================================
# إضافة / تحديث Cache
# ============================================

function Set-WikidataCacheValue {

    param(

        [Parameter(Mandatory)]
        [string]$Key,

        [AllowNull()]
        [string]$Value
    )

    $script:WikidataCache |
        Add-Member `
            -NotePropertyName $Key `
            -NotePropertyValue $Value `
            -Force
}


# ============================================
# فحص Cache
# ============================================

function Test-WikidataCache {

    param(

        [Parameter(Mandatory)]
        [string]$Key
    )

    return (
        $null -ne
        $script:WikidataCache.PSObject.Properties[$Key]
    )
}


# ============================================
# تقسيم العناصر إلى دفعات
# ============================================

function Split-IntoBatches {

    param(

        [Parameter(Mandatory)]
        [array]$Items,

        [int]$BatchSize = 50
    )

    # تحويل صريح إلى Array
    # لتجنب سلوك List / IEnumerable في PowerShell

    $Items =
        @($Items)

    for (
        $i = 0;
        $i -lt $Items.Count;
        $i += $BatchSize
    ) {

        $end =
            [Math]::Min(
                $i + $BatchSize - 1,
                $Items.Count - 1
            )

        ,@(
            $Items[
                $i..$end
            ]
        )
    }
}


# ============================================
# تنفيذ طلب API مع إعادة المحاولة
# ============================================

function Invoke-WikiApiRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)]
        [ValidateSet("Wikipedia","Wikidata")]
        [string]$ApiName
    )

    $maxRetries = [int]$script:ApiSettings.MaxRetries
    $baseDelay = [int]$script:ApiSettings.RetryDelaySeconds
    $minInterval = [double]$script:ApiSettings.MinRequestIntervalSeconds

    if($null -ne $script:LastApiRequestTime){
        $elapsed = ((Get-Date) - $script:LastApiRequestTime).TotalSeconds
        $remaining = $minInterval - $elapsed
        if($remaining -gt 0){
            Start-Sleep -Milliseconds ([int]($remaining * 1000))
        }
    }

    for($attempt=1; $attempt -le $maxRetries; $attempt++){
        try {
            if($ApiName -eq "Wikipedia"){
                $script:ApiStats.WikipediaRequests++
            } else {
                $script:ApiStats.WikidataRequests++
            }

            $script:LastApiRequestTime = Get-Date

            return Invoke-RestMethod `
                -Uri $Uri `
                -Method Get `
                -Headers @{
                    "User-Agent" = "WikiArabicTools/1.0.0 (Wikipedia link translation tool)"
                    "Accept" = "application/json"
                } `
                -ErrorAction Stop
        }
        catch {
            $message = $_.Exception.Message
            $isRateLimit = $message -match "429|Too Many Requests"

            if($isRateLimit -and $attempt -lt $maxRetries){
                $retryAfter = $null

                try {
                    $response = $_.Exception.Response
                    if($null -ne $response){
                        $headerValue = $response.Headers["Retry-After"]
                        if(-not [string]::IsNullOrWhiteSpace([string]$headerValue)){
                            $seconds = 0
                            if([int]::TryParse([string]$headerValue, [ref]$seconds)){
                                $retryAfter = $seconds
                            }
                        }
                    }
                } catch {}

                if($null -eq $retryAfter){
                    $retryAfter = [int][Math]::Min(
                        $baseDelay * [Math]::Pow(2,$attempt-1), 120
                    )
                }

                Write-Warning "Rate limit reached for $ApiName API."
                Write-Warning "Retrying after $retryAfter ثانية... ($attempt/$maxRetries)"
                Start-Sleep -Seconds $retryAfter
                $script:LastApiRequestTime = Get-Date
                continue
            }

            $script:ApiStats.FailedRequests++

            if($isRateLimit){
                Write-Warning "Rate limit exceeded for $ApiName API after $maxRetries attempts."
            } else {
                Write-Warning "Connection to $ApiName API."
                Write-Warning "Reason: $message"
            }

            return $null
        }
    }

    return $null
}

# ============================================
# Wikipedia API
# الحصول على QIDs
# ============================================

function Get-WikidataEntityIdsBatch {

    param(
        [Parameter(Mandatory)]
        [array]$EnglishTitles
    )

    $result = @{}
    $EnglishTitles = @($EnglishTitles)
    $batchSize = [int]$script:ApiSettings.BatchSize

    for ($i = 0; $i -lt $EnglishTitles.Count; $i += $batchSize) {

        $end = [Math]::Min(
            $i + $batchSize - 1,
            $EnglishTitles.Count - 1
        )

        $batch = @($EnglishTitles[$i..$end])
        $titles = $batch -join "|"
        $encodedTitles = [System.Uri]::EscapeDataString($titles)

        $url =
            "https://en.wikipedia.org/w/api.php?action=query&prop=pageprops&ppprop=wikibase_item&titles=$encodedTitles&format=json&formatversion=2"

        $response = Invoke-WikiApiRequest -Uri $url -ApiName "Wikipedia"

        if ($null -eq $response) {
            continue
        }

        $script:ApiStats.SuccessfulRequests++

        foreach ($page in $response.query.pages) {
            if ($page.pageprops.wikibase_item) {
                $result[$page.title] = $page.pageprops.wikibase_item
            }
        }
    }

    return $result
}


# ============================================
# Wikidata API
# الحصول على عناوين ويكيبيديا العربية
# ============================================

function Get-ArabicWikipediaTitlesBatch {

    param(
        [Parameter(Mandatory)]
        [array]$WikidataIds
    )

    $result = @{}
    $WikidataIds = @($WikidataIds)
    $batchSize = [int]$script:ApiSettings.BatchSize

    for ($i = 0; $i -lt $WikidataIds.Count; $i += $batchSize) {

        $end = [Math]::Min(
            $i + $batchSize - 1,
            $WikidataIds.Count - 1
        )

        $batch = @($WikidataIds[$i..$end])
        $ids = $batch -join "|"
        $encodedIds = [System.Uri]::EscapeDataString($ids)

        $url =
            "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$encodedIds&props=sitelinks&sitefilter=arwiki&format=json&formatversion=2"

        $response = Invoke-WikiApiRequest -Uri $url -ApiName "Wikidata"

        if ($null -eq $response) {
            continue
        }

        $script:ApiStats.SuccessfulRequests++

        foreach ($property in $response.entities.PSObject.Properties) {

            $entity = $property.Value

            if (
                $null -ne $entity.sitelinks -and
                $null -ne $entity.sitelinks.arwiki -and
                -not [string]::IsNullOrWhiteSpace(
                    $entity.sitelinks.arwiki.title
                )
            ) {
                $result[$entity.id] = $entity.sitelinks.arwiki.title
            }
        }
    }

    return $result
}


# ============================================
# الحصول على التسمية العربية من Wikidata
# لا تُستخدم إلا للكيانات التي لا تملك صفحة arwiki.
# ============================================
function Get-ArabicWikidataLabelsBatch {
    param(
        [Parameter(Mandatory)]
        [array]$WikidataIds
    )

    $result = @{}
    $ids = @($WikidataIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($ids.Count -eq 0) { return $result }

    # Use local cache first. Empty values are negative-cache hits.
    $idsToQuery = [System.Collections.Generic.List[string]]::new()
    $cacheHits = 0

    foreach ($qid in $ids) {
        $key = "arlabel:$qid"
        if (Test-WikidataCache -Key $key) {
            $cacheHits++
            $cached = $script:WikidataCache.PSObject.Properties[$key].Value
            if (-not [string]::IsNullOrWhiteSpace([string]$cached)) {
                $result[[string]$qid] = [string]$cached
            }
        }
        else {
            [void]$idsToQuery.Add([string]$qid)
        }
    }

    $script:WikidataLabelCacheStats = [ordered]@{
        Hits = $cacheHits
        Misses = $idsToQuery.Count
        ApiRequests = 0
    }

    if ($idsToQuery.Count -eq 0) { return $result }

    $batchSize = 50
    for ($start = 0; $start -lt $idsToQuery.Count; $start += $batchSize) {
        $count = [Math]::Min($batchSize, $idsToQuery.Count - $start)
        $batch = @($idsToQuery[$start..($start + $count - 1)])
        $encodedIds = [uri]::EscapeDataString(($batch -join '|'))
        $url = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$encodedIds&props=labels&languages=ar&languagefallback=0&format=json&formatversion=2"

        $response = Invoke-WikiApiRequest -Uri $url -ApiName "Wikidata"
        $script:WikidataLabelCacheStats.ApiRequests++
        if ($null -eq $response) { continue }
        $script:ApiStats.SuccessfulRequests++

        foreach ($qid in $batch) {
            $label = $null
            $entityProp = $response.entities.PSObject.Properties[[string]$qid]
            if ($null -ne $entityProp) {
                $entity = $entityProp.Value
                if ($null -ne $entity.labels -and $null -ne $entity.labels.ar) {
                    $label = [string]$entity.labels.ar.value
                }
            }

            # Cache both positive and negative results.
            Set-WikidataCacheValue -Key "arlabel:$qid" -Value $label
            if (-not [string]::IsNullOrWhiteSpace($label)) {
                $result[[string]$qid] = $label
            }
        }
    }

    Save-WikidataCache
    return $result
}


function Resolve-WikipediaLinksBatch {

    param(

        [Parameter(Mandatory)]
        [array]$EnglishTitles
    )


    $resolved = @{}


    if (
        $EnglishTitles.Count -eq 0
    ) {

        return $resolved
    }


    # ========================================
    # تحويل الإدخال إلى Array
    # ========================================

    $EnglishTitles =
        @($EnglishTitles)


    # ========================================
    # قراءة QID من Cache
    # ========================================

    $titlesToQuery =
        [System.Collections.Generic.List[string]]::new()


    $cacheQidHits =
        0

    $cacheQidMisses =
        0


    foreach (
        $title in $EnglishTitles
    ) {

        $qidKey =
            "qid:$title"


        if (
            Test-WikidataCache `
                -Key $qidKey
        ) {

            $cacheQidHits++


            $qid =
                $script:WikidataCache.PSObject.Properties[
                    $qidKey
                ].Value


            $resolved[$title] = @{
                QID = $qid
            }
        }
        else {

            $cacheQidMisses++


            $titlesToQuery.Add(
                $title
            )
        }
    }


    # ========================================
    # جلب QIDs من Wikipedia
    # ========================================

    if (
        $titlesToQuery.Count -gt 0
    ) {

        Write-Host `
            "روابط جديدة تحتاج Wikidata: $($titlesToQuery.Count)" `
            -ForegroundColor Cyan


        $qidResults =
            Get-WikidataEntityIdsBatch `
                -EnglishTitles @(
                    $titlesToQuery.ToArray()
                )


        foreach (
            $title in $titlesToQuery
        ) {

            $qid =
                $null


            if (
                $qidResults.ContainsKey(
                    $title
                )
            ) {

                $qid =
                    $qidResults[$title]
            }


            Set-WikidataCacheValue `
                -Key "qid:$title" `
                -Value $qid


            $resolved[$title] = @{
                QID = $qid
            }
        }


        Save-WikidataCache
    }


    # ========================================
    # arwiki Cache
    # ========================================

    $qidsToQuery =
        [System.Collections.Generic.List[string]]::new()


    $cacheArabicHits =
        0

    $cacheArabicMisses =
        0


    foreach (
        $title in $resolved.Keys
    ) {

        $qid =
            $resolved[$title].QID


        if (
            [string]::IsNullOrWhiteSpace(
                [string]$qid
            )
        ) {

            continue
        }


        $arKey =
            "arwiki:$qid"


        if (
            Test-WikidataCache `
                -Key $arKey
        ) {

            $cachedArabicTitle =
                [string]$script:WikidataCache.PSObject.Properties[
                    $arKey
                ].Value


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $cachedArabicTitle
                )
            ) {

                # Cache يحتوي على نتيجة صحيحة

                $cacheArabicHits++


                $resolved[$title].ArabicTitle =
                    $cachedArabicTitle
            }
            else {

                # Negative Cache:
                # القيمة الفارغة تعني أن Wikidata فُحص سابقًا
                # ولم توجد صفحة مقابلة في ويكيبيديا العربية.
                # لا نعيد الطلب في كل تشغيل.

                $cacheArabicHits++
                $resolved[$title].ArabicTitle = $null
            }
        }
        else {

            # لا توجد نتيجة في Cache

            $cacheArabicMisses++


            if (
                -not $qidsToQuery.Contains(
                    [string]$qid
                )
            ) {

                $qidsToQuery.Add(
                    [string]$qid
                )
            }
        }
    }


    # ========================================
    # جلب الصفحات العربية
    # ========================================

    if (
        $qidsToQuery.Count -gt 0
    ) {

        Write-Host `
            "كيانات جديدة تحتاج arwiki: $($qidsToQuery.Count)" `
            -ForegroundColor Cyan


        # تحويل List إلى Array صراحةً
        # لمنع إنشاء دفعة لكل عنصر

        $qidsArray =
            @(
                $qidsToQuery.ToArray()
            )


        Write-Host `
            "عدد QIDs المرسلة إلى Wikidata: $($qidsArray.Count)" `
            -ForegroundColor Gray


        $arabicResults =
            Get-ArabicWikipediaTitlesBatch `
                -WikidataIds $qidsArray


        foreach (
            $qid in $qidsArray
        ) {

            $arabicTitle =
                $null


            if (
                $arabicResults.ContainsKey(
                    $qid
                )
            ) {

                $arabicTitle =
                    $arabicResults[$qid]
            }


            Set-WikidataCacheValue `
                -Key "arwiki:$qid" `
                -Value $arabicTitle
        }


        Save-WikidataCache
    }


    # ========================================
    # تحديث النتائج
    # ========================================

    foreach (
        $title in $resolved.Keys
    ) {

        $qid =
            $resolved[$title].QID


        if (
            [string]::IsNullOrWhiteSpace(
                [string]$qid
            )
        ) {

            continue
        }


        $arKey =
            "arwiki:$qid"


        if (
            Test-WikidataCache `
                -Key $arKey
        ) {

            $arabicTitle =
                [string]$script:WikidataCache.PSObject.Properties[
                    $arKey
                ].Value


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $arabicTitle
                )
            ) {

                $resolved[$title].ArabicTitle =
                    $arabicTitle
            }
        }
    }


    # ========================================
    # معلومات إضافية للإحصائيات
    # ========================================

    $script:CacheStats = [ordered]@{

        QidHits =
            $cacheQidHits

        QidMisses =
            $cacheQidMisses

        ArabicHits =
            $cacheArabicHits

        ArabicMisses =
            $cacheArabicMisses
    }


    return $resolved
}