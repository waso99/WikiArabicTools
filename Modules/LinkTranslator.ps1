# ============================================
# LinkTranslator.ps1
# ترجمة روابط ويكيبيديا باستخدام Wikidata
# ============================================

$script:LinkStats=[ordered]@{Total=0;Converted=0;IllWD2=0;NoWikidata=0;NoArabic=0;Ignored=0;Protected=0;SectionLinks=0;DisplayTranslated=0;GeminiRequests=0;GeminiFailures=0}
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
# Gemini: ترجمة النص الظاهر للرابط
# ============================================

$script:GeminiDisplayCachePath = Join-Path $PSScriptRoot '..\Cache\GeminiDisplayCache.json'

function Get-GeminiDisplayCache {
    if(-not (Test-Path $script:GeminiDisplayCachePath)){ return @{} }

    try {
        $obj = Get-Content -LiteralPath $script:GeminiDisplayCachePath -Raw -Encoding UTF8 |
            ConvertFrom-Json

        $cache = @{}
        foreach($p in $obj.PSObject.Properties){
            $cache[[string]$p.Name] = [string]$p.Value
        }
        return $cache
    }
    catch {
        Write-Warning "Could not read GeminiDisplayCache.json: $($_.Exception.Message)"
        return @{}
    }
}

function Save-GeminiDisplayCache {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    try {
        $dir = Split-Path -Parent $script:GeminiDisplayCachePath

        if(-not (Test-Path $dir)){
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $Cache |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $script:GeminiDisplayCachePath -Encoding UTF8
    }
    catch {
        Write-Warning "Could not save GeminiDisplayCache.json: $($_.Exception.Message)"
    }
}

function Test-NeedsGeminiDisplayTranslation {
    param(
        [AllowEmptyString()]
        [string]$Display
    )

    if([string]::IsNullOrWhiteSpace($Display)){ return $false }

    # النص العربي لا يحتاج ترجمة.
    if($Display -match '[\u0600-\u06FF]'){ return $false }

    return $true
}

if($null -eq $script:GeminiNextAllowedTime){ $script:GeminiNextAllowedTime = [DateTime]::MinValue
$script:GeminiDisabledThisRun = $false
$script:Gemini429CountThisRun = 0 }

function Wait-GeminiRateLimit {
    param([int]$MinimumIntervalSeconds = 8)
    $now=[DateTime]::UtcNow
    $wait=($script:GeminiNextAllowedTime-$now).TotalSeconds
    if($wait -gt 0){ $s=[Math]::Ceiling($wait); Write-Host "  Waiting $s seconds for Gemini..." -ForegroundColor DarkGray; Start-Sleep -Seconds $s }
    $script:GeminiNextAllowedTime=[DateTime]::UtcNow.AddSeconds($MinimumIntervalSeconds)
}

function Get-GeminiRetryDelaySeconds {
    param([int]$Attempt,[int]$DefaultSeconds=10)
    return [int][Math]::Min(120,$DefaultSeconds*[Math]::Pow(2,($Attempt-1)))
}

function Invoke-GeminiDisplayTranslationsBatch {
    param(
        [Parameter(Mandatory)]
        [string[]]$Displays
    )

    if($script:GeminiDisabledThisRun){ return @{} }

    function Get-GeminiSetting {
        param([Parameter(Mandatory)][string]$Name,[string]$Default='')
        $value=[Environment]::GetEnvironmentVariable($Name,'Process')
        if([string]::IsNullOrWhiteSpace($value)){ $value=[Environment]::GetEnvironmentVariable($Name,'User') }
        if([string]::IsNullOrWhiteSpace($value)){ $value=[Environment]::GetEnvironmentVariable($Name,'Machine') }
        if([string]::IsNullOrWhiteSpace($value)){ $value=$Default }
        if($null -ne $value){ $value=$value.Trim().Trim('\"').Trim() }
        return $value
    }

    $apiKey=Get-GeminiSetting -Name 'GEMINI_API_KEY'
    if([string]::IsNullOrWhiteSpace($apiKey)){
        if(-not $script:GeminiDisabledThisRun){
            Write-Warning "GEMINI_API_KEY was not found in Process/User/Machine; visible texts will remain unchanged for this run."
            $script:GeminiDisabledThisRun=$true
        }
        return @{}
    }

    $model=Get-GeminiSetting -Name 'GEMINI_MODEL' -Default 'gemini-3.5-flash'
    $model=$model.Trim()
    if($model -like "models/*"){ $model=$model.Substring(7) }

    # نموذج بديل يُجرّب مرة واحدة فقط إذا أعاد النموذج الأساسي HTTP 429.
    $fallbackModel=Get-GeminiSetting -Name 'GEMINI_FALLBACK_MODEL' -Default 'gemini-3.1-flash-lite'
    $fallbackModel=$fallbackModel.Trim()
    if($fallbackModel -like "models/*"){ $fallbackModel=$fallbackModel.Substring(7) }

    $uri="https://generativelanguage.googleapis.com/v1beta/models/$model`:generateContent"
    if(-not $script:GeminiConfigurationShown){
        Write-Host "Gemini: API key = present | model = $model | fallback = $fallbackModel" -ForegroundColor DarkGray
        $script:GeminiConfigurationShown=$true
    }

    $items=@()
    for($i=0;$i -lt $Displays.Count;$i++){
        $items += "{0}. {1}" -f ($i+1), $Displays[$i]
    }
    $inputText=$items -join "`n"

    $prompt=@"
You are an English-to-Arabic translator for Arabic Wikipedia.

Translate each English display text below into concise, natural, formal Arabic suitable for an Arabic Wikipedia link label.

STRICT OUTPUT RULES:
- Return exactly one line for every numbered input.
- Preserve the same numbering and order.
- Format every result exactly as: NUMBER<TAB>ARABIC TRANSLATION
- Return ONLY the numbered translations. No introduction, explanation, alternatives, or conclusion.
- Do NOT repeat the English text.
- Do NOT use Markdown or code fences.
- Do NOT use Wikitext such as [[ ]], {{ }}, or |.
- Do NOT add quotation marks around the translation.
- Preserve the meaning and scope of each original text.
- Prefer established Arabic terminology for historical events, wars, places, people, organizations, and other proper names when it is known.
- Do not merge, split, omit, or reorder items.

English display texts:
$inputText
"@

    $body=(@{
        contents=@(@{parts=@(@{text=$prompt})})
        generationConfig=@{temperature=0.1}
    } | ConvertTo-Json -Depth 10)

    # إذا كانت الدفعة صغيرة جدًا (خصوصًا عنصرًا واحدًا)، فلا نعيد محاولة 429.
    # هذا يمنع إضاعة الوقت على طلب واحد عند وجود حد/ازدحام في Gemini.
    # الدفعات الأكبر تحصل على محاولة ثانية واحدة فقط عند الأخطاء المؤقتة.
    if($Displays.Count -le 2){
        $maxAttempts=1
    } else {
        $maxAttempts=2
    }
    # إذا كانت الدفعة صغيرة جدًا، لا نعيد المحاولة after 429؛ إعادة المحاولة لعنصر واحد
    # غالبًا لا تضيف شيئًا وتؤخر التشغيل فقط. سيُعاد طلبه في التشغيل التالي.
    $isSmallBatch=($Displays.Count -le 2)
    for($attempt=1;$attempt -le $maxAttempts;$attempt++){
        Wait-GeminiRateLimit -MinimumIntervalSeconds 10
        try {
            $script:LinkStats.GeminiRequests++
            Write-Host "  Gemini batch [$attempt/$maxAttempts] - $($Displays.Count) texts" -ForegroundColor DarkCyan

            try {
                $response=Invoke-RestMethod -Uri $uri -Method Post `
                    -Headers @{'x-goog-api-key'=$apiKey;'Accept'='application/json'} `
                    -ContentType 'application/json; charset=utf-8' `
                    -Body $body -ErrorAction Stop
            }
            catch {
                $primaryException=$_
                $primaryStatus=$null
                $primaryBody=$null
                $primaryRetryAfter=$null

                try {
                    $primaryResp=$_.Exception.Response
                    if($null -ne $primaryResp){
                        try { $primaryStatus=[int]$primaryResp.StatusCode } catch {}
                        try { $primaryRetryAfter=$primaryResp.Headers['Retry-After'] } catch {}
                        try {
                            $primaryStream=$primaryResp.GetResponseStream()
                            if($null -ne $primaryStream){
                                $primaryReader=New-Object System.IO.StreamReader($primaryStream)
                                $primaryBody=$primaryReader.ReadToEnd()
                                $primaryReader.Dispose()
                                $primaryStream.Dispose()
                            }
                        } catch {}
                    }
                } catch {}

                $primaryMessage=[string]$_.Exception.Message
                $primaryIs429=($primaryStatus -eq 429) -or ($primaryMessage -match '429|Too Many Requests')

                if($primaryIs429 -and -not [string]::IsNullOrWhiteSpace($fallbackModel) -and $fallbackModel -ne $model){
                    $script:Gemini429CountThisRun++
                    Write-Warning "Gemini returned HTTP 429 for model $model."
                    if(-not [string]::IsNullOrWhiteSpace([string]$primaryRetryAfter)){
                        Write-Host "  Retry-After: $primaryRetryAfter" -ForegroundColor Yellow
                    }

                    if(-not [string]::IsNullOrWhiteSpace($primaryBody)){
                        try {
                            $errorJson=$primaryBody | ConvertFrom-Json
                            if($null -ne $errorJson.error){
                                Write-Host "  reason: $($errorJson.error.reason)" -ForegroundColor Yellow
                                Write-Host "  status: $($errorJson.error.status)" -ForegroundColor Yellow
                                Write-Host "  message: $($errorJson.error.message)" -ForegroundColor Yellow
                            } else {
                                Write-Host "  429 details: $primaryBody" -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "  429 details: $primaryBody" -ForegroundColor Yellow
                        }
                    }

                    Write-Host "  Trying fallback model: $fallbackModel" -ForegroundColor Cyan
                    Wait-GeminiRateLimit -MinimumIntervalSeconds 10
                    $script:LinkStats.GeminiRequests++
                    $fallbackUri="https://generativelanguage.googleapis.com/v1beta/models/$fallbackModel`:generateContent"

                    try {
                        $response=Invoke-RestMethod -Uri $fallbackUri -Method Post `
                            -Headers @{'x-goog-api-key'=$apiKey;'Accept'='application/json'} `
                            -ContentType 'application/json; charset=utf-8' `
                            -Body $body -ErrorAction Stop
                        $uri=$fallbackUri
                        Write-Host "  Fallback model succeeded: $fallbackModel" -ForegroundColor Green
                    }
                    catch {
                        $fallbackException=$_
                        $fallbackStatus=$null
                        $fallbackBody=$null
                        try {
                            $fallbackResp=$_.Exception.Response
                            if($null -ne $fallbackResp){
                                try { $fallbackStatus=[int]$fallbackResp.StatusCode } catch {}
                                try {
                                    $fallbackStream=$fallbackResp.GetResponseStream()
                                    if($null -ne $fallbackStream){
                                        $fallbackReader=New-Object System.IO.StreamReader($fallbackStream)
                                        $fallbackBody=$fallbackReader.ReadToEnd()
                                        $fallbackReader.Dispose()
                                        $fallbackStream.Dispose()
                                    }
                                } catch {}
                            }
                        } catch {}

                        $fallbackMessage=[string]$_.Exception.Message
                        if($fallbackStatus -eq 429 -or $fallbackMessage -match '429|Too Many Requests'){
                            $script:Gemini429CountThisRun++
                            Write-Warning "Fallback model $fallbackModel أعاد HTTP 429 also."
                            if(-not [string]::IsNullOrWhiteSpace($fallbackBody)){
                                try {
                                    $fallbackJson=$fallbackBody | ConvertFrom-Json
                                    if($null -ne $fallbackJson.error){
                                        Write-Host "  reason: $($fallbackJson.error.reason)" -ForegroundColor Yellow
                                        Write-Host "  status: $($fallbackJson.error.status)" -ForegroundColor Yellow
                                        Write-Host "  message: $($fallbackJson.error.message)" -ForegroundColor Yellow
                                    } else {
                                        Write-Host "  429 details: $fallbackBody" -ForegroundColor Yellow
                                    }
                                } catch {
                                    Write-Host "  429 details: $fallbackBody" -ForegroundColor Yellow
                                }
                            }
                        }
                        throw $fallbackException
                    }
                } else {
                    throw $primaryException
                }
            }

            if($null -eq $response.candidates -or $response.candidates.Count -eq 0){
                throw "لم يُرجع Gemini أي candidate."
            }

            $raw=[string]$response.candidates[0].content.parts[0].text
            $raw=$raw.Trim()
            $raw=$raw -replace '^\s*```(?:text|markdown)?\s*',''
            $raw=$raw -replace '\s*```\s*$',''
            $raw=$raw.Trim()

            $result=@{}
            $lines=@($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

            foreach($line in $lines){
                if($line -match '^\s*(\d+)\s*[\.\)\-:]?\s*\t\s*(.+?)\s*$'){
                    $number=[int]$Matches[1]
                    $translation=Clean-GeminiDisplayTranslation -Text $Matches[2]
                    if($number -ge 1 -and $number -le $Displays.Count -and -not [string]::IsNullOrWhiteSpace($translation)){
                        $result[$Displays[$number-1]]=$translation
                    }
                    continue
                }

                # السماح also بإخراج "1. الترجمة" إذا استبدل Gemini علامة الجدولة بنقطة.
                if($line -match '^\s*(\d+)\s*[\.\)\-:]\s*(.+?)\s*$'){
                    $number=[int]$Matches[1]
                    $translation=Clean-GeminiDisplayTranslation -Text $Matches[2]
                    if($number -ge 1 -and $number -le $Displays.Count -and -not [string]::IsNullOrWhiteSpace($translation)){
                        $result[$Displays[$number-1]]=$translation
                    }
                }
            }

            if($result.Count -eq 0){ throw "تعذر تحليل ترجمات Gemini للدفعة." }

            # نرفض الدفعة فقط إذا فقدت عناصر كثيرة؛ العناصر المفقودة ستبقى بلا ترجمة.
            $missing=$Displays | Where-Object { -not $result.ContainsKey($_) }
            if($missing.Count -gt [Math]::Max(2,[Math]::Floor($Displays.Count/2))){
                throw "أعاد Gemini عددًا غير كافٍ من الترجمات ($($result.Count)/$($Displays.Count))."
            }

            foreach($display in $Displays){
                if($result.ContainsKey($display)){
                    Write-Host "    ✓ $display → $($result[$display])" -ForegroundColor Green
                } else {
                    Write-Warning "Gemini did not return a translation for text '$display'."
                }
            }
            return $result
        }
        catch {
            $message=$_.Exception.Message
            $statusCode=$null
            $errorBody=$null
            $retryAfter=$null

            try {
                $resp=$_.Exception.Response
                if($null -ne $resp){
                    try { $statusCode=[int]$resp.StatusCode } catch {}
                    try { $retryAfter=$resp.Headers['Retry-After'] } catch {}
                    try {
                        $stream=$resp.GetResponseStream()
                        if($null -ne $stream){
                            $reader=New-Object System.IO.StreamReader($stream)
                            $errorBody=$reader.ReadToEnd()
                            $reader.Dispose()
                            $stream.Dispose()
                        }
                    } catch {}
                }
            } catch {}

            if($statusCode -eq 429 -or $message -match '429|Too Many Requests'){
                $script:Gemini429CountThisRun++
                Write-Warning "Gemini returned HTTP 429 (Too Many Requests)."
                if($Displays.Count -le 2){
                    Write-Host "  The batch is too small; it will not be retried now. The text will be requested again on the next run." -ForegroundColor Yellow
                }
                if(-not [string]::IsNullOrWhiteSpace([string]$retryAfter)){
                    Write-Host "  Retry-After: $retryAfter" -ForegroundColor Yellow
                }
                if(-not [string]::IsNullOrWhiteSpace([string]$errorBody)){
                    Write-Host "  Full Gemini response:" -ForegroundColor Yellow
                    Write-Host "  $errorBody" -ForegroundColor DarkYellow
                } else {
                    Write-Host "  Google returned no additional details about the 429 error." -ForegroundColor Yellow
                }
            } elseif($statusCode){
                Write-Warning "Gemini returned HTTP $statusCode."
                if(-not [string]::IsNullOrWhiteSpace([string]$errorBody)){
                    Write-Host "  $errorBody" -ForegroundColor DarkYellow
                }
            }

            $delay=0
            $retryable=($statusCode -eq 429) -or ($message -match '429|Too Many Requests|503|Service Unavailable|500|502|504|timeout|timed out')
            if($retryable -and $attempt -lt $maxAttempts -and -not ($statusCode -eq 429 -and $isSmallBatch)){
                
                if($statusCode -eq 429 -and -not [string]::IsNullOrWhiteSpace([string]$retryAfter)){
                    $delay=0
                    try { $delay=[int]$retryAfter } catch {}
                    if($delay -gt 0){ $delay=[Math]::Min(300,$delay) }
                }
                if($delay -le 0){
                    $delay=Get-GeminiRetryDelaySeconds -Attempt $attempt -DefaultSeconds 15
                    # jitter صغير لتجنب تزامن الattempts.
                    $delay += Get-Random -Minimum 0 -Maximum 6
                }
                if($attempt -lt $maxAttempts){
                    Write-Warning "Gemini temporarily unavailable for this batch. Retrying after $delay seconds..."
                    Start-Sleep -Seconds $delay
                    continue
                }
            }

            $script:LinkStats.GeminiFailures++
            if($statusCode -eq 429 -or $message -match '429|Too Many Requests') {
                $script:GeminiDisabledThisRun = $true
                Write-Warning "Gemini and the fallback model both failed with HTTP 429. Processing will continue without Display translation; untranslated texts will be requested on the next run."
            }
            Write-Warning "Gemini failed to translate a batch of $($Displays.Count) texts: $message | URI: $uri"
            return @{}
        }
    }

    $script:LinkStats.GeminiFailures++
    return @{}
}

function Clean-GeminiDisplayTranslation {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $result = $Text.Trim()

    # إزالة Markdown الشائع إذا أعاده النموذج رغم التعليمات.
    $result = $result -replace '^\s*```(?:text|markdown)?\s*', ''
    $result = $result -replace '\s*```\s*$', ''
    $result = $result.Trim()

    # إزالة علامات الاقتباس المحيطة بالنص.
    if(
        $result.Length -ge 2 -and
        (
            ($result.StartsWith('"') -and $result.EndsWith('"')) -or
            ($result.StartsWith('“') -and $result.EndsWith('”')) -or
            ($result.StartsWith('«') -and $result.EndsWith('»'))
        )
    ){
        $result = $result.Substring(1, $result.Length - 2).Trim()
    }

    # إذا أعاد النموذج عدة أسطر، استخدم أول سطر غير فارغ.
    $lines = @(
        $result -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
    )

    if($lines.Count -gt 1){
        # لا نغامر بأخذ شرح طويل؛ نرفض النتيجة متعددة الأسطر.
        throw "أعاد Gemini أكثر من سطر للنص الظاهر."
    }

    return $result.Trim()
}

function Get-DeterministicArabicDisplay {
    param(
        [string]$Display,
        [string]$EnglishTitle,
        [string]$ArabicTitle,
        [string]$ArabicWikidataLabel
    )

    if ([string]::IsNullOrWhiteSpace($Display)) { return $null }

    # If visible text is exactly the English source title, do not call Gemini.
    if (-not [string]::IsNullOrWhiteSpace($EnglishTitle) -and
        [string]::Equals($Display.Trim(), $EnglishTitle.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace($ArabicTitle)) { return $ArabicTitle.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($ArabicWikidataLabel) -and $ArabicWikidataLabel -match '[\u0600-\u06FF]') {
            return $ArabicWikidataLabel.Trim()
        }
    }

    return $null
}

function Get-ArabicDisplayText {
    param(
        [AllowEmptyString()]
        [string]$Display,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    if(-not (Test-NeedsGeminiDisplayTranslation -Display $Display)){
        return $Display
    }

    if($Cache.ContainsKey($Display)){
        return [string]$Cache[$Display]
    }

    # لا نرسل طلبًا فرديًا هنا؛ تتم ترجمة الtexts على دفعات قبل إعادة بناء الروابط.
    return $Display
}

function Convert-WikipediaLinks {
    param([Parameter(Mandatory)][string]$Text)
    $script:LinkStats=[ordered]@{Total=0;Converted=0;IllWD2=0;NoWikidata=0;NoArabic=0;Ignored=0;Protected=0;SectionLinks=0;DisplayTranslated=0;GeminiRequests=0;GeminiFailures=0}
    $script:UntranslatedLinks=@()
    $script:GeminiDisabledThisRun=$false
    $script:Gemini429CountThisRun=0
    $script:GeminiConfigurationShown=$false
    Write-Host "`nAnalyzing Wikitext..." -ForegroundColor Cyan
    $tokens=Get-WikitextTokens -Text $Text
    $links=@(Get-WikitextInternalLinks -Tokens $tokens)
    $script:LinkStats.Total=$links.Count
    Write-Host "Found $($links.Count) processable links." -ForegroundColor Gray
    if($links.Count -eq 0){return $Text}
    $uniqueTitles=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if($script:Gemini429CountThisRun -gt 0){
        Write-Host "Gemini: HTTP 429 responses in this run: $($script:Gemini429CountThisRun)." -ForegroundColor Yellow
    }
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
    $geminiDisplayCache=Get-GeminiDisplayCache
    $geminiCacheChanged=$false

    # جمع الtexts الظاهرة الفريدة التي تحتاج Gemini، ثم ترجمتها على batches.
    $geminiDisplays=New-Object System.Collections.Generic.List[string]
    $geminiDisplaySeen=@{}
    foreach($link in $links){
        if(-not $resolution.ContainsKey($link.Target)){ continue }
        $resolved=$resolution[$link.Target]
        $hasArabicPage = -not [string]::IsNullOrWhiteSpace([string]$resolved.ArabicTitle)

        # For Ill-WD2 links, the Arabic Wikidata label is already available
        # and the visible link text still needs Gemini translation.
        $hasArabicWikidataLabel = $false
        if(-not $hasArabicPage){
            $candidateQid=[string]$resolved.QID
            if(-not [string]::IsNullOrWhiteSpace($candidateQid) -and $illWdLabels.ContainsKey($candidateQid)){
                $candidateWdLabel=[string]$illWdLabels[$candidateQid]
                $hasArabicWikidataLabel = (
                    -not [string]::IsNullOrWhiteSpace($candidateWdLabel) -and
                    $candidateWdLabel -match '[\u0600-\u06FF]'
                )
            }
        }

        if(-not $hasArabicPage -and -not $hasArabicWikidataLabel){ continue }

        $display=[string]$link.Display
        if(-not (Test-NeedsGeminiDisplayTranslation -Display $display)){ continue }

        $wdLabelForDisplay=$null
        if($hasArabicWikidataLabel){ $wdLabelForDisplay=[string]$illWdLabels[[string]$resolved.QID] }
        $deterministicDisplay=Get-DeterministicArabicDisplay `
            -Display $display `
            -EnglishTitle ([string]$link.Target) `
            -ArabicTitle ([string]$resolved.ArabicTitle) `
            -ArabicWikidataLabel $wdLabelForDisplay
        if(-not [string]::IsNullOrWhiteSpace([string]$deterministicDisplay)){ continue }

        if($geminiDisplayCache.ContainsKey($display)){ continue }
        if($geminiDisplaySeen.ContainsKey($display)){ continue }
        $geminiDisplaySeen[$display]=$true
        [void]$geminiDisplays.Add($display)
    }

    if($geminiDisplays.Count -gt 0){
        $batchSize=10
        $batchSizeEnv=[Environment]::GetEnvironmentVariable('GEMINI_BATCH_SIZE')
        if($batchSizeEnv -match '^\d+$' -and [int]$batchSizeEnv -ge 1 -and [int]$batchSizeEnv -le 20){ $batchSize=[int]$batchSizeEnv }
        $batchCount=[Math]::Ceiling($geminiDisplays.Count / $batchSize)
        Write-Host "`nTranslating visible texts with Gemini: $($geminiDisplays.Count) texts in $batchCount batches." -ForegroundColor Cyan

        for($batchIndex=0;$batchIndex -lt $batchCount;$batchIndex++){
            if($script:GeminiDisabledThisRun){
                Write-Host "Gemini has been disabled for the rest of this run; remaining batches will be skipped." -ForegroundColor Yellow
                break
            }
            $startIndex=$batchIndex*$batchSize
            $count=[Math]::Min($batchSize,$geminiDisplays.Count-$startIndex)
            $batch=@($geminiDisplays.GetRange($startIndex,$count))
            Write-Host "Gemini batch [$($batchIndex+1)/$batchCount] ($count texts)" -ForegroundColor DarkCyan
            $translations=Invoke-GeminiDisplayTranslationsBatch -Displays $batch

            foreach($display in $translations.Keys){
                $translation=[string]$translations[$display]
                if(-not [string]::IsNullOrWhiteSpace($translation)){
                    $geminiDisplayCache[$display]=$translation
                    $script:LinkStats.DisplayTranslated++
                    $geminiCacheChanged=$true
                }
            }

            if($geminiCacheChanged){
                Save-GeminiDisplayCache -Cache $geminiDisplayCache
                $geminiCacheChanged=$false
            }
        }
    } else {
        Write-Host "No new visible texts require Gemini translation." -ForegroundColor DarkGray
    }
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
                    else {
                        $displayText=Get-ArabicDisplayText -Display $displayText -Cache $geminiDisplayCache
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
        if([string]::IsNullOrWhiteSpace([string]$arabicDisplay)){
            $arabicDisplay=Get-ArabicDisplayText -Display $link.Display -Cache $geminiDisplayCache
        }

        $newLink=New-ArabicWikipediaLink -ArabicTitle $arabicTitle -Section $link.Section -Display $arabicDisplay

        if($newLink -eq $link.Text){continue}

        $replacements[[int]$link.Start]=$newLink
        $script:LinkStats.Converted++
    }
    if($geminiCacheChanged){ Save-GeminiDisplayCache -Cache $geminiDisplayCache }
    Write-Host "`nRebuilding Wikitext..." -ForegroundColor Cyan
    return Rebuild-Wikitext -Text $Text -Tokens $tokens -Replacements $replacements
}
