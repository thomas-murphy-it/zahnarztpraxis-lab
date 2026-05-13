<#
=========================================================================
 LAB TROUBLE MAKER — Break/Fix Übung für Thomas
 Zahnarztpraxis Dr. Müller Domain Controller
=========================================================================
 ⚠️ WICHTIG: VOR dem Ausführen Snapshot in VirtualBox machen!
 ⚠️ Skript NUR auf Lab-VM ausführen, NIE auf Produktiv-System!

 Bedienung:
   .\Lab-Trouble-Maker.ps1 -Difficulty Easy
   .\Lab-Trouble-Maker.ps1 -Difficulty Medium
   .\Lab-Trouble-Maker.ps1 -Difficulty Hard

 Hilfe wenn du stuck bist:
   .\Lab-Trouble-Maker.ps1 -ShowLog       # Zeigt was eingebaut wurde
   .\Lab-Trouble-Maker.ps1 -FixAll        # Repariert alles automatisch
=========================================================================
#>

param(
    [ValidateSet("Easy", "Medium", "Hard")]
    [string]$Difficulty = "Easy",

    [switch]$ShowLog,

    [switch]$FixAll
)

# Log-Pfad (versteckt im AppData)
$LogDir  = "$env:ProgramData\TroubleLab"
$LogFile = Join-Path $LogDir "current_session.json"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    attrib +h $LogDir
}

# ===================== TROUBLE-KATALOG =====================
# Jeder Eintrag hat: Difficulty, Symptom, Diagnose-Hinweis, Break-Action, Fix-Action

$Troubles = @{

    # ========== EASY ==========
    "DNS_Dienst_Aus" = @{
        Difficulty = "Easy"
        Symptom    = "Clients können sich nicht mehr anmelden. müllerpraxis.lan wird nicht gefunden."
        Hinweis    = "Welche Dienste laufen normalerweise auf einem DC? Get-Service mit Filter."
        Break      = { Stop-Service -Name "DNS" -Force; Set-Service -Name "DNS" -StartupType Manual }
        Fix        = { Set-Service -Name "DNS" -StartupType Automatic; Start-Service -Name "DNS" }
    }

    "DHCP_Dienst_Aus" = @{
        Difficulty = "Easy"
        Symptom    = "Neue Clients bekommen keine IP-Adresse (169.254.x.x APIPA)."
        Hinweis    = "Get-Service DHCPServer. Wer verteilt die IPs?"
        Break      = { Stop-Service -Name "DHCPServer" -Force; Set-Service -Name "DHCPServer" -StartupType Manual }
        Fix        = { Set-Service -Name "DHCPServer" -StartupType Automatic; Start-Service -Name "DHCPServer" }
    }

    "Anna_Deaktiviert" = @{
        Difficulty = "Easy"
        Symptom    = "Anna Müller ruft an: 'Ich kann mich nicht anmelden, Fehlermeldung Konto deaktiviert.'"
        Hinweis    = "Get-ADUser anna.mueller -Properties Enabled. Was ist der Status?"
        Break      = { Disable-ADAccount -Identity anna.mueller }
        Fix        = { Enable-ADAccount -Identity anna.mueller }
    }

    "Spooler_Aus" = @{
        Difficulty = "Easy"
        Symptom    = "Anrufer aus der Verwaltung: 'Drucken geht nicht mehr.'"
        Hinweis    = "Welcher Dienst ist für Drucker zuständig? Get-Service Print*"
        Break      = { Stop-Service -Name "Spooler" -Force; Set-Service -Name "Spooler" -StartupType Manual }
        Fix        = { Set-Service -Name "Spooler" -StartupType Automatic; Start-Service -Name "Spooler" }
    }

    "Firewall_Ping_Block" = @{
        Difficulty = "Easy"
        Symptom    = "Clients melden 'Server nicht erreichbar.' Ping schlägt fehl."
        Hinweis    = "Was hatten wir am Anfang vom Lab eingerichtet? Get-NetFirewallRule -DisplayName *Ping*"
        Break      = { Disable-NetFirewallRule -DisplayName "Ping erlauben" -ErrorAction SilentlyContinue }
        Fix        = { Enable-NetFirewallRule -DisplayName "Ping erlauben" -ErrorAction SilentlyContinue }
    }

    # ========== MEDIUM ==========
    "Peter_Gesperrt" = @{
        Difficulty = "Medium"
        Symptom    = "Peter Schmidt ruft an: 'Ich bin gesperrt, hab nur 2x falsch getippt!'"
        Hinweis    = "Get-ADUser peter.schmidt -Properties LockedOut, BadLogonCount"
        Break      = {
            # Account lockout simulieren durch 10x falsches Passwort
            1..10 | ForEach-Object {
                try {
                    $cred = New-Object System.Management.Automation.PSCredential("peter.schmidt", (ConvertTo-SecureString "WrongPassword!" -AsPlainText -Force))
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c exit" -Credential $cred -ErrorAction SilentlyContinue -WindowStyle Hidden
                } catch {}
            }
            # Notfalls direkt setzen
            try {
                $userDN = (Get-ADUser peter.schmidt).DistinguishedName
                Set-ADObject -Identity $userDN -Replace @{lockoutTime = [int64]([datetime]::UtcNow.ToFileTimeUtc())}
            } catch {}
        }
        Fix        = { Unlock-ADAccount -Identity peter.schmidt }
    }

    "DNS_Forwarder_Falsch" = @{
        Difficulty = "Medium"
        Symptom    = "Clients können intern alles auflösen, aber Internet geht nicht (z.B. google.de)."
        Hinweis    = "Get-DnsServerForwarder. Welche Forwarder sind eingetragen?"
        Break      = {
            # Original-Forwarder speichern und durch falsche IP ersetzen
            $current = (Get-DnsServerForwarder).IPAddress.IPAddressToString
            Set-Item "HKLM:\SOFTWARE\TroubleLab" -Name "OrigForwarders" -Value ($current -join ",") -Force -ErrorAction SilentlyContinue
            Remove-DnsServerForwarder -IPAddress $current -Force -ErrorAction SilentlyContinue
            Add-DnsServerForwarder -IPAddress "10.99.99.99" -ErrorAction SilentlyContinue
        }
        Fix        = {
            Remove-DnsServerForwarder -IPAddress "10.99.99.99" -Force -ErrorAction SilentlyContinue
            Add-DnsServerForwarder -IPAddress "8.8.8.8","1.1.1.1" -ErrorAction SilentlyContinue
        }
    }

    "GPO_Bildschirmsperre_Unverlinkt" = @{
        Difficulty = "Medium"
        Symptom    = "Niemand wird mehr nach 10 Minuten gesperrt. Compliance-Verstoß!"
        Hinweis    = "Get-GPInheritance -Target 'DC=müllerpraxis,DC=lan' oder GPMC öffnen — welche GPOs sind verlinkt?"
        Break      = {
            try {
                $link = Get-GPInheritance -Target "DC=müllerpraxis,DC=lan" | Select-Object -ExpandProperty GpoLinks | Where-Object { $_.DisplayName -like "*Bildschirm*" }
                if ($link) { Set-GPLink -Name $link.DisplayName -Target "DC=müllerpraxis,DC=lan" -LinkEnabled No }
            } catch {}
        }
        Fix        = {
            try {
                $link = Get-GPInheritance -Target "DC=müllerpraxis,DC=lan" | Select-Object -ExpandProperty GpoLinks | Where-Object { $_.DisplayName -like "*Bildschirm*" }
                if ($link) { Set-GPLink -Name $link.DisplayName -Target "DC=müllerpraxis,DC=lan" -LinkEnabled Yes }
            } catch {}
        }
    }

    "Empfang_NTFS_Permission_Weg" = @{
        Difficulty = "Medium"
        Symptom    = "Anna kann den Empfang-Ordner nicht mehr öffnen. 'Zugriff verweigert.'"
        Hinweis    = "icacls C:\Praxisdaten\Empfang. Wer hat noch Zugriff?"
        Break      = {
            $folder = "C:\Praxisdaten\Empfang"
            if (Test-Path $folder) {
                # Backup der Permissions
                icacls $folder /save "$LogDir\empfang_acl.bak" /T | Out-Null
                # Empfang-Gruppe entfernen
                icacls $folder /remove "müllerpraxis\Empfang" /T | Out-Null
            }
        }
        Fix        = {
            $folder = "C:\Praxisdaten\Empfang"
            if (Test-Path $folder) {
                icacls $folder /grant "müllerpraxis\Empfang:(OI)(CI)F" /T | Out-Null
            }
        }
    }

    # ========== HARD ==========
    "Time_Skew" = @{
        Difficulty = "Hard"
        Symptom    = "Clients können sich nicht anmelden — Kerberos-Fehler. Was, wenn die Zeit nicht stimmt?"
        Hinweis    = "Get-Date auf Server und Client vergleichen. Kerberos toleriert max 5 Min Drift. w32tm /query /status"
        Break      = {
            # Zeit um 30 Minuten zurückstellen
            $newTime = (Get-Date).AddMinutes(-30)
            Set-Date -Date $newTime
        }
        Fix        = {
            # NTP-Sync erzwingen
            Start-Service W32Time -ErrorAction SilentlyContinue
            w32tm /resync /force | Out-Null
        }
    }

    "Veeam_Backup_Service_Aus" = @{
        Difficulty = "Hard"
        Symptom    = "Backup-Job läuft nicht mehr nachts. Im Veeam Agent: kein Status sichtbar."
        Hinweis    = "Get-Service *Veeam*. Welche Dienste sollten laufen?"
        Break      = {
            Get-Service -Name "*Veeam*" -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
                Set-Service $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
            }
        }
        Fix        = {
            Get-Service -Name "*Veeam*" -ErrorAction SilentlyContinue | ForEach-Object {
                Set-Service $_.Name -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service $_.Name -ErrorAction SilentlyContinue
            }
        }
    }

    "Sarah_Password_Expired" = @{
        Difficulty = "Hard"
        Symptom    = "Sarah Klein bekommt beim Login: 'Passwort muss geändert werden' — aber sie hat es gerade erst gesetzt."
        Hinweis    = "Get-ADUser sarah.klein -Properties PasswordExpired, PasswordLastSet, msDS-UserPasswordExpiryTimeComputed"
        Break      = { Set-ADUser -Identity sarah.klein -ChangePasswordAtLogon $true }
        Fix        = { Set-ADUser -Identity sarah.klein -ChangePasswordAtLogon $false }
    }
}

# ===================== HAUPTLOGIK =====================

function Show-Log {
    if (-not (Test-Path $LogFile)) {
        Write-Host "Kein aktiver Trouble-Session-Log gefunden." -ForegroundColor Yellow
        return
    }
    $session = Get-Content $LogFile | ConvertFrom-Json
    Write-Host ""
    Write-Host "=== AKTUELLE TROUBLE-SESSION ===" -ForegroundColor Cyan
    Write-Host "Gestartet: $($session.Timestamp)" -ForegroundColor Gray
    Write-Host "Schwierigkeit: $($session.Difficulty)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Eingebaute Probleme:" -ForegroundColor Yellow
    foreach ($name in $session.Issues) {
        $t = $Troubles[$name]
        Write-Host ""
        Write-Host "  [$name]" -ForegroundColor Magenta
        Write-Host "    Symptom: $($t.Symptom)" -ForegroundColor White
        Write-Host "    Hinweis: $($t.Hinweis)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Fix-All {
    if (-not (Test-Path $LogFile)) {
        Write-Host "Kein aktiver Trouble-Session-Log gefunden — nichts zu reparieren." -ForegroundColor Yellow
        return
    }
    $session = Get-Content $LogFile | ConvertFrom-Json
    Write-Host "Repariere $($session.Issues.Count) Probleme..." -ForegroundColor Cyan
    foreach ($name in $session.Issues) {
        Write-Host "  Fix: $name" -ForegroundColor Green
        try { & $Troubles[$name].Fix } catch { Write-Host "    Fehler: $_" -ForegroundColor Red }
    }
    Remove-Item $LogFile -Force
    Write-Host "Alle Probleme repariert. Session-Log gelöscht." -ForegroundColor Green
}

# Modi
if ($ShowLog) { Show-Log; return }
if ($FixAll)  { Fix-All; return }

# Hauptmodus: Probleme einbauen
$count = switch ($Difficulty) {
    "Easy"   { 1 }
    "Medium" { 2 }
    "Hard"   { 3 }
}

$available = $Troubles.GetEnumerator() | Where-Object { $_.Value.Difficulty -eq $Difficulty }
if (-not $available) {
    Write-Host "Keine Probleme für Schwierigkeit '$Difficulty' verfügbar." -ForegroundColor Red
    return
}

$selected = $available | Get-Random -Count ([Math]::Min($count, $available.Count))

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " LAB TROUBLE MAKER" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Schwierigkeit: $Difficulty"
Write-Host " Probleme:      $($selected.Count)"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Baue Probleme ein..." -ForegroundColor Yellow

foreach ($trouble in $selected) {
    Write-Host "  Injektion: $($trouble.Name)" -ForegroundColor DarkGray
    try { & $trouble.Value.Break } catch { Write-Host "    Warnung: $_" -ForegroundColor DarkYellow }
}

$session = @{
    Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Difficulty = $Difficulty
    Issues     = @($selected.Name)
}
$session | ConvertTo-Json | Out-File $LogFile -Encoding UTF8

Write-Host ""
Write-Host "Fertig. $($selected.Count) Probleme eingebaut." -ForegroundColor Green
Write-Host ""
Write-Host "Deine Aufgabe:" -ForegroundColor Yellow
Write-Host "  1. Finde was kaputt ist (Tools: Get-Service, Get-ADUser, Get-EventLog, ping, nslookup, dcdiag)"
Write-Host "  2. Diagnose: was ist die Ursache?"
Write-Host "  3. Repariere — und erkläre warum dein Fix funktioniert"
Write-Host ""
Write-Host "Stuck nach 30 Minuten?" -ForegroundColor DarkGray
Write-Host "  .\Lab-Trouble-Maker.ps1 -ShowLog   # Zeigt eingebaute Probleme"
Write-Host "  .\Lab-Trouble-Maker.ps1 -FixAll    # Repariert alles automatisch"
Write-Host ""
