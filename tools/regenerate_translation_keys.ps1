# Régénère scripts/autoload/translation_keys.gd depuis assets/menu/traduction.csv
$root = Split-Path -Parent $PSScriptRoot
$csvPath = Join-Path $root "assets\menu\traduction.csv"
$outPath = Join-Path $root "scripts\autoload\translation_keys.gd"

$csv = Get-Content $csvPath -Encoding UTF8
$en = @{}; $fr = @{}; $de = @{}
foreach ($line in $csv) {
	if ($line -match '^\s*#' -or $line -match '^\s*$' -or $line -match '^id;') { continue }
	$parts = $line -split ';', 4
	if ($parts.Count -lt 4) { continue }
	$key = $parts[0].Trim()
	if ($key -eq '') { continue }
	$en[$key] = $parts[1]
	$fr[$key] = $parts[2]
	$de[$key] = $parts[3]
}

function Escape-Gd([string]$s) {
	return ($s -replace '\\', '\\\\' -replace '"', '\"')
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("extends RefCounted")
[void]$sb.AppendLine("class_name TranslationKeys")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Généré depuis assets/menu/traduction.csv — relancer tools/regenerate_translation_keys.ps1 après modification du CSV.")
[void]$sb.AppendLine("")

foreach ($loc in @(@{ n = 'EN'; h = $en }, @{ n = 'FR'; h = $fr }, @{ n = 'DE'; h = $de })) {
	[void]$sb.AppendLine("const MSG_$($loc.n) := {")
	foreach ($k in ($loc.h.Keys | Sort-Object)) {
		[void]$sb.AppendLine('	"' + (Escape-Gd $k) + '": "' + (Escape-Gd $loc.h[$k]) + '",')
	}
	[void]$sb.AppendLine("}")
	[void]$sb.AppendLine("")
}

[void]$sb.AppendLine("static func apply_to_server() -> int:")
[void]$sb.AppendLine("	var count := 0")
[void]$sb.AppendLine('	for loc in [{"code": "en", "msg": MSG_EN}, {"code": "fr", "msg": MSG_FR}, {"code": "de", "msg": MSG_DE}]:')
[void]$sb.AppendLine("		var translation := Translation.new()")
[void]$sb.AppendLine("		translation.locale = loc.code")
[void]$sb.AppendLine("		for key in loc.msg:")
[void]$sb.AppendLine("			translation.add_message(key, str(loc.msg[key]))")
[void]$sb.AppendLine("			count += 1")
[void]$sb.AppendLine("		TranslationServer.add_translation(translation)")
[void]$sb.AppendLine("	return count")

[System.IO.File]::WriteAllText($outPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $outPath ($($en.Count) keys per locale)"
