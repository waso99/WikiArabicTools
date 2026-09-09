# ============================================
# Test-TemplateTranslator.ps1
# Deterministic regression tests for template handling.
# ============================================

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Modules\TemplateTranslator.ps1')

$map = Join-Path $root 'Templates\TemplateMap.json'

$input = @'
<!-- {{Campaignbox Golden Age of Piracy}} must remain untouched. -->
{{Campaignbox
|name=Campaignbox Golden Age of Piracy
|title=[[Golden Age of Piracy]]
}}
{{Campaignbox Golden Age of Piracy
|name=Campaignbox Golden Age of Piracy
}}
{{Outer
|nested={{Campaignbox Golden Age of Piracy}}
|link=[[Campaignbox Golden Age of Piracy|Campaignbox Golden Age of Piracy]]
|nestedRuleGuard={{OtherTemplate
|name=Campaignbox Golden Age of Piracy
}}
}}
<nowiki>{{Campaignbox Golden Age of Piracy}}</nowiki>
{{convert|10|kg|lb}}
{{cvt|5|ft|m}}
{{convert|10|kg|lb|abbr=on}}
{{convert|10|to|20|km|mi}}
{{convert|{{formatnum:1000}}|kg|lb}}
{{some_other|10|kg|lb}}
{{test|value=<!-- }} -->|second=value}}
{{test|value=<nowiki>}}</nowiki>|second=value}}
{{test|value=<ref>}}</ref>|second=value}}
{{test|value={{inner|x=1}}|second=value}}
{{test|value=[[A|B]]|second=value}}
'@

$expected = @'
<!-- {{Campaignbox Golden Age of Piracy}} must remain untouched. -->
{{Campaignbox
|name=صندوق حملة العصر الذهبي للقرصنة
|title=[[Golden Age of Piracy]]
}}
{{صندوق حملة العصر الذهبي للقرصنة
|name=Campaignbox Golden Age of Piracy
}}
{{Outer
|nested={{صندوق حملة العصر الذهبي للقرصنة}}
|link=[[Campaignbox Golden Age of Piracy|Campaignbox Golden Age of Piracy]]
|nestedRuleGuard={{OtherTemplate
|name=Campaignbox Golden Age of Piracy
}}
}}
<nowiki>{{Campaignbox Golden Age of Piracy}}</nowiki>
{{حول|10|kg|lb}}
{{حول مختصر|5|ft|m}}
{{حول|10|kg|lb|abbr=on}}
{{حول|10|to|20|km|mi}}
{{حول|{{formatnum:1000}}|kg|lb}}
{{some_other|10|kg|lb}}
{{test|value=<!-- }} -->|second=value}}
{{test|value=<nowiki>}}</nowiki>|second=value}}
{{test|value=<ref>}}</ref>|second=value}}
{{test|value={{inner|x=1}}|second=value}}
{{test|value=[[A|B]]|second=value}}
'@

$output = Convert-WikipediaTemplates -Text $input -MapPath $map

if ($output -ne $expected) {
    Write-Host 'Template test FAILED.' -ForegroundColor Red
    Write-Host 'Expected:'
    Write-Host $expected
    Write-Host 'Actual:'
    Write-Host $output
    exit 1
}

if ($TemplateStats.TemplatesFound -ne 18) { throw "Expected 18 templates, got $($TemplateStats.TemplatesFound)." }
if ($TemplateStats.TemplateNamesChanged -ne 7) { throw "Expected 7 renamed template names, got $($TemplateStats.TemplateNamesChanged)." }
if ($TemplateStats.ParameterValuesChanged -ne 1) { throw "Expected 1 parameter value change, got $($TemplateStats.ParameterValuesChanged)." }

Write-Host 'Template regression tests passed.' -ForegroundColor Green
Write-Host "Templates found: $($TemplateStats.TemplatesFound)"
Write-Host "Template names changed: $($TemplateStats.TemplateNamesChanged)"
Write-Host "Parameter values changed: $($TemplateStats.ParameterValuesChanged)"
