$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Modules\WikitextParser.ps1')
. (Join-Path $root 'Modules\Wikidata.ps1')
. (Join-Path $root 'Modules\LinkTranslator.ps1')
function Resolve-WikipediaLinksBatch {
    param([Parameter(Mandatory)][string[]]$EnglishTitles)
    $result=@{}
    foreach($title in $EnglishTitles){
        $ar=''; $qid='QTEST'
        switch($title){
            "Henry Morgan's raid on Porto Bello" {$ar='غارة هنري مورغان على بورتوبيلو'}
            "Henry Morgan's raid on Lake Maracaibo" {$ar='غارة هنري مورغان على بحيرة ماراكايبو'}
            'Lake Nicaragua' {$ar='بحيرة نيكاراغوا';$qid='Q-LAKE'}
            'Panama' {$ar='بنما';$qid='Q-PANAMA'}
            'Joseph Bannister' {$qid='Q-RANGER'}
            'Charles Town' {$ar='شارلستون (توضيح)';$qid='Q-CHARLESTON'}
        }
        $result[$title]=[PSCustomObject]@{QID=$qid;ArabicTitle=$ar}
    }
    return $result
}
function Get-ArabicWikidataLabelsBatch { param([Parameter(Mandatory)][string[]]$WikidataIds) $r=@{}; foreach($q in $WikidataIds){if($q -eq 'Q-RANGER'){$r[$q]='جوزيف بانيستر'}}; return $r }
function Get-ArabicWikipediaDisambiguationBatch { param([Parameter(Mandatory)][string[]]$ArabicTitles) $r=@{}; foreach($t in $ArabicTitles){$r[$t]=($t -eq 'شارلستون (توضيح)')}; return $r }
$input=@'
* [[Henry Morgan's raid on Porto Bello|Porto Bello]]
* [[Henry Morgan's raid on Lake Maracaibo|Lake Maracaibo]]
* [[Lake Nicaragua|Lake Nicaragua]]
* [[Panama|Panama]]
* [[Capture of John Rackham|Capture of ''William'']]
* [[Joseph Bannister|Samaná Bay]]
* [[Blackbeard#Blockade of Charles Town|Charles Town]]
'@
$output=Convert-WikipediaLinks -Text $input
$expected=@'
* [[غارة هنري مورغان على بورتوبيلو|بورتو بيلو]]
* [[غارة هنري مورغان على بحيرة ماراكايبو|بحيرة ماراكايبو]]
* [[بحيرة نيكاراغوا|بحيرة نيكاراغوا]]
* [[بنما|بنما]]
* [[Capture of John Rackham|Capture of ''William'']]
* {{Ill-WD2|جوزيف بانيستر|id=Q-RANGER|نص=خليج سامانا}}
* [[Blackbeard#Blockade of Charles Town|Charles Town]]
'@
if($output -ne $expected){Write-Host 'Link display test FAILED.' -ForegroundColor Red;Write-Host 'Expected:';Write-Host $expected;Write-Host 'Actual:';Write-Host $output;exit 1}
if($LinkStats.IllWD2 -ne 1){throw "Expected 1 Ill-WD2 link, got $($LinkStats.IllWD2)."}
if($LinkStats.Converted -ne 5){throw "Expected 5 converted links, got $($LinkStats.Converted)."}

Write-Host 'Link display regression tests passed.' -ForegroundColor Green
