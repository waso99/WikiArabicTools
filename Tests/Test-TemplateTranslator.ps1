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

if ($TemplateStats.TemplatesFound -ne 5) { throw "Expected 5 templates, got $($TemplateStats.TemplatesFound)." }
if ($TemplateStats.TemplateNamesChanged -ne 2) { throw "Expected 2 renamed template names, got $($TemplateStats.TemplateNamesChanged)." }
if ($TemplateStats.ParameterValuesChanged -ne 1) { throw "Expected 1 parameter value change, got $($TemplateStats.ParameterValuesChanged)." }

Write-Host 'Template regression tests passed.' -ForegroundColor Green
Write-Host "Templates found: $($TemplateStats.TemplatesFound)"
Write-Host "Template names changed: $($TemplateStats.TemplateNamesChanged)"
Write-Host "Parameter values changed: $($TemplateStats.ParameterValuesChanged)"
