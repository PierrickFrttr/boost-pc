# BoostPC - nettoyage et accélération de Windows 10 (dossier autonome, à copier sur chaque PC)
# Menu à options : chaque action se coche ou se décoche.
# Aucun document personnel n'est touché, sauf l'option 22 (profils inutilisés) qui exige une confirmation écrite.

$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Boost PC'

$Racine       = Split-Path -Parent $PSCommandPath
$Dossier      = Join-Path $Racine 'Rapports'
$FichierChoix = Join-Path $Racine 'choix.txt'
New-Item -ItemType Directory -Force -Path $Dossier | Out-Null
$Conseils = New-Object System.Collections.Generic.List[string]
$estAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# --- Outils ------------------------------------------------------------------
function Log([string]$texte, [string]$couleur = 'Gray') {
    Write-Host $texte -ForegroundColor $couleur
    Add-Content -Path $Rapport -Value $texte -Encoding UTF8
}
function Etape([string]$titre) { Log ''; Log "=== $titre ===" 'Cyan' }
function EspaceLibre { [math]::Round((Get-PSDrive C).Free / 1GB, 2) }
function Vider([string]$motif) {
    foreach ($p in (Resolve-Path -Path $motif -ErrorAction SilentlyContinue)) {
        Get-ChildItem -LiteralPath $p.Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function RegSet([string]$cle, [string]$nom, $valeur, [string]$type = 'DWord') {
    if (-not (Test-Path $cle)) { New-Item -Path $cle -Force | Out-Null }
    Set-ItemProperty -Path $cle -Name $nom -Value $valeur -Type $type
}
function U32($x) { [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$x), 0) }

# Programmes lancés au démarrage, avec la clé "StartupApproved" qui permet de les désactiver
# exactement comme le Gestionnaire des tâches (réversible, rien n'est désinstallé).
function ElementsDemarrage {
    $sa = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Type = 'Reg';     Chemin = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Ok = "HKCU:\$sa\Run";           Admin = $false },
        @{ Type = 'Reg';     Chemin = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Ok = "HKLM:\$sa\Run";           Admin = $true  },
        @{ Type = 'Reg';     Chemin = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Ok = "HKLM:\$sa\Run32";         Admin = $true  },
        @{ Type = 'Dossier'; Chemin = [Environment]::GetFolderPath('Startup');                           Ok = "HKCU:\$sa\StartupFolder"; Admin = $false },
        @{ Type = 'Dossier'; Chemin = [Environment]::GetFolderPath('CommonStartup');                     Ok = "HKLM:\$sa\StartupFolder"; Admin = $true  }
    )
    foreach ($s in $sources) {
        if ($s.Admin -and -not $estAdmin) { continue }
        if ($s.Type -eq 'Reg') {
            $v = Get-ItemProperty -Path $s.Chemin
            if (-not $v) { continue }
            $items = $v.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
                     ForEach-Object { [pscustomobject]@{ Nom = $_.Name; Commande = "$($_.Value)" } }
        } else {
            $items = Get-ChildItem -LiteralPath $s.Chemin -File -Force | Where-Object Name -ne 'desktop.ini' |
                     ForEach-Object { [pscustomobject]@{ Nom = $_.Name; Commande = $_.FullName } }
        }
        foreach ($i in $items) {
            $etat = (Get-ItemProperty -Path $s.Ok -Name $i.Nom).($i.Nom)
            $i | Add-Member -NotePropertyName Ok    -NotePropertyValue $s.Ok
            $i | Add-Member -NotePropertyName Actif -NotePropertyValue (-not ($etat -and ($etat[0] -band 1)))
            $i
        }
    }
}
function DesactiverDemarrage($element) {
    RegSet $element.Ok $element.Nom ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) 'Binary'
}

# --- Liste des options -------------------------------------------------------
# A = droits admin requis, R = cochée dans "recommandé", C = cochée dans "complet"
$Options = @(
    @{ N = 1;  G = 'NETTOYAGE';             A = $false; R = $true;  C = $true;  T = 'Fichiers temporaires et caches des navigateurs' }
    @{ N = 2;  G = 'NETTOYAGE';             A = $false; R = $true;  C = $true;  T = 'Vider la corbeille' }
    @{ N = 3;  G = 'NETTOYAGE';             A = $true;  R = $true;  C = $true;  T = 'Cache des mises à jour Windows' }
    @{ N = 4;  G = 'NETTOYAGE';             A = $true;  R = $false; C = $true;  T = 'Nettoyage de disque Windows (Windows.old...) - long' }
    @{ N = 5;  G = 'DÉMARRAGE';             A = $false; R = $true;  C = $true;  T = 'Désactiver les programmes inutiles connus (Spotify, Steam...)' }
    @{ N = 6;  G = 'DÉMARRAGE';             A = $false; R = $false; C = $false; T = 'Choisir un par un les programmes à désactiver (questions)' }
    @{ N = 7;  G = 'DÉMARRAGE';             A = $true;  R = $true;  C = $true;  T = 'Désactiver les tâches de mise à jour cachées (Adobe, CCleaner...)' }
    @{ N = 8;  G = 'DÉMARRAGE';             A = $true;  R = $true;  C = $true;  T = 'Activer le démarrage rapide de Windows' }
    @{ N = 9;  G = 'DÉMARRAGE';             A = $true;  R = $true;  C = $true;  T = 'Menu de démarrage : attente réduite à 3 secondes' }
    @{ N = 10; G = 'RÉGLAGES';              A = $false; R = $true;  C = $true;  T = 'Mode Performances élevées (PC fixes uniquement)' }
    @{ N = 11; G = 'RÉGLAGES';              A = $false; R = $true;  C = $true;  T = 'Couper les pubs et suggestions de Windows' }
    @{ N = 12; G = 'RÉGLAGES';              A = $true;  R = $true;  C = $true;  T = 'Couper l''indexation de recherche (disque dur HDD seulement)' }
    @{ N = 13; G = 'RÉGLAGES';              A = $false; R = $false; C = $false; T = 'Réduire les effets visuels (moins joli, plus réactif)' }
    @{ N = 14; G = 'RÉGLAGES';              A = $false; R = $false; C = $false; T = 'Couper les applications en arrière-plan' }
    @{ N = 15; G = 'RÉGLAGES';              A = $true;  R = $false; C = $false; T = 'Supprimer les applis préinstallées (Candy Crush, Xbox...)' }
    @{ N = 16; G = 'RÉGLAGES';              A = $true;  R = $false; C = $false; T = 'Réduire la télémétrie (envoi de données à Microsoft)' }
    @{ N = 17; G = 'SÉCURITÉ ET RÉPARATION'; A = $true;  R = $true;  C = $true;  T = 'Point de restauration avant les modifications' }
    @{ N = 18; G = 'SÉCURITÉ ET RÉPARATION'; A = $true;  R = $true;  C = $true;  T = 'Analyse antivirus rapide (Windows Defender)' }
    @{ N = 19; G = 'SÉCURITÉ ET RÉPARATION'; A = $true;  R = $false; C = $true;  T = 'Installer les mises à jour Windows en attente - long' }
    @{ N = 20; G = 'SÉCURITÉ ET RÉPARATION'; A = $true;  R = $false; C = $true;  T = 'Réparer les fichiers Windows (DISM + SFC) - long' }
    @{ N = 21; G = 'SÉCURITÉ ET RÉPARATION'; A = $true;  R = $false; C = $true;  T = 'Optimiser le disque (défragmentation / TRIM) - long' }
    @{ N = 22; G = 'SALLE INFORMATIQUE';    A = $true;  R = $false; C = $false; T = 'Supprimer les profils inutilisés depuis 3 mois (confirmation)' }
) | ForEach-Object { [pscustomobject]$_ }

$Sel = New-Object 'System.Collections.Generic.HashSet[int]'
function Autorisee($o) { $estAdmin -or -not $o.A }
function Preselection([string]$p) {
    $Sel.Clear()
    foreach ($o in $Options) {
        $ok = switch ($p) { 'R' { $o.R } 'C' { $o.C } 'T' { $true } default { $false } }
        if ($ok -and (Autorisee $o)) { [void]$Sel.Add($o.N) }
    }
}
function Coche([int]$n) { $Sel.Contains($n) }

# Sélection de départ : celle du dernier lancement si elle existe, sinon "recommandé"
Preselection 'R'
if (Test-Path $FichierChoix) {
    $Sel.Clear()
    foreach ($n in ((Get-Content $FichierChoix -Raw) -split '\D+' | Where-Object { $_ })) {
        $o = $Options | Where-Object N -eq ([int]$n)
        if ($o -and (Autorisee $o)) { [void]$Sel.Add($o.N) }
    }
}

# --- Fenêtre de choix (cases à cocher à la souris) ----------------------------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text            = "Boost PC - $env:COMPUTERNAME"
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.TopMost         = $true
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 10)
$form.ClientSize      = New-Object System.Drawing.Size(1000, 600)
$gras = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

function Etiquette([string]$texte, [int]$x, [int]$y, $police, $couleur) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $texte; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true
    if ($police)  { $l.Font = $police }
    if ($couleur) { $l.ForeColor = $couleur }
    $form.Controls.Add($l)
}
function Bouton([string]$texte, [int]$x, [int]$largeur, [scriptblock]$action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $texte; $b.Location = New-Object System.Drawing.Point($x, 540); $b.Size = New-Object System.Drawing.Size($largeur, 40)
    $b.Add_Click($action); $form.Controls.Add($b); $b
}

Etiquette 'Cochez ce que vous voulez faire, puis cliquez sur LANCER.' 20 12 $gras $null
if (-not $estAdmin) {
    Etiquette 'Mode limité (sans droits administrateur) : les options grisées ne sont pas disponibles.' 20 36 $null ([System.Drawing.Color]::DarkOrange)
}

# Deux colonnes : nettoyage + démarrage à gauche, le reste à droite
$colonne = @{ 'NETTOYAGE' = 0; 'DÉMARRAGE' = 0; 'RÉGLAGES' = 1; 'SÉCURITÉ ET RÉPARATION' = 1; 'SALLE INFORMATIQUE' = 1 }
$y = @(64, 64)
$cases = @{}
$groupe = ''
foreach ($o in $Options) {
    $c = $colonne[$o.G]; $x = 20 + $c * 495
    if ($o.G -ne $groupe) {
        $groupe = $o.G
        Etiquette $groupe $x ($y[$c] + 6) $gras ([System.Drawing.Color]::SteelBlue)
        $y[$c] += 32
    }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text     = if (Autorisee $o) { $o.T } else { "$($o.T)  (admin)" }
    $cb.Location = New-Object System.Drawing.Point(($x + 10), $y[$c])
    $cb.Size     = New-Object System.Drawing.Size(480, 24)
    $cb.Checked  = Coche $o.N
    $cb.Enabled  = Autorisee $o
    $form.Controls.Add($cb)
    $cases[$o.N] = $cb
    $y[$c] += 26
}

function AppliquerPreselection([string]$p) {
    Preselection $p
    foreach ($o in $Options) { $cases[$o.N].Checked = Coche $o.N }
}
[void](Bouton 'Recommandé'        20 120 { AppliquerPreselection 'R' })
[void](Bouton 'Complet (long)'   148 130 { AppliquerPreselection 'C' })
[void](Bouton 'Tout cocher'      286 110 { AppliquerPreselection 'T' })
[void](Bouton 'Tout décocher'    404 120 { AppliquerPreselection 'A' })
[void](Bouton 'Diagnostic seul'  600 150 { $form.Tag = 'D'; $form.Close() })
$lancer = Bouton 'LANCER' 765 215 { $form.Tag = 'L'; $form.Close() }
$lancer.Font = $gras; $lancer.BackColor = [System.Drawing.Color]::SeaGreen; $lancer.ForeColor = [System.Drawing.Color]::White
$form.AcceptButton = $lancer

[void]$form.ShowDialog()
$action = $form.Tag
if (-not $action) { exit }   # fenêtre fermée avec la croix

$Sel.Clear()
if ($action -eq 'L') {
    foreach ($o in $Options) { if ($cases[$o.N].Checked -and $cases[$o.N].Enabled) { [void]$Sel.Add($o.N) } }
    Set-Content -Path $FichierChoix -Value (($Sel | Sort-Object) -join ' ')
}

$Rapport = Join-Path $Dossier ('{0}_{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
$chrono  = [Diagnostics.Stopwatch]::StartNew()
Clear-Host
Log "Rapport Boost PC - $env:COMPUTERNAME - $(Get-Date -Format 'dd/MM/yyyy HH:mm') - $(if ($estAdmin) {'administrateur'} else {"MODE LIMITÉ (utilisateur $env:USERNAME)"})"
if ($Sel.Count -eq 0) { Log 'Diagnostic seul : rien n''a été modifié.' }
else {
    Log 'Options choisies :'
    foreach ($o in $Options) { if (Coche $o.N) { Log "   $($o.N). $($o.T)" } }
}

# --- Diagnostic (toujours) ---------------------------------------------------
Etape 'DIAGNOSTIC'
$os  = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
$portable = [bool](Get-CimInstance Win32_Battery)
$joursAllume = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
Log "Windows     : $($os.Caption) (version $($os.Version))"
Log "Processeur  : $cpu"
Log "Mémoire RAM : $ram Go"
Log "Type de PC  : $(if ($portable) {'portable'} else {'fixe'})"

$numDisque  = (Get-Partition -DriveLetter C).DiskNumber
$disque     = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$numDisque" }
$typeDisque = "$($disque.MediaType)"
$libreAvant = EspaceLibre
$totalC     = [math]::Round((Get-PSDrive C).Used / 1GB + $libreAvant, 1)
Log "Disque C:   : $($disque.FriendlyName) - type $typeDisque - état $($disque.HealthStatus)"
Log "Espace libre: $libreAvant Go sur $totalC Go"
Log "Allumé depuis le dernier vrai redémarrage : $joursAllume jours"

$evtBoot = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1
if ($evtBoot) {
    $ms = ([xml]$evtBoot.ToXml()).Event.EventData.Data | Where-Object Name -eq 'BootTime' | Select-Object -ExpandProperty '#text'
    if ($ms) { Log ("Dernier démarrage mesuré par Windows : {0} secondes" -f [math]::Round($ms / 1000)) }
}

$antivirus = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object -ExpandProperty displayName -Unique)
Log "Antivirus   : $($antivirus -join ', ')"

$demarrage = @(ElementsDemarrage | Where-Object Actif)
Log "Programmes actifs au démarrage ($($demarrage.Count)) :"
foreach ($d in $demarrage) { Log "   - $($d.Nom)" }

$redemarrageEnAttente = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')

if ($typeDisque -eq 'HDD') {
    $Conseils.Add("DISQUE DUR MÉCANIQUE (HDD) : c'est très probablement LA cause principale de la lenteur. Le remplacer par un SSD (environ 25-40 euros) divise le temps de démarrage par 5 à 10. Aucun nettoyage n'aura un effet comparable.")
}
if ($disque.HealthStatus -and "$($disque.HealthStatus)" -ne 'Healthy') {
    $Conseils.Add("ATTENTION : le disque signale un problème de santé ($($disque.HealthStatus)). Sauvegardez les données et prévoyez son remplacement.")
}
if ($ram -lt 6) { $Conseils.Add("Seulement $ram Go de RAM : Windows 10 est à l'étroit. Passer à 8 Go améliore beaucoup la fluidité.") }
if ($libreAvant / $totalC -lt 0.15) { $Conseils.Add("Disque C: presque plein (moins de 15 % libre) : Windows ralentit fortement. Supprimez ou déplacez des fichiers volumineux.") }
if ($antivirus.Count -gt 1) { $Conseils.Add("Plusieurs antivirus détectés ($($antivirus -join ', ')) : ils se gênent et ralentissent tout. N'en gardez qu'un (Windows Defender suffit).") }
if ($demarrage.Count -gt 8) { $Conseils.Add("$($demarrage.Count) programmes au démarrage : relancez Boost PC avec l'option 6 pour les trier un par un.") }
if ($joursAllume -gt 7) { $Conseils.Add("Le PC n'a pas vraiment redémarré depuis $joursAllume jours (l'arrêt rapide de Windows ne remet pas à zéro). Faites « Redémarrer » régulièrement.") }
if (-not $estAdmin -and $Sel.Count) { $Conseils.Add("Nettoyage fait SANS droits administrateur : les gains les plus importants n'ont pas pu être faits. Montrez ce rapport au responsable informatique pour qu'il lance le programme avec un compte administrateur.") }
if ($redemarrageEnAttente) { $Conseils.Add("Des mises à jour Windows attendent un redémarrage : redémarrez le PC (cela peut prendre du temps la première fois).") }

# --- Actions -----------------------------------------------------------------
if ($Sel.Count) {

    if (Coche 17) {
        Etape 'POINT DE RESTAURATION (sécurité)'
        Checkpoint-Computer -Description 'Avant Boost PC' -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue
        if ($?) { Log 'Point de restauration créé.' 'Green' } else { Log 'Point de restauration impossible (désactivé sur ce PC ou déjà créé aujourd''hui) - on continue.' 'Yellow' }
    }

    # Les options qui posent des questions passent en premier : ensuite le PC peut travailler seul.
    if (Coche 6) {
        Etape 'PROGRAMMES AU DÉMARRAGE : CHOIX UN PAR UN'
        $elements = @(ElementsDemarrage | Where-Object { $_.Actif -and $_.Nom -notmatch 'SecurityHealth|Windows Defender' })
        if (-not $elements) { Log 'Aucun programme actif au démarrage.' }
        foreach ($e in $elements) {
            $cmd = $e.Commande; if ($cmd.Length -gt 90) { $cmd = $cmd.Substring(0, 87) + '...' }
            Write-Host ''
            Write-Host "  $($e.Nom)" -ForegroundColor White
            Write-Host "  $cmd" -ForegroundColor DarkGray
            $r = Read-Host '  Désactiver au démarrage ? (O/N)'
            if ("$r".Trim().ToUpper() -eq 'O') { DesactiverDemarrage $e; Log "   Désactivé : $($e.Nom)" 'Green' }
            else { Log "   Conservé  : $($e.Nom)" }
        }
    }

    if (Coche 22) {
        Etape 'PROFILS D''UTILISATEURS INUTILISÉS DEPUIS PLUS DE 3 MOIS'
        $limite = (Get-Date).AddDays(-90)
        $vieux = @(foreach ($p in (Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special -and -not $_.Loaded -and $_.LocalPath -like 'C:\Users\*' })) {
            $k = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($p.SID)"
            $date = $null
            if ($k.LocalProfileUnloadTimeHigh) {
                $date = [DateTime]::FromFileTime(([int64](U32 $k.LocalProfileUnloadTimeHigh) -shl 32) -bor [int64](U32 $k.LocalProfileUnloadTimeLow))
            }
            if (-not $date) { $date = $p.LastUseTime }
            if ($date -and $date -lt $limite) { [pscustomobject]@{ Profil = $p; Dossier = $p.LocalPath; Date = $date } }
        })
        if (-not $vieux) { Log 'Aucun profil inutilisé depuis plus de 3 mois.' 'Green' }
        else {
            foreach ($v in $vieux) { Log ("   {0}   (dernière utilisation : {1:dd/MM/yyyy})" -f $v.Dossier, $v.Date) }
            Write-Host '  ATTENTION : documents, bureau et fichiers de ces comptes seront effacés définitivement.' -ForegroundColor Red
            Write-Host '  (les comptes eux-mêmes ne sont pas supprimés : un nouveau profil vide sera recréé à la prochaine connexion)' -ForegroundColor Red
            $r = Read-Host '  Tapez SUPPRIMER pour confirmer, ou Entrée pour annuler'
            if ("$r".Trim().ToUpper() -eq 'SUPPRIMER') {
                foreach ($v in $vieux) {
                    Remove-CimInstance -InputObject $v.Profil
                    if ($?) { Log "   Supprimé : $($v.Dossier)" 'Green' } else { Log "   Échec    : $($v.Dossier)" 'Yellow' }
                }
            } else { Log '   Annulé : aucun profil supprimé.' }
        }
    }

    Log ''
    Log 'Plus aucune question avant la fin : vous pouvez laisser le PC travailler.' 'Yellow'

    if (Coche 19) {
        Etape 'MISES À JOUR WINDOWS EN ATTENTE'
        Log 'Recherche des mises à jour (plusieurs minutes possibles)...'
        try {
            $session  = New-Object -ComObject Microsoft.Update.Session
            $resultat = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
            if ($resultat.Updates.Count -eq 0) { Log 'Windows est à jour.' 'Green' }
            else {
                $liste = New-Object -ComObject Microsoft.Update.UpdateColl
                foreach ($u in $resultat.Updates) {
                    if (-not $u.EulaAccepted) { $u.AcceptEula() }
                    [void]$liste.Add($u); Log "   - $($u.Title)"
                }
                Log 'Téléchargement...'
                $dl = $session.CreateUpdateDownloader(); $dl.Updates = $liste; [void]$dl.Download()
                Log 'Installation...'
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $liste; $r = $inst.Install()
                Log "Installation terminée (code $($r.ResultCode) : 2 = réussi, 3 = réussi en partie, 4 = échec)." 'Green'
                if ($r.RebootRequired) { $Conseils.Add('Les mises à jour installées demandent un redémarrage.') }
            }
        } catch { Log "Mises à jour impossibles (pas d'Internet ou service bloqué) : $($_.Exception.Message)" 'Yellow' }
    }

    if ((Coche 1) -or (Coche 2) -or (Coche 3)) { Etape 'NETTOYAGE' }
    if (Coche 1) {
        Log 'Fichiers temporaires...'
        # Sans droits admin, seuls les dossiers de l'utilisateur actuel sont accessibles : les autres sont ignorés.
        Vider 'C:\Users\*\AppData\Local\Temp'
        Vider 'C:\Users\*\AppData\Local\CrashDumps'
        Vider 'C:\Users\*\AppData\Local\Microsoft\Windows\WER\ReportArchive'
        if ($estAdmin) {
            Vider 'C:\Windows\Temp'
            Vider 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive'
            Vider 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
        }
        Log 'Caches des navigateurs (mots de passe, historique et favoris conservés)...'
        foreach ($nav in 'Google\Chrome', 'Microsoft\Edge') {
            foreach ($c in 'Cache', 'Code Cache', 'GPUCache') { Vider "C:\Users\*\AppData\Local\$nav\User Data\*\$c" }
        }
        Vider 'C:\Users\*\AppData\Local\Mozilla\Firefox\Profiles\*\cache2'
    }
    if (Coche 3) {
        Log 'Cache des mises à jour Windows...'
        Stop-Service wuauserv, bits -Force
        Vider 'C:\Windows\SoftwareDistribution\Download'
        Start-Service wuauserv, bits
        Delete-DeliveryOptimizationCache -Force
    }
    if (Coche 2) { Log 'Corbeille...'; Clear-RecycleBin -Force }
    if ((Coche 1) -or (Coche 2) -or (Coche 3)) { Log "Espace libéré : $([math]::Round((EspaceLibre) - $libreAvant, 2)) Go" 'Green' }

    if (Coche 4) {
        Etape 'NETTOYAGE DE DISQUE WINDOWS'
        Log 'Peut durer longtemps, la fenêtre peut sembler figée : patientez.' 'Yellow'
        Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches' |
            ForEach-Object { Set-ItemProperty -Path $_.PSPath -Name StateFlags0099 -Value 2 -Type DWord }
        Start-Process cleanmgr.exe -ArgumentList '/sagerun:99' -Wait
        Log 'Nettoyage de disque terminé.' 'Green'
    }

    if (Coche 5) {
        Etape 'PROGRAMMES INUTILES CONNUS AU DÉMARRAGE'
        $inutiles = 'Spotify', 'Discord', 'Steam', 'Skype', 'EpicGames', 'uTorrent', 'BitTorrent', 'CCleaner',
                    'AdobeAAMUpdater', 'Adobe Acrobat Synchronizer', 'AdobeGCInvoker', 'iTunesHelper', 'Opera',
                    'MicrosoftEdgeAutoLaunch', 'com.squirrel.Teams.Teams', 'Origin', 'Battle.net', 'GoogleDriveSync'
        $nb = 0
        foreach ($e in (ElementsDemarrage | Where-Object Actif)) {
            $nom = $e.Nom
            if ($inutiles | Where-Object { $nom -like "*$_*" }) { DesactiverDemarrage $e; Log "   Désactivé : $nom" 'Green'; $nb++ }
        }
        if ($nb -eq 0) { Log 'Aucun programme inutile connu trouvé.' }
    }

    if (Coche 7) {
        Etape 'TÂCHES DE MISE À JOUR CACHÉES'
        # Les mises à jour des navigateurs (Chrome, Edge, Firefox) sont volontairement conservées : sécurité.
        $motifs = 'Adobe Acrobat Update', 'AdobeGCInvoker', 'CCleaner', 'Opera.*(scheduled|Autoupdate)',
                  'Dropbox.*Update', 'Firefox Default Browser Agent', 'AppleSoftwareUpdate', 'Spotify'
        $nb = 0
        foreach ($t in (Get-ScheduledTask | Where-Object State -ne 'Disabled')) {
            $nom = $t.TaskName
            if ($motifs | Where-Object { $nom -match $_ }) { Disable-ScheduledTask -InputObject $t | Out-Null; Log "   Désactivée : $nom" 'Green'; $nb++ }
        }
        if ($nb -eq 0) { Log 'Aucune tâche inutile trouvée.' }
    }

    if (Coche 8) {
        Etape 'DÉMARRAGE RAPIDE'
        if (-not (Test-Path 'C:\hiberfil.sys')) { powercfg /h on | Out-Null; powercfg /h /type reduced | Out-Null }
        RegSet 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1
        Log 'Démarrage rapide activé (effet après le prochain « Arrêter »).' 'Green'
    }

    if (Coche 9) {
        Etape 'MENU DE DÉMARRAGE'
        bcdedit /timeout 3 | Out-Null
        if ($LASTEXITCODE -eq 0) { Log 'Attente du menu de démarrage réduite à 3 secondes.' 'Green' } else { Log 'Modification refusée.' 'Yellow' }
    }

    if ((Coche 10) -or (Coche 11) -or (Coche 12) -or (Coche 13) -or (Coche 14) -or (Coche 15) -or (Coche 16)) { Etape 'RÉGLAGES' }
    if (Coche 10) {
        if ($portable) { Log 'PC portable : mode d''alimentation laissé tel quel (préserve la batterie).' }
        else {
            powercfg /setactive SCHEME_MIN 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Log 'Mode d''alimentation : Performances élevées.' 'Green' } else { Log 'Mode d''alimentation : modification refusée sur ce PC.' 'Yellow' }
        }
    }
    if (Coche 11) {
        $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        foreach ($v in 'SubscribedContent-338389Enabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled',
                       'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'SilentInstalledAppsEnabled') { RegSet $cdm $v 0 }
        Log "Pubs et suggestions de Windows coupées (compte $env:USERNAME)." 'Green'
    }
    if (Coche 12) {
        if ($typeDisque -eq 'HDD') {
            Stop-Service WSearch -Force; Set-Service WSearch -StartupType Disabled
            Log 'Indexation de recherche coupée (disque dur).' 'Green'
        } else { Log "Indexation conservée : le disque n'est pas un HDD (type : $typeDisque)." }
    }
    if (Coche 13) {
        RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0)) -Type Binary
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2' -Type String
        RegSet 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
        $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        RegSet $adv 'TaskbarAnimations' 0; RegSet $adv 'ListviewAlphaSelect' 0; RegSet $adv 'ListviewShadow' 0
        RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        RegSet 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
        Log "Effets visuels réduits (compte $env:USERNAME, effet à la prochaine connexion)." 'Green'
    }
    if (Coche 14) {
        RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
        RegSet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        if ($estAdmin) {
            RegSet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
            Log 'Applications en arrière-plan coupées (tous les comptes).' 'Green'
        } else { Log "Applications en arrière-plan coupées (compte $env:USERNAME)." 'Green' }
    }
    if (Coche 15) {
        Log 'Suppression des applis préinstallées (quelques minutes)...'
        $applis = '*CandyCrush*', 'king.com.*', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.XboxApp',
                  'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay',
                  'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.BingNews', 'Microsoft.BingWeather',
                  'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.People', 'Microsoft.SkypeApp',
                  'Microsoft.WindowsFeedbackHub', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer',
                  'Microsoft.MicrosoftOfficeHub', 'Microsoft.Messaging', 'Microsoft.OneConnect', 'Microsoft.Print3D',
                  '*Spotify*', '*Disney*', '*TikTok*', '*Facebook*', '*Instagram*', '*Netflix*', '*Twitter*'
        $supprimees = New-Object 'System.Collections.Generic.HashSet[string]'
        $provision = Get-AppxProvisionedPackage -Online
        foreach ($a in $applis) {
            foreach ($pkg in (Get-AppxPackage -AllUsers -Name $a)) {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers
                [void]$supprimees.Add($pkg.Name)
            }
            # Empêche aussi la réinstallation pour les nouveaux comptes
            $provision | Where-Object DisplayName -like $a | ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName | Out-Null
                [void]$supprimees.Add($_.DisplayName)
            }
        }
        if ($supprimees.Count) { foreach ($s in $supprimees) { Log "   Supprimée : $s" 'Green' } } else { Log 'Aucune appli inutile trouvée.' }
    }
    if (Coche 16) {
        foreach ($svc in 'DiagTrack', 'dmwappushservice') { Stop-Service $svc -Force; Set-Service $svc -StartupType Disabled }
        RegSet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Log 'Télémétrie réduite au minimum.' 'Green'
    }

    if (Coche 18) {
        Etape 'ANALYSE ANTIVIRUS RAPIDE'
        $mp = Get-MpComputerStatus
        if (-not $mp.AntivirusEnabled) { Log 'Windows Defender n''est pas l''antivirus actif sur ce PC : analyse ignorée (utilisez l''antivirus installé).' 'Yellow' }
        else {
            Log 'Analyse en cours (5 à 15 min)...'
            $debut = Get-Date
            Start-MpScan -ScanType QuickScan
            $menaces = @(Get-MpThreatDetection | Where-Object { $_.InitialDetectionTime -ge $debut })
            if ($menaces.Count) {
                Log "$($menaces.Count) menace(s) détectée(s) et traitée(s) par Windows Defender." 'Red'
                $Conseils.Add("Des menaces ont été détectées : ouvrez Sécurité Windows > Protection contre les virus > Historique de protection, puis lancez une analyse complète.")
            } else { Log 'Aucune menace détectée.' 'Green' }
        }
    }

    if (Coche 20) {
        Etape 'RÉPARATION DES FICHIERS WINDOWS'
        Log 'DISM (nettoyage des composants)...'
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup
        Log "DISM terminé (code $LASTEXITCODE)."
        Log 'SFC (vérification des fichiers système)...'
        & sfc.exe /scannow
        Log "SFC terminé (code $LASTEXITCODE). Détails : C:\Windows\Logs\CBS\CBS.log"
    }

    if (Coche 21) {
        Etape 'OPTIMISATION DU DISQUE'
        if ($typeDisque -eq 'SSD') { Log 'SSD : optimisation TRIM (rapide).' } else { Log 'Défragmentation (peut être long sur un disque dur).' 'Yellow' }
        Optimize-Volume -DriveLetter C -Verbose
        Log 'Optimisation terminée.' 'Green'
    }

    Etape 'BILAN'
    $libreApres = EspaceLibre
    Log "Espace libre avant : $libreAvant Go  ->  après : $libreApres Go  (gain : $([math]::Round($libreApres - $libreAvant, 2)) Go)" 'Green'
}

# --- Conseils ----------------------------------------------------------------
Etape 'CONSEILS POUR CE PC'
if ($Conseils.Count -eq 0) { Log 'Rien d''anormal détecté.' 'Green' }
foreach ($c in $Conseils) { Log "* $c" 'Yellow'; Log '' }

$chrono.Stop()
Log ("Durée : {0:hh\:mm\:ss}" -f $chrono.Elapsed)
Log "Rapport enregistré : $Rapport"

Write-Host ''
if ($Sel.Count) {
    $r = Read-Host 'Redémarrer le PC maintenant pour finir (recommandé) ? (O/N)'
    if ("$r".Trim().ToUpper() -eq 'O') { Restart-Computer -Force }
} else {
    Read-Host 'Appuyez sur Entrée pour fermer' | Out-Null
}
