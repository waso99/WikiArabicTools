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

            $versionFile = Join-Path $PSScriptRoot '..\VERSION.txt'
            $version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim() } else { 'unknown' }

            return Invoke-RestMethod `
                -Uri $Uri `
                -Method Get `
                -Headers @{
                    "User-Agent" = "WikiArabicTools/$version (Wikipedia link translation tool; https://github.com/waso99/WikiArabicTools)"
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

function Get-BatchSlice {
    param([Parameter(Mandatory)][object[]]$Items,[Parameter(Mandatory)][int]$Start,[Parameter(Mandatory)][int]$BatchSize)
    $end = [Math]::Min($Start+$BatchSize-1,$Items.Count-1)
    return [object[]]$Items[$Start..$end]
}

# Success maps prevent failed API calls from becoming negative cache entries.
$script:LastWikipediaTitleSuccess = @{}
$script:LastArabicSitelinkSuccess = @{}

function Get-WikidataEntitiesCollection {
    param([Parameter(Mandatory)]$Entities)
    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Entities) { return @() }

    # Wikidata API responses can deserialize in PowerShell either as an array
    # of entity objects or as an object whose properties are QIDs. Support both.
    if ($Entities -is [System.Array] -or $Entities -is [System.Collections.IEnumerable] -and
        $Entities -isnot [string] -and $Entities.PSObject.Properties.Count -eq 0) {
        foreach ($entity in @($Entities)) { if ($null -ne $entity) { $items.Add($entity) } }
        return $items.ToArray()
    }

    $props = @($Entities.PSObject.Properties)
    if ($props.Count -gt 0) {
        foreach ($prop in $props) {
            if ($null -ne $prop.Value) { $items.Add($prop.Value) }
        }
        return $items.ToArray()
    }

    return @($Entities)
}

function Get-ArabicWikipediaTitlesBatch {
    param([Parameter(Mandatory)][array]$WikidataIds)
    $result = @{}
    $script:LastArabicSitelinkSuccess = @{}
    $items = [object[]]@($WikidataIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($items.Count -eq 0) { return $result }

    for ($i=0; $i -lt $items.Count; $i += [int]$script:ApiSettings.BatchSize) {
        $batch = Get-BatchSlice -Items $items -Start $i -BatchSize ([int]$script:ApiSettings.BatchSize)
        $ids = [string]::Join('|',[string[]]$batch)
        $encoded = [Uri]::EscapeDataString($ids)
        $url = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$encoded&props=sitelinks&sitefilter=arwiki&format=json&formatversion=2&maxlag=5"
        try {
            $response = Invoke-WikiApiRequest -Uri $url -ApiName Wikidata
            foreach ($qid in $batch) { $script:LastArabicSitelinkSuccess[[string]$qid] = $true }
            foreach ($entity in (Get-WikidataEntitiesCollection -Entities $response.entities)) {
                if ($null -eq $entity) { continue }
                if ($null -ne $entity.sitelinks -and
                    $null -ne $entity.sitelinks.arwiki -and
                    -not [string]::IsNullOrWhiteSpace([string]$entity.sitelinks.arwiki.title)) {
                    $result[[string]$entity.id] = [string]$entity.sitelinks.arwiki.title
                }
            }
        }
        catch {
            Write-Warning "فشل الاتصال بـ Wikidata API لهذه الدفعة؛ لن تُحفظ نتائج سلبية لها."
            Write-Warning "السبب: $($_.Exception.Message)"
        }
    }
    return $result
}

function Get-ArabicWikipediaDisambiguationBatch {
    param([Parameter(Mandatory)][array]$ArabicTitles)
    $result = @{}
    $items = [object[]]@($ArabicTitles | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($items.Count -eq 0) { return $result }

    for ($i=0; $i -lt $items.Count; $i += [int]$script:ApiSettings.BatchSize) {
        $batch = Get-BatchSlice -Items $items -Start $i -BatchSize ([int]$script:ApiSettings.BatchSize)
        $titles = [string]::Join('|',[string[]]$batch)
        $encoded = [Uri]::EscapeDataString($titles)
        $url = "https://ar.wikipedia.org/w/api.php?action=query&prop=pageprops&ppprop=disambiguation&titles=$encoded&redirects=1&format=json&formatversion=2&maxlag=5"
        try {
            $response = Invoke-WikiApiRequest -Uri $url -ApiName Wikipedia
            foreach ($page in @($response.query.pages)) {
                if ($null -eq $page -or [string]::IsNullOrWhiteSpace([string]$page.title)) { continue }
                $isDisambig = ($null -ne $page.pageprops -and $null -ne $page.pageprops.disambiguation)
                $result[[string]$page.title] = [bool]$isDisambig
            }
            foreach ($t in $batch) {
                if (-not $result.ContainsKey([string]$t)) { $result[[string]$t] = $false }
            }
        }
        catch {
            Write-Warning "فشل التحقق من صفحات التوضيح في Wikipedia API لهذه الدفعة؛ لن تُستخدم الصفحات غير الموثوقة."
            throw
        }
    }
    return $result
}

function Resolve-WikipediaLinksBatch {
    param([Parameter(Mandatory)][array]$EnglishTitles)
    $resolved = @{}
    $EnglishTitles = [object[]]@($EnglishTitles | Select-Object -Unique)
    if ($EnglishTitles.Count -eq 0) { return $resolved }

    $titlesToQuery = [System.Collections.Generic.List[string]]::new()
    $cacheQidHits=0; $cacheQidMisses=0
    foreach ($title in $EnglishTitles) {
        $title=[string]$title; $key="qid:$title"
        if (Test-WikidataCache -Key $key) {
            $cacheQidHits++; $resolved[$title]=@{QID=[string]$script:WikidataCache.PSObject.Properties[$key].Value}
        } else { $cacheQidMisses++; $titlesToQuery.Add($title) }
    }

    if ($titlesToQuery.Count -gt 0) {
        Write-Host "روابط جديدة تحتاج Wikidata: $($titlesToQuery.Count)" -ForegroundColor Cyan
        $qidResults = Get-WikidataEntityIdsBatch -EnglishTitles ([object[]]$titlesToQuery.ToArray())
        $cacheChanged=$false
        foreach ($title in $titlesToQuery) {
            $qid=$null
            if ($qidResults.ContainsKey([string]$title)) { $qid=[string]$qidResults[[string]$title] }
            if ($script:LastWikipediaTitleSuccess.ContainsKey([string]$title)) {
                Set-WikidataCacheValue -Key "qid:$title" -Value $qid; $cacheChanged=$true
            }
            $resolved[[string]$title]=@{QID=$qid}
        }
        if ($cacheChanged) { Save-WikidataCache }
    }

    $qidsToQuery=[System.Collections.Generic.List[string]]::new(); $cacheArabicHits=0; $cacheArabicMisses=0
    $NoArabicSitelinkMarker='__NO_ARABIC_SITELINK__'
    foreach ($title in @($resolved.Keys)) {
        $qid=[string]$resolved[$title].QID
        if ([string]::IsNullOrWhiteSpace($qid)) { continue }
        $key="arwiki:$qid"
        if (Test-WikidataCache -Key $key) {
            $value=[string]$script:WikidataCache.PSObject.Properties[$key].Value
            if ($value -eq $NoArabicSitelinkMarker) {
                $cacheArabicHits++
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $cacheArabicHits++
                $resolved[$title].ArabicTitle=$value
            } else {
                # Legacy empty arwiki cache entries are stale and must be refreshed.
                $cacheArabicMisses++
                if (-not $qidsToQuery.Contains($qid)) { $qidsToQuery.Add($qid) }
            }
        } else {
            $cacheArabicMisses++
            if (-not $qidsToQuery.Contains($qid)) { $qidsToQuery.Add($qid) }
        }
    }

    if ($qidsToQuery.Count -gt 0) {
        $qids=[object[]]$qidsToQuery.ToArray()
        Write-Host "كيانات جديدة تحتاج arwiki: $($qids.Count)" -ForegroundColor Cyan
        Write-Host "عدد QIDs المرسلة إلى Wikidata: $($qids.Count) (دفعة قصوى: $($script:ApiSettings.BatchSize))" -ForegroundColor DarkGray
        $arabicResults=Get-ArabicWikipediaTitlesBatch -WikidataIds $qids
        $cacheChanged=$false
        $NoArabicSitelinkMarker='__NO_ARABIC_SITELINK__'
        foreach ($qid in $qids) {
            $qid=[string]$qid
            if (-not $script:LastArabicSitelinkSuccess.ContainsKey($qid)) { continue }
            $value=$null
            if ($arabicResults.ContainsKey($qid) -and -not [string]::IsNullOrWhiteSpace([string]$arabicResults[$qid])) {
                $value=[string]$arabicResults[$qid]
            } else {
                $value=$NoArabicSitelinkMarker
            }
            Set-WikidataCacheValue -Key "arwiki:$qid" -Value $value; $cacheChanged=$true
        }
        if ($cacheChanged) { Save-WikidataCache }
    }

    foreach ($title in @($resolved.Keys)) {
        $qid=[string]$resolved[$title].QID
        if ([string]::IsNullOrWhiteSpace($qid)) { continue }
        $key="arwiki:$qid"
        if (Test-WikidataCache -Key $key) {
            $value=[string]$script:WikidataCache.PSObject.Properties[$key].Value
            if (-not [string]::IsNullOrWhiteSpace($value) -and $value -ne '__NO_ARABIC_SITELINK__') {
                $resolved[$title].ArabicTitle=$value
            }
        }
    }

    $script:CacheStats=[ordered]@{QidHits=$cacheQidHits;QidMisses=$cacheQidMisses;ArabicHits=$cacheArabicHits;ArabicMisses=$cacheArabicMisses}
    return $resolved
}


function Get-ArabicWikidataLabelsBatch {
    param([Parameter(Mandatory)][array]$WikidataIds)
    $result=@{}
    $ids=[object[]]@($WikidataIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if($ids.Count -eq 0){ return $result }

    $idsToQuery=[System.Collections.Generic.List[string]]::new()
    $cacheHits=0
    foreach($qid in $ids){
        $qid=[string]$qid
        $key="arlabel:$qid"
        if(Test-WikidataCache -Key $key){
            $cached=[string]$script:WikidataCache.PSObject.Properties[$key].Value
            if(-not [string]::IsNullOrWhiteSpace($cached) -and $cached -match '[\u0600-\u06FF]'){
                $cacheHits++; $result[$qid]=$cached
            } else {
                $idsToQuery.Add($qid)
                try { $script:WikidataCache.PSObject.Properties.Remove($key) } catch {}
            }
        } else { $idsToQuery.Add($qid) }
    }
    $script:WikidataLabelCacheStats=[ordered]@{Hits=$cacheHits;Misses=$idsToQuery.Count;ApiRequests=0}
    if($idsToQuery.Count -eq 0){ return $result }

    for($i=0;$i -lt $idsToQuery.Count;$i+=50){
        $end=[Math]::Min($i+49,$idsToQuery.Count-1)
        $batch=@($idsToQuery[$i..$end])
        $encoded=[Uri]::EscapeDataString(($batch -join '|'))
        $url="https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$encoded&props=labels&languages=ar&languagefallback=0&format=json&formatversion=2&maxlag=5"
        try {
            $script:WikidataLabelCacheStats.ApiRequests++
            $response=Invoke-WikiApiRequest -Uri $url -ApiName 'Wikidata'
            if($null -eq $response){ continue }
            $script:ApiStats.SuccessfulRequests++
            foreach($entity in (Get-WikidataEntitiesCollection -Entities $response.entities)){
                if($null -eq $entity){continue}
                $qid=[string]$entity.id; $labelValue=''
                if($null -ne $entity.labels -and $null -ne $entity.labels.ar){$labelValue=[string]$entity.labels.ar.value}
                if(-not [string]::IsNullOrWhiteSpace($labelValue) -and $labelValue -match '[\u0600-\u06FF]'){
                    Set-WikidataCacheValue -Key "arlabel:$qid" -Value $labelValue
                    $result[$qid]=$labelValue
                } else { try { $script:WikidataCache.PSObject.Properties.Remove("arlabel:$qid") } catch {} }
            }
            Save-WikidataCache
        } catch { Write-Warning "تعذر الحصول على التسميات العربية من Wikidata: $($_.Exception.Message)" }
    }
    return $result
}
