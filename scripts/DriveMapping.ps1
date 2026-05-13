# ============================================================
# Netzlaufwerk-Mapping Logon Script
# Zahnarztpraxis Dr. Mueller
# Mappt automatisch das richtige Laufwerk basierend auf Gruppenmitgliedschaft
# ============================================================

$ServerName = "WIN-H0C86VCM0FO"
$Domain     = "MUELLERPRAXIS"

# Gruppe → Laufwerkbuchstabe + Unterordner
$Mappings = @{
    "Empfang"    = @{ Letter = "E"; Folder = "Empfang"    }
    "Verwaltung" = @{ Letter = "V"; Folder = "Verwaltung" }
    "Aerzte"     = @{ Letter = "Y"; Folder = "Aerzte"     }
    "Abrechnung" = @{ Letter = "A"; Folder = "Abrechnung" }
    "Behandlung" = @{ Letter = "B"; Folder = "Behandlung" }
}

# Aktuelle Gruppen des angemeldeten Users ermitteln
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$UserGroups = $Identity.Groups | ForEach-Object {
    try { $_.Translate([System.Security.Principal.NTAccount]).Value }
    catch { $null }
} | Where-Object { $_ -ne $null }

# Laufwerke mappen
foreach ($GroupName in $Mappings.Keys) {

    $FullGroupName = "$Domain\$GroupName"
    $Letter        = $Mappings[$GroupName].Letter
    $UNCPath       = "\\$ServerName\Praxisdaten\$($Mappings[$GroupName].Folder)"

    if ($UserGroups -contains $FullGroupName) {

        # Altes Mapping auf dem Buchstaben entfernen falls vorhanden
        $existing = Get-PSDrive -Name $Letter -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-PSDrive -Name $Letter -Force -ErrorAction SilentlyContinue
        }

        # Laufwerk mappen (persistent = bleibt nach Reboot)
        try {
            New-PSDrive -Name $Letter `
                        -PSProvider FileSystem `
                        -Root $UNCPath `
                        -Persist `
                        -ErrorAction Stop | Out-Null

            Write-EventLog -LogName Application `
                           -Source "DriveMapping" `
                           -EventId 1000 `
                           -EntryType Information `
                           -Message "Laufwerk $Letter`: gemappt auf $UNCPath fuer $env:USERNAME" `
                           -ErrorAction SilentlyContinue
        }
        catch {
            Write-EventLog -LogName Application `
                           -Source "DriveMapping" `
                           -EventId 1001 `
                           -EntryType Error `
                           -Message "Fehler beim Mapping $Letter`: auf $UNCPath - $_" `
                           -ErrorAction SilentlyContinue
        }
    }
}
