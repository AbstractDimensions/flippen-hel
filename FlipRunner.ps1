# FlipRunner --- Flip-lookalike one-click flash + serial for AT89C51RD2/LP51RD2
# "Want Atmel FLIP was 'n groot FLOP" - Afrikaans pun: wish Atmel FLIP was a
# big FLOP. Mascot is a flip-flop called Fillip.
# Run button = erase + blankcheck + program + verify + start (remembers last hex).
# No installs needed (PowerShell + .NET WinForms).
# NOTE: Flip 3.4.7 ships AT89C51RD2.xml but NO AT89LP51RD2.xml --- default is AT89C51RD2.

param(
    [string]$HexFile = "",
    [switch]$Cli,
    [string]$Action = "",
    [string]$Hex = "",
    [string]$Device = "",
    [string]$Port = "",
    [string]$IspBaud = "115200",
    [string]$MonBaud = "9600",
    [int]$Seconds = 10
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- portable defaults (friend/faculty friendly) ----------
# Dependency preference order:
#   1. a batchisp.exe bundled NEXT TO THIS SCRIPT (bin\ or same folder) - this
#      is what ships in the release zip, so the app needs no Flip install
#   2. an installed Atmel FLIP 3.4.7 (auto-detected)
# batchisp.exe is standalone: it needs no DLLs and no working directory, so a
# single copied binary is the entire dependency.
function Find-BatchIsp {
    $local = @(
        (Join-Path $PSScriptRoot 'bin\batchisp.exe'),
        (Join-Path $PSScriptRoot 'batchisp.exe')
    )
    foreach ($c in $local) { if (Test-Path $c) { return $c } }
    $cands = @(
        'C:\Program Files (x86)\Atmel\Flip 3.4.7\bin\batchisp.exe',
        'C:\Program Files\Atmel\Flip 3.4.7\bin\batchisp.exe'
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    $g = Get-Command batchisp.exe -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $cands[0]
}
# Device tokens come from a bundled part-file folder when present, otherwise
# from the Flip install.
function Find-PartFileDir {
    $local = @(
        (Join-Path $PSScriptRoot 'PartDescriptionFiles'),
        (Join-Path $PSScriptRoot 'bin\PartDescriptionFiles')
    )
    foreach ($c in $local) { if (Test-Path $c) { return $c } }
    $i = 'C:\Program Files (x86)\Atmel\Flip 3.4.7\bin\PartDescriptionFiles'
    if (Test-Path $i) { return $i }
    return $local[0]
}
function Find-CodeBlocksRoot {
    $cands = @(
        (Join-Path $env:USERPROFILE 'OneDrive\Documents\CodeBlocks'),
        (Join-Path $env:USERPROFILE 'Documents\CodeBlocks')
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    return $cands[0]
}

$BatchIsp = Find-BatchIsp
$ConfigFile = Join-Path $PSScriptRoot 'FlipRunner.json'
$DefaultDevice = 'AT89C51RD2'
$ResetMagic = '!!!RESET!!!'   # firmware watches for 3x '!' then reboots app

$FirmwareSnippet = @'
// --- FlipRunner firmware reset (AT89LP51RD2, SDCC, 8051) ---
// 1. Call UartResetPoll() inside your main while(1) loop.
// 2. In FlipRunner, open serial then press Reset (Ctrl+R).
//    The PC sends "!!!RESET!!!" and this reboots the APP.
//    (TX/RX alone CANNOT enter the bootloader --- that still needs the
//     hardware ISP condition or BLJB/AutoISP wiring. This is app-restart
//     for fast testing without reflashing.)
void UartResetPoll(void) {
    static unsigned char n = 0;
    if (RI) {
        RI = 0;
        if (SBUF == '!') {
            if (++n >= 3) {
                n = 0;
                EA = 0;              // stop interrupts
                __asm               // reboot app from address 0
                    ljmp 0
                __endasm;
                while (1);           // never reached
            }
        } else n = 0;
    }
}
'@

function Load-Config {
    $cfg = [ordered]@{
        HexFile = ''; Device = $DefaultDevice; Port = ''
        IspBaud = '115200'; MonBaud = '9600'; AutoIsp = $true
        RecentDevices = @(); RecentHex = @(); CollapsedSig = $true
        SerialAuto = $true; TargetMem = 'FLASH'
    }
    if (Test-Path $ConfigFile) {
        try { foreach ($kv in (Get-Content $ConfigFile -Raw | ConvertFrom-Json).PSObject.Properties) { $cfg[$kv.Name] = $kv.Value } } catch {}
    }
    if ($cfg.CollapsedSig -eq $null) { $cfg.CollapsedSig = $true }
    if ($cfg.SerialAuto -eq $null) { $cfg.SerialAuto = $true }
    return $cfg
}
function Save-Config($cfg) { ($cfg | ConvertTo-Json) | Set-Content $ConfigFile -Encoding UTF8 }
function Find-NewestHex($root) {
    if (-not (Test-Path $root)) { return $null }
    Get-ChildItem $root -Recurse -Include *.hex -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

# Bluetooth-ignoring COM scan. Friendly-name check via WMI; fallback to raw list.
function Get-ComPortsFiltered {
    try { $all = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object }
    catch { return @() }
    try {
        $map = @{}
        foreach ($s in (Get-CimInstance Win32_SerialPort -ErrorAction Stop)) {
            $map[$s.DeviceID] = ($s.Description + ' ' + $s.PNPDeviceID + ' ' + $s.Name)
        }
        $out = @()
        foreach ($p in $all) {
            $info = [string]$map[$p]
            if ($info -match 'Bluetooth|BTH|RFCOMM|btport|BlueSoleil|BTENUM') { continue }
            $out += $p
        }
        if ($out.Count -gt 0) { return $out }
        return $all  # WMI gave nothing useful --- show raw list rather than empty
    } catch { return $all }
}

# Device tokens harvested from Flip part files (NAME attribute, filename fallback).
function Get-DeviceTokens {
    $partDir = Find-PartFileDir
    $tokens = @()
    if (-not (Test-Path $partDir)) { return @() }
    $files = Get-ChildItem $partDir -Filter *.xml -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $name = $null
        try {
            $head = Get-Content $f.FullName -TotalCount 20 -ErrorAction Stop | Out-String
            $m = [regex]::Match($head, 'NAME\s*=\s*"([^"]+)"')
            if ($m.Success) { $name = $m.Groups[1].Value.Trim() }
        } catch {}
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [IO.Path]::GetFileNameWithoutExtension($f.Name) }
        if ($name -ne '') { $tokens += $name }
    }
    return (@($tokens | Sort-Object -Unique))
}

# Educated device guess: code contents (weight 2) + doc filenames (weight 1).
# Bounded: capped file counts, small text files only, filenames-only outside
# code dirs, hidden/system paths skipped. Returns top token or $null.
function Invoke-DeviceGuess {
    $tokens = @(Get-DeviceTokens)
    if ($tokens.Count -eq 0) { return $null }
    $canon = @{}
    foreach ($t in $tokens) { $canon[$t.ToUpperInvariant()] = $t }
    $pat = (($tokens | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|')
    $opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $scores = @{}
    try {
        $codeFiles = Get-ChildItem $CodeBlocksRoot -Recurse -Include *.c,*.h,*.cbp -File -ErrorAction SilentlyContinue | Select-Object -First 300
        foreach ($f in $codeFiles) {
            try {
                if ($f.Length -gt 102400) { continue }
                $text = [IO.File]::ReadAllText($f.FullName)
                foreach ($m in ([regex]::Matches($text, $pat, $opt))) {
                    $k = $m.Value.ToUpperInvariant()
                    $scores[$k] = ([int]$scores[$k]) + 2
                }
            } catch {}
        }
    } catch {}
    $docRoots = @()
    foreach ($d in @((Join-Path $env:USERPROFILE 'OneDrive\Documents'), (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Downloads'))) {
        if (Test-Path $d) { $docRoots += $d }
    }
    try {
        $seen = 0
        foreach ($root in $docRoots) {
            $files = Get-ChildItem $root -Recurse -File -Depth 2 -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                if ($seen -ge 5000) { break }
                $seen++
                try {
                    if (($f.Attributes -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) -ne 0) { continue }
                } catch {}
                if ($f.FullName -match '[\\/]\.') { continue }
                $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                foreach ($m in ([regex]::Matches($base, $pat, $opt))) {
                    $k = $m.Value.ToUpperInvariant()
                    $scores[$k] = ([int]$scores[$k]) + 1
                }
            }
            if ($seen -ge 5000) { break }
        }
    } catch {}
    if ($scores.Count -eq 0) { return $null }
    $ranked = @($scores.GetEnumerator() | Sort-Object Value -Descending)
    if ($ranked.Count -gt 1 -and $ranked[0].Value -eq $ranked[1].Value) { return $null }
    return $canon[$ranked[0].Key]
}

# MRU: most-recent-first, deduped, capped at 8, persisted in FlipRunner.json.
function Add-RecentHex($path) {
    $path = ("$path").Trim()
    if ($path -eq '') { return }
    $list = @()
    if ($cfg.RecentHex) { $list = @($cfg.RecentHex) }
    $up = $path.ToUpperInvariant()
    $list = @($list | Where-Object { ("$_").ToUpperInvariant() -ne $up })
    $cfg.RecentHex = @(@($path) + @($list) | Select-Object -First 8)
    $cfg.HexFile = $path
    Save-Config $cfg
    Update-HexComboItems
}
function Update-HexComboItems {
    if ((Get-Variable -Name cmbHex -Scope Script -ErrorAction SilentlyContinue) -eq $null) { return }
    if ((Get-Variable -Name cmbHex -ValueOnly -ErrorAction SilentlyContinue) -eq $null) { return }
    $cur = $cmbHex.Text
    $cmbHex.Items.Clear()
    $seen = @{}
    $ordered = @()
    if ($cur -ne '') { $ordered += $cur }
    if ($cfg.RecentHex) { foreach ($h in @($cfg.RecentHex)) { $ordered += $h } }
    foreach ($h in $ordered) {
        $k = ("$h").ToUpperInvariant()
        if ($seen[$k]) { continue }
        $seen[$k] = $true
        [void]$cmbHex.Items.Add($h)
    }
    $cmbHex.Text = $cur
}
function Get-HexAgeText($when) {
    try { $s = [int](([datetime]::Now - $when).TotalSeconds) } catch { return 'age unknown' }
    if ($s -lt 0) { $s = 0 }
    if ($s -lt 10) { return 'built just now' }
    if ($s -lt 60) { return ('built ' + $s + ' sec ago') }
    $m = [int]($s / 60)
    if ($m -lt 60) { return ('built ' + $m + ' min ago') }
    $h = [int]($m / 60)
    if ($h -lt 48) { return ('built ' + $h + ' hr ago') }
    $d = [int]($h / 24)
    return ('built ' + $d + ' days ago')
}
function Sync-HexFromCombo {
    $p = ("$($cmbHex.Text)").Trim('" ').Trim()
    if ($p -eq '') { Update-HexInfo; return }
    if (Test-Path $p) {
        try { $full = ([IO.Path]::GetFullPath($p)) } catch { $full = $p }
        $tip.SetToolTip($cmbHex, $full)
        $cfg.HexFile = $p
        Save-Config $cfg
    } else {
        $tip.SetToolTip($cmbHex, ('Not found: ' + $p))
    }
    Update-HexInfo
    if ($p -ne '' -and (Test-Path $p)) { Update-StateNext 'Press Run (F5)' } else { Update-StateNext 'Pick a valid hex (Ctrl+O)' }
}
# MRU: most-recent-first, deduped, capped at 5, persisted in FlipRunner.json.
function Add-RecentDevice($dev) {
    $dev = ("$dev").Trim()
    if ($dev -eq '') { return }
    $list = @()
    if ($cfg.RecentDevices) { $list = @($cfg.RecentDevices) }
    $up = $dev.ToUpperInvariant()
    $list = @($list | Where-Object { ("$_").ToUpperInvariant() -ne $up })
    $cfg.RecentDevices = @(@($dev) + @($list) | Select-Object -First 5)
    Save-Config $cfg
}

function Update-DeviceMenu {
    $deviceMenu.DropDownItems.Clear()
    $recent = @()
    if ($cfg.RecentDevices) { $recent = @($cfg.RecentDevices) }
    if ($recent.Count -gt 0) {
        foreach ($d in $recent) {
            $devName = "$d"
            $item = New-Object Windows.Forms.ToolStripMenuItem; $item.Text = $devName
            $item.ToolTipText = ("Use " + $devName + " as device")
            $item.Add_Click(({ $txtDev.Text = $devName; $tip.SetToolTip($txtDev, ('device: ' + $devName + ' (batchisp -device name)')); Update-StateNext 'Press Run (F5)'; Log ('device: ' + $devName) }.GetNewClosure()))
            [void]$deviceMenu.DropDownItems.Add($item)
        }
        $sep = New-Object Windows.Forms.ToolStripSeparator; [void]$deviceMenu.DropDownItems.Add($sep)
    }
    $all = New-Object Windows.Forms.ToolStripMenuItem; $all.Text = 'Select Device...'; $all.ToolTipText = 'Pick from all Flip-supported devices'; $all.Add_Click({ Show-DevicePicker }); [void]$deviceMenu.DropDownItems.Add($all)
    if ($recent.Count -eq 0) {
        $e = New-Object Windows.Forms.ToolStripMenuItem; $e.Text = '(no recent devices)'; $e.Enabled = $false
        [void]$deviceMenu.DropDownItems.Add($e)
    }
}

$cfg = Load-Config
$CodeBlocksRoot = Find-CodeBlocksRoot
if ($HexFile -ne '') { $cfg.HexFile = $HexFile }
$hexFallbackNotice = $null
if (($cfg.HexFile -eq '' -or -not (Test-Path $cfg.HexFile))) {
    $auto = Find-NewestHex $CodeBlocksRoot
    if ($auto) { $cfg.HexFile = $auto; $hexFallbackNotice = ('remembered hex not found, using ' + $auto) }
}
$storedDevice = $false
if (Test-Path $ConfigFile) {
    try {
        $rawCfg = Get-Content $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($rawCfg.Device -ne $null -and ("$($rawCfg.Device)").Trim() -ne '') { $storedDevice = $true }
    } catch {}
}
# Auto-detect device: guess the 8051 from your own code + docs. Switch it off
# and this never runs - you pick the device like in FLIP.
if (-not $storedDevice) {
    $doGuess = $true
    try { $doGuess = Get-AutoFlow 'Auto-detect device' } catch {}
    if ($doGuess) {
        $guessed = Invoke-DeviceGuess
        if ($guessed -ne $null -and $guessed -ne '') { $cfg.Device = $guessed }
    }
}

# ---------- headless CLI for AI/automation (zero windows; before any form) ----------
# Usage: FlipRunner.ps1 -Cli -Action Flash|Reset|Monitor [-Hex ...] [-Device ...]
#   [-Port ...] [-IspBaud ...] [-MonBaud ...] [-Seconds N]
# Omitted Hex/Device/Port/IspBaud/MonBaud fall back to FlipRunner.json, then to
# the hardcoded defaults. Prints FLIPHEL OK|FAIL lines; exit code 0/1.
if ($Cli) {
    $cliAction = ("$Action").Trim()
    if ($Hex -ne '') { $cliHex = $Hex } else { $cliHex = $cfg.HexFile }
    if ($Device -ne '') { $cliDev = $Device } elseif ("$($cfg.Device)" -ne '') { $cliDev = ("$($cfg.Device)").Trim() } else { $cliDev = $DefaultDevice }
    if ($Port -ne '') { $cliPort = $Port } else { $cliPort = ("$($cfg.Port)").Trim() }
    if ($PSBoundParameters.ContainsKey('IspBaud')) { $cliIsp = ("$IspBaud").Trim() } elseif ("$($cfg.IspBaud)" -ne '') { $cliIsp = ("$($cfg.IspBaud)").Trim() } else { $cliIsp = '115200' }
    if ($PSBoundParameters.ContainsKey('MonBaud')) { $cliMon = ("$MonBaud").Trim() } elseif ("$($cfg.MonBaud)" -ne '') { $cliMon = ("$($cfg.MonBaud)").Trim() } else { $cliMon = '9600' }
    if ($PSBoundParameters.ContainsKey('Seconds')) { $cliSecs = [int]$Seconds } else { $cliSecs = 10 }
    if ($cliAction -eq '' -or ($cliAction -ne 'Flash' -and $cliAction -ne 'Reset' -and $cliAction -ne 'Monitor')) {
        Write-Output 'FLIPHEL FAIL unknown action (use Flash|Reset|Monitor)'
        exit 1
    }
    if ($cliAction -eq 'Flash') {
        # Same construction as the GUI Run: full erase+blankcheck+program+
        # verify+start flow, two-arg -autoisp 1 0 when enabled, omitted when off.
        if ($cliHex -eq '' -or -not (Test-Path $cliHex)) { Write-Output ('FLIPHEL FAIL no hex file: ' + $cliHex); exit 1 }
        if (-not (Test-Path $BatchIsp)) { Write-Output ('FLIPHEL FAIL batchisp not found: ' + $BatchIsp); exit 1 }
        if ($cliPort -eq '') { Write-Output 'FLIPHEL FAIL no port given and none stored in config'; exit 1 }
        $cliAuto = ''; if ([bool]$cfg.AutoIsp) { $cliAuto = '-autoisp 1 0' }
        $cliOp = ('MEMORY FLASH ERASE F BLANKCHECK LOADBUFFER "{0}" PROGRAM VERIFY START RESET 0' -f $cliHex)

        # Build port retry list for CLI: start with selected, then all non-BT ports
        $allPorts = @()
        try { $allPorts = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object } catch {}
        try {
            $btFilter = 'Bluetooth|BTH|RFCOMM|btport|BlueSoleil|BTENUM'
            $map = @{}
            foreach ($s in (Get-CimInstance Win32_SerialPort -ErrorAction Stop)) {
                $map[$s.DeviceID] = ($s.Description + ' ' + $s.PNPDeviceID + ' ' + $s.Name)
            }
            $filtered = @()
            foreach ($p in $allPorts) {
                $info = [string]$map[$p]
                if ($info -notmatch $btFilter) { $filtered += $p }
            }
            if ($filtered.Count -gt 0) { $allPorts = $filtered }
        } catch {}
        $retryPorts = @()
        if ($cliPort -ne '' -and ($allPorts -contains $cliPort)) { $retryPorts += $cliPort }
        foreach ($p in $allPorts) { if ($p -ne $cliPort) { $retryPorts += $p } }

        $cliFlashOk = $false
        foreach ($tryPort in $retryPorts) {
            $cliArgs = "-device $cliDev -hardware RS232 -port $tryPort -baudrate $cliIsp $cliAuto -operation $cliOp"
            Write-Output ("FLIPHEL TRY ${tryPort}: batchisp.exe $cliArgs")
            try {
                $cliP = Start-Process -FilePath $BatchIsp -ArgumentList $cliArgs -NoNewWindow -Wait -PassThru
            } catch { Write-Output ('FLIPHEL FAIL batchisp launch failed on ' + $tryPort + ': ' + $_.Exception.Message); continue }
            if ($cliP.ExitCode -eq 0) {
                $cliFlashOk = $true
                $cliPort = $tryPort
                Write-Output ('FLIPHEL OK flashed ' + $cliHex + ' on ' + $cliPort + ' as ' + $cliDev)
                exit 0
            } else {
                Write-Output ('FLIPHEL FAIL batchisp exit ' + $cliP.ExitCode + ' on ' + $tryPort + ' -- trying next port')
            }
        }
        Write-Output ('FLIPHEL FAIL all ports exhausted (device ' + $cliDev + ' isp ' + $cliIsp + ')')
        exit 1
    }
    if ($cliAction -eq 'Reset') {
        if ($cliPort -eq '') { Write-Output 'FLIPHEL FAIL no port given and none stored in config'; exit 1 }
        try {
            $cliP = New-Object System.IO.Ports.SerialPort($cliPort, [int]$cliMon, 'None', 8, 'One')
            $cliP.Open()
            $cliP.Write($ResetMagic + "`r`n")
            $cliP.Close()
            Write-Output ('FLIPHEL OK reset sent on ' + $cliPort)
            exit 0
        } catch { Write-Output ('FLIPHEL FAIL reset failed on ' + $cliPort + ': ' + $_.Exception.Message); exit 1 }
    }
    # Monitor: stream RX bytes to stdout for N seconds, then report.
    if ($cliPort -eq '') { Write-Output 'FLIPHEL FAIL no port given and none stored in config'; exit 1 }
    try {
        $cliP = New-Object System.IO.Ports.SerialPort($cliPort, [int]$cliMon, 'None', 8, 'One')
        $cliP.Open()
    } catch { Write-Output ('FLIPHEL FAIL monitor open failed on ' + $cliPort + ': ' + $_.Exception.Message); exit 1 }
    try {
        $cliEnd = [datetime]::Now.AddSeconds($cliSecs)
        while ([datetime]::Now -lt $cliEnd) {
            try {
                if ($cliP.BytesToRead -gt 0) { [Console]::Out.Write($cliP.ReadExisting()) }
                else { Start-Sleep -Milliseconds 100 }
            } catch { break }
        }
        try { $cliP.Close() } catch {}
        Write-Output ''
        Write-Output ('FLIPHEL OK monitor done on ' + $cliPort + ' (' + $cliSecs + 's)')
        exit 0
    } catch { try { $cliP.Close() } catch {}; Write-Output ('FLIPHEL FAIL monitor failed on ' + $cliPort + ': ' + $_.Exception.Message); exit 1 }
}

# ---------- form (Flip lookalike) ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'FLIPpen Hel'
$form.Size = New-Object Drawing.Size(900, 560)
$form.StartPosition = 'CenterScreen'
$form.KeyPreview = $true
$form.BackColor = [Drawing.SystemColors]::Control

$tip = New-Object Windows.Forms.ToolTip
$tip.AutoPopDelay = 8000; $tip.InitialDelay = 400; $tip.ReshowDelay = 100
$tip.ShowAlways = $true

# menu
$menu = New-Object Windows.Forms.MenuStrip
foreach ($m in @('File', 'Buffer', 'Device', 'Settings', 'Help')) {
    $mi = New-Object Windows.Forms.ToolStripMenuItem; $mi.Text = $m; [void]$menu.Items.Add($mi)
    $mi.ToolTipText = @{File='File operations (Load HEX, Refresh ports)'; Buffer='Buffer info (size, variant)'; Device='Recent device quick-pick'; Settings='Connection settings dialog'; Help='Help topics, copy firmware snippet'}[$m]
    if ($m -eq 'Settings') { $settingsMenu = $mi }
    if ($m -eq 'File') {
        $o = New-Object Windows.Forms.ToolStripMenuItem; $o.Text = 'Load HEX...'; $o.ShortcutKeys = 'Control, O'; $o.ToolTipText = 'Load HEX - pick a .hex file to flash (Ctrl+O). Flip keeps the last 6 loaded'; $o.Add_Click({ Invoke-BrowseHex }); [void]$mi.DropDownItems.Add($o)
        $n = New-Object Windows.Forms.ToolStripMenuItem; $n.Text = 'Use newest hex in CodeBlocks'; $n.ToolTipText = 'Newest Hex - auto-pick the newest CodeBlocks bin\*.hex'; $n.Add_Click({ Invoke-NewestHex }); [void]$mi.DropDownItems.Add($n)
        $sv = New-Object Windows.Forms.ToolStripMenuItem; $sv.Text = 'Save Buffer Contents...'; $sv.ShortcutKeys = 'Control, S'; $sv.ToolTipText = 'Save Buffer - write the current hex to a new .hex file (Intel HEX)'
        $sv.Add_Click({ Save-BufferContents }); [void]$mi.DropDownItems.Add($sv)
        $r = New-Object Windows.Forms.ToolStripMenuItem; $r.Text = 'Refresh port list'; $r.ToolTipText = 'Refresh ports - rescan COM ports (Bluetooth ignored)'; $r.Add_Click({ Refresh-Ports }); [void]$mi.DropDownItems.Add($r)
    }
    if ($m -eq 'Buffer') {
        $script:bufSizeItem = New-Object Windows.Forms.ToolStripMenuItem; $script:bufSizeItem.Text = 'Hex size: (no hex)'; $script:bufSizeItem.Enabled = $false; $script:bufSizeItem.ToolTipText = 'Shows hex file size and address range (auto from parsed hex)'; [void]$mi.DropDownItems.Add($script:bufSizeItem)
        $script:bufVariantItem = New-Object Windows.Forms.ToolStripMenuItem; $script:bufVariantItem.Text = 'Variant: (no hex)'; $script:bufVariantItem.Enabled = $false; $script:bufVariantItem.ToolTipText = 'Shows Debug/Release variant from path'; [void]$mi.DropDownItems.Add($script:bufVariantItem)
    }
    if ($m -eq 'Help') {
        $a = New-Object Windows.Forms.ToolStripMenuItem; $a.Text = 'Copy firmware reset snippet'; $a.ToolTipText = 'Copy C snippet for UART reset reboot to clipboard'; $a.Add_Click({ Copy-FirmwareSnippet }); [void]$mi.DropDownItems.Add($a)
        $w = New-Object Windows.Forms.ToolStripMenuItem; $w.Text = 'Help topics...'; $w.ToolTipText = 'Open firmware reset explanation window'; $w.Add_Click({ Show-Help }); [void]$mi.DropDownItems.Add($w)
    }
    if ($m -eq 'Device') {
        $deviceMenu = $mi
        $deviceMenu.Add_DropDownOpening({ Update-DeviceMenu })
        $sep = New-Object Windows.Forms.ToolStripSeparator; [void]$mi.DropDownItems.Add($sep)
        # Device > Erase (full chip erase; block erase uses the range dialog)
        $e1 = New-Object Windows.Forms.ToolStripMenuItem; $e1.Text = 'Erase'; $e1.ToolTipText = 'Erase - full chip erase. Resets SSB, Hardware Byte, BSB and SBV to defaults'
        $e1.Add_Click({ Device-Erase 'F' }); [void]$mi.DropDownItems.Add($e1)
        $e2 = New-Object Windows.Forms.ToolStripMenuItem; $e2.Text = 'Erase Blocks...'; $e2.ToolTipText = 'Erase Blocks - erase only the address range you type'
        $e2.Add_Click({ Show-Prompt 'Erase Blocks' 'Start address (hex, no 0x)' '' 'End address (hex, no 0x)' '' {
            param($s, $e)
            $op = ('ERASE F START ' + $s + ' END ' + $e)
            $ok = (Invoke-OpOnPorts $op 'Erase blocks') -ne ''
            Set-OpResult 'Erase' $ok
            Update-StateNext (if ($ok) { 'Block erase done' } else { 'Block erase failed' })
        } }); [void]$mi.DropDownItems.Add($e2)
        # Device > Blank Check
        $b1 = New-Object Windows.Forms.ToolStripMenuItem; $b1.Text = 'Blank Check...'; $b1.ShortcutKeys = 'Control, B'; $b1.ToolTipText = 'Blank Check - check the address range is blank; reports first non-blank address'
        $b1.Add_Click({ Device-BlankCheck }); [void]$mi.DropDownItems.Add($b1)
        # Device > Read
        $r1 = New-Object Windows.Forms.ToolStripMenuItem; $r1.Text = 'Read...'; $r1.ToolTipText = 'Read - read target memory into the buffer, then show buffer info'
        $r1.Add_Click({ Device-Read }); [void]$mi.DropDownItems.Add($r1)
        # Device > Verify
        $v1 = New-Object Windows.Forms.ToolStripMenuItem; $v1.Text = 'Verify'; $v1.ToolTipText = 'Verify - read back memory and compare with the loaded hex; reports first failing address'
        $v1.Add_Click({ Device-Verify }); [void]$mi.DropDownItems.Add($v1)
        # Device > Communications check
        $c1 = New-Object Windows.Forms.ToolStripMenuItem; $c1.Text = 'Check Communications'; $c1.ToolTipText = 'Check Communications - verify batchisp can talk to the device on the selected port'
        $c1.Add_Click({ Device-CommCheck }); [void]$mi.DropDownItems.Add($c1)
        # Device > Write/Read special bits
        $s1 = New-Object Windows.Forms.ToolStripMenuItem; $s1.Text = 'Write/Read Special Bits...'; $s1.ToolTipText = 'Special Bits - write or read BLJB, X2, BSB/SBV and Security Level'
        $s1.Add_Click({ Show-SpecialBits }); [void]$mi.DropDownItems.Add($s1)
    }
}
# NOTE: the menu is added to $form.Controls AFTER the toolbar below. For
# same-edge docking the control added last docks closest to the top edge, so
# that order puts the menu row at the very top with the icon row beneath it.

# toolbar: icon row directly beneath the menu row (Flip-style groups).
function New-GreyIcon($name) {
    $sz = 32
    $bmp = New-Object Drawing.Bitmap($sz, $sz)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::Transparent)
    $grey = [Drawing.Color]::FromArgb(88, 88, 88)
    $pen = New-Object Drawing.Pen($grey, 2)
    $pen2 = New-Object Drawing.Pen($grey, 3)
    $brush = New-Object Drawing.SolidBrush($grey)
    if ($name -eq 'chip') {
        $g.DrawRectangle($pen2, 8, 8, 16, 16)
        $g.DrawLine($pen, 12, 3, 12, 8); $g.DrawLine($pen, 20, 3, 20, 8)
        $g.DrawLine($pen, 12, 24, 12, 29); $g.DrawLine($pen, 20, 24, 20, 29)
        $g.DrawLine($pen, 3, 12, 8, 12); $g.DrawLine($pen, 3, 20, 8, 20)
        $g.DrawLine($pen, 24, 12, 29, 12); $g.DrawLine($pen, 24, 20, 29, 20)
    } elseif ($name -eq 'device') {
        # chip + magnifier (Flip's "select device")
        $g.DrawRectangle($pen2, 4, 4, 14, 14)
        $g.DrawLine($pen, 7, 1, 7, 4); $g.DrawLine($pen, 15, 1, 15, 4)
        $g.DrawLine($pen, 7, 18, 7, 21); $g.DrawLine($pen, 15, 18, 15, 21)
        $g.DrawLine($pen, 1, 7, 4, 7); $g.DrawLine($pen, 1, 15, 4, 15)
        $g.DrawLine($pen, 18, 7, 21, 7); $g.DrawLine($pen, 18, 15, 21, 15)
        $g.DrawEllipse($pen, 19, 19, 10, 10)
        $g.DrawLine($pen2, 26, 26, 31, 31)
    } elseif ($name -eq 'serial') {
        # RS232 cable + plug (communication medium)
        $g.DrawRectangle($pen2, 3, 12, 14, 10)
        $g.DrawLine($pen, 6, 12, 6, 2); $g.DrawLine($pen, 10, 12, 10, 2); $g.DrawLine($pen, 14, 12, 14, 2)
        $g.DrawLine($pen, 5, 12, 5, 15); $g.DrawLine($pen, 15, 12, 15, 15)
        $g.DrawLine($pen, 14, 12, 18, 12)
        $g.FillRectangle($brush, 20, 8, 8, 8)
        $g.DrawLine($pen, 22, 16, 22, 24); $g.DrawLine($pen, 26, 16, 26, 24)
    } elseif ($name -eq 'folder') {
        $g.DrawRectangle($pen2, 4, 10, 24, 16)
        $pts = @((New-Object Drawing.Point(4, 10)), (New-Object Drawing.Point(4, 6)), (New-Object Drawing.Point(12, 6)), (New-Object Drawing.Point(15, 10)))
        $g.DrawLines($pen2, $pts)
    } elseif ($name -eq 'play') {
        $pts = @((New-Object Drawing.Point(10, 5)), (New-Object Drawing.Point(10, 27)), (New-Object Drawing.Point(28, 16)))
        $g.FillPolygon($brush, $pts)
    } elseif ($name -eq 'start') {
        $pts = @((New-Object Drawing.Point(5, 4)), (New-Object Drawing.Point(5, 28)), (New-Object Drawing.Point(20, 16)))
        $g.FillPolygon($brush, $pts)
        $g.FillRectangle($brush, 21, 4, 5, 24)
    } elseif ($name -eq 'reset-arrow') {
        $g.DrawArc($pen2, 5, 5, 22, 22, 45, 290)
        $pts = @((New-Object Drawing.Point(25, 2)), (New-Object Drawing.Point(30, 12)), (New-Object Drawing.Point(20, 11)))
        $g.FillPolygon($brush, $pts)
    } elseif ($name -eq 'terminal') {
        $g.DrawRectangle($pen2, 2, 6, 28, 22)
        $g.FillRectangle($brush, 6, 10, 11, 4)
        $g.DrawLine($pen, 6, 20, 18, 20)
    }
    $pen.Dispose(); $pen2.Dispose(); $brush.Dispose(); $g.Dispose()
    return $bmp
}
$bar = New-Object Windows.Forms.ToolStrip
$bar.Dock = 'Top'
$bar.ImageScalingSize = New-Object Drawing.Size(32, 32)
$bar.AutoSize = $false
$bar.Height = 62
$bar.GripStyle = 'Hidden'
$bar.Padding = New-Object Windows.Forms.Padding(6, 2, 6, 2)
function Add-Tb($text, $tt, $action) {
    $b = New-Object Windows.Forms.ToolStripButton
    $b.Text = $text; $b.ToolTipText = $tt
    $b.DisplayStyle = 'ImageAndText'; $b.TextImageRelation = 'ImageAboveText'
    $b.AutoSize = $false; $b.Width = 78; $b.Height = 58
    $b.Padding = New-Object Windows.Forms.Padding(2)
    $b.Add_Click($action); [void]$bar.Items.Add($b); return $b
}
function Add-Sep {
    $s = New-Object Windows.Forms.ToolStripSeparator; [void]$bar.Items.Add($s)
}
$form.Controls.Add($bar)
# Menu row goes on LAST so it docks to the top edge above the icon row.
[void]$form.Controls.Add($menu)
$form.MainMenuStrip = $menu
# Flip-style grouping: [device + communication] | [file] | [flash] | [run/start] | [serial tools]
$tbDevice  = Add-Tb 'Device' 'Device - pick target device (MRU + full list from Flip part files)' { Show-DevicePicker }
Add-Sep
$tbConnect = Add-Tb 'Serial: Auto' 'Serial: Auto - click connects (if needed) + opens terminal (Ctrl+T). RX data auto-opens the terminal' { Invoke-SerialButton }
Add-Sep
$tbLoad    = Add-Tb 'Load HEX' 'Load HEX - pick a hex file to flash (Ctrl+O)' { Invoke-BrowseHex }
Add-Sep
$tbRun     = Add-Tb 'Run' 'Run - full flow: erase + blankcheck + program + verify + start (F5). Opens progress popup' { $btnRun.PerformClick() }
$tbStart   = Add-Tb 'Start App' 'Start Application - START RESET 0 only, no flash (F6)' { $btnStartApp.PerformClick() }
Add-Sep
$tbReset   = Add-Tb 'Firmware Reset' 'Firmware Reset - send !!!RESET!!! over serial to reboot the app (Ctrl+R). Needs the snippet in firmware' { $btnFwReset.PerformClick() }
$tbTerminal = Add-Tb 'Terminal' 'Terminal - show/hide the serial monitor window' { Toggle-Terminal }
$tbDevice.Image = New-GreyIcon 'device'
$tbConnect.Image = New-GreyIcon 'serial'
$tbLoad.Image = New-GreyIcon 'folder'
$tbRun.Image = New-GreyIcon 'play'
$tbStart.Image = New-GreyIcon 'start'
$tbReset.Image = New-GreyIcon 'reset-arrow'
$tbTerminal.Image = New-GreyIcon 'terminal'

# panels start clear of menu (~24) + toolbar (62)
$top = 92
$PW_LEFT = 240; $PW_MID = 300; $PW_RIGHT = 324
# left: Operations Flow. Two sections so a FLIP refugee can see instantly what
# is a real FLIP operation and what FLIPpen Hel automates - plus a switch that
# turns the automation off for plain FLIP behaviour.
$gOp = New-Object Windows.Forms.GroupBox; $gOp.Text = 'Operations Flow'
$gOp.Location = New-Object Drawing.Point(8, $top); $gOp.Size = New-Object Drawing.Size($PW_LEFT, 380)
$form.Controls.Add($gOp)
$tip.SetToolTip($gOp, 'Operations Flow - pick the ISP steps to run, then press Run. Checkboxes turn green on pass, red on fail. The bottom group is automation; switch it off for plain FLIP behaviour')
$lblSec1 = New-Object Windows.Forms.Label; $lblSec1.Text = 'ISP operations'
$lblSec1.Font = New-Object Drawing.Font($form.Font, [Drawing.FontStyle]::Bold)
$lblSec1.Location = New-Object Drawing.Point(10, 18); $lblSec1.Size = New-Object Drawing.Size(220, 16)
$gOp.Controls.Add($lblSec1)
$tip.SetToolTip($lblSec1, 'The operation checkboxes real FLIP gives you in this same panel')
$ops = @(
    @{ n = 'Erase'; on = $true; tt = 'Erase - full chip erase before programming. Resets special bytes (SSB, HW Byte, BSB, SBV) to defaults' },
    @{ n = 'Blank Check'; on = $true; tt = 'Blank Check - verify flash is blank after erasing. Reports first non-blank address' },
    @{ n = 'Program'; on = $true; tt = 'Program - write the loaded hex buffer into target flash' },
    @{ n = 'Verify'; on = $true; tt = 'Verify - read back flash and compare with the buffer. Reports first failing address' },
    @{ n = 'Start Application'; on = $true; tt = 'Start Application - launch the firmware (START RESET 0) once the checked stages pass. Turn it off to leave the chip halted after flashing, exactly like FLIP' }
)
$chkOps = @{}
$oy = 40
foreach ($o in $ops) {
    $c = New-Object Windows.Forms.CheckBox; $c.Text = $o.n; $c.Checked = $o.on
    $c.Location = New-Object Drawing.Point(10, $oy); $c.Size = New-Object Drawing.Size(220, 20); $gOp.Controls.Add($c)
    $tip.SetToolTip($c, $o.tt + '   [green = last pass, red = last fail]')
    $chkOps[$o.n] = $c; $oy += 21
}
$sepY = ($oy + 3)
$lblSep = New-Object Windows.Forms.Label; $lblSep.Text = ''
$lblSep.Location = New-Object Drawing.Point(10, $sepY); $lblSep.Size = New-Object Drawing.Size(220, 2)
$lblSep.BorderStyle = 'Fixed3D'
$gOp.Controls.Add($lblSep)
$lblSec2 = New-Object Windows.Forms.Label; $lblSec2.Text = 'FLIPpen Hel automation'
$lblSec2.Font = New-Object Drawing.Font($form.Font, [Drawing.FontStyle]::Bold)
$lblSec2.Location = New-Object Drawing.Point(10, ($sepY + 5)); $lblSec2.Size = New-Object Drawing.Size(220, 16)
$gOp.Controls.Add($lblSec2)
$tip.SetToolTip($lblSec2, 'Things real FLIP makes you do by hand. Each one is yours to switch off')
$autoItems = @(
    @{ n = 'Auto-detect device'; on = $true; tt = 'Auto-detect device - guesses your 8051 from your own code and docs instead of making you pick from a list. Off = pick the device yourself, like FLIP' },
    @{ n = 'Auto-pick COM port'; on = $true; tt = 'Auto-pick COM port - scans ports, hides the Bluetooth ones, chooses the best candidate. Off = you always pick the port, like FLIP' },
    @{ n = 'Auto-retry other ports'; on = $true; tt = 'Auto-retry other ports - if a flash fails on the chosen port it tries every other non-Bluetooth port before giving up. Off = fail on the first attempt, like FLIP' },
    @{ n = 'Auto-reload newest hex'; on = $true; tt = 'Auto-reload newest hex - when a newer CodeBlocks build appears it switches to it automatically. Off = only shows the blue notice and waits for you, like FLIP' },
    @{ n = 'Auto-open terminal'; on = $true; tt = 'Auto-open terminal - the serial monitor pops open the moment your firmware prints anything. Off = it stays closed until you press Terminal, like FLIP' }
)
$chkAutoFlow = @{}
$oy = ($sepY + 25)
foreach ($o in $autoItems) {
    $c = New-Object Windows.Forms.CheckBox; $c.Text = $o.n; $c.Checked = $o.on
    $c.Location = New-Object Drawing.Point(10, $oy); $c.Size = New-Object Drawing.Size(220, 20); $gOp.Controls.Add($c)
    $tip.SetToolTip($c, $o.tt)
    $chkAutoFlow[$o.n] = $c; $oy += 21
}
function Get-AutoFlow($name) {
    try { return [bool]$chkAutoFlow[$name].Checked } catch { return $true }
}
function Set-OpResult($name, $ok) {
    try {
        if ($ok) { $chkOps[$name].ForeColor = [Drawing.Color]::FromArgb(0, 140, 0) }
        else { $chkOps[$name].ForeColor = [Drawing.Color]::FromArgb(190, 0, 0) }
    } catch {}
}
function Clear-OpsResult {
    foreach ($k in @($chkOps.Keys)) { $chkOps[$k].ForeColor = [System.Drawing.SystemColors]::ControlText }
}
# Buttons sit below both sections, pinned to the bottom of the panel.
$btnY = 300
$btnRun = New-Object Windows.Forms.Button; $btnRun.Text = 'Run'
$btnRun.Location = New-Object Drawing.Point(10, $btnY); $btnRun.Size = New-Object Drawing.Size(105, 28)
$btnRun.Font = New-Object Drawing.Font($btnRun.Font, [Drawing.FontStyle]::Bold)
$gOp.Controls.Add($btnRun)
$tip.SetToolTip($btnRun, 'Run - runs the checked ISP stages, then Start Application if that box is ticked. Opens a progress popup and colours each stage (F5)')
$btnClearOps = New-Object Windows.Forms.Button; $btnClearOps.Text = 'Clear'
$btnClearOps.Location = New-Object Drawing.Point(120, $btnY); $btnClearOps.Size = New-Object Drawing.Size(110, 28)
$gOp.Controls.Add($btnClearOps)
$btnClearOps.Add_Click({
    $chkOps['Erase'].Checked = $true; $chkOps['Blank Check'].Checked = $true
    $chkOps['Program'].Checked = $true; $chkOps['Verify'].Checked = $true
    $chkOps['Start Application'].Checked = $true
    foreach ($k in @($chkAutoFlow.Keys)) { $chkAutoFlow[$k].Checked = $true }
    Clear-OpsResult; Log 'operations flow cleared - ISP stages and automation back to defaults'
})
$tip.SetToolTip($btnClearOps, 'Clear - reset every operation checkbox and every automation checkbox to defaults, and clear the pass/fail colours')
$chkTarget = New-Object Windows.Forms.ComboBox; $chkTarget.DropDownStyle = 'DropDownList'
$chkTarget.Items.AddRange([string[]]@('FLASH', 'EEPROM')); $chkTarget.SelectedIndex = 0
$lblTarget = New-Object Windows.Forms.Label; $lblTarget.Text = 'Memory'; $lblTarget.Location = New-Object Drawing.Point(10, ($btnY + 36)); $lblTarget.Size = New-Object Drawing.Size(60, 20)
$gOp.Controls.Add($lblTarget)
$chkTarget.Location = New-Object Drawing.Point(74, ($btnY + 34)); $chkTarget.Size = New-Object Drawing.Size(156, 20); $gOp.Controls.Add($chkTarget)
$tip.SetToolTip($lblTarget, 'Target memory for all ISP operations')
$tip.SetToolTip($chkTarget, 'Target memory - FLASH is what SDCC hex files use. EEPROM only if your build targets it')
$chkTarget.Add_SelectedIndexChanged({
    try { $mem = ("$($chkTarget.Text)").Trim(); if ($mem -ne '') { $cfg.TargetMem = $mem; Save-Config $cfg } } catch {}
})
$chkAuto = New-Object Windows.Forms.CheckBox; $chkAuto.Text = 'AutoISP'
$chkAuto.Location = New-Object Drawing.Point(10, ($btnY + 58)); $chkAuto.Size = New-Object Drawing.Size(220, 20)
$chkAuto.Checked = [bool]$cfg.AutoIsp; $gOp.Controls.Add($chkAuto)
$tip.SetToolTip($chkAuto, 'AutoISP - batchisp -autoisp <RESET level> <PSEN level>. Sends 1 0: RESET active-high, PSEN active-low. Needs DTR->RST + RTS->PSEN wiring; leave OFF if your board has real ISP wiring')

# middle: FLASH Buffer Information
$gBuf = New-Object Windows.Forms.GroupBox; $gBuf.Text = 'FLASH Buffer Information'
$gBuf.Location = New-Object Drawing.Point(258, $top); $gBuf.Size = New-Object Drawing.Size($PW_MID, 380)
$form.Controls.Add($gBuf)
$tip.SetToolTip($gBuf, 'FLASH Buffer Information - address range, checksum, size and filename of the loaded hex (same fields Flip shows)')
$lblSize = New-Object Windows.Forms.Label; $lblSize.Text = 'Size  64 KB   Range 0x0 - 0x0'; $lblSize.Location = New-Object Drawing.Point(10, 22); $lblSize.Size = New-Object Drawing.Size(278, 30); $gBuf.Controls.Add($lblSize)
$tip.SetToolTip($lblSize, 'Hex file size and address range (parsed from Intel HEX)')
$lblSum = New-Object Windows.Forms.Label; $lblSum.Text = 'Checksum 0xFF'; $lblSum.Location = New-Object Drawing.Point(10, 52); $lblSum.Size = New-Object Drawing.Size(278, 20); $gBuf.Controls.Add($lblSum)
$tip.SetToolTip($lblSum, 'Data byte count and Debug/Release variant from path')
$l = New-Object Windows.Forms.Label; $l.Text = 'HEX File:'; $l.Location = New-Object Drawing.Point(10, 80); $l.Size = New-Object Drawing.Size(278, 16); $gBuf.Controls.Add($l)
$tip.SetToolTip($l, 'Selected hex file - click Browse or use MRU dropdown (Ctrl+O)')
if ($cfg.RecentHex -eq $null) { $cfg.RecentHex = @() }
$cmbHex = New-Object Windows.Forms.ComboBox; $cmbHex.DropDownStyle = 'DropDown'
$cmbHex.Location = New-Object Drawing.Point(10, 98); $cmbHex.Size = New-Object Drawing.Size(250, 21)
$gBuf.Controls.Add($cmbHex)
$cmbHex.Text = $cfg.HexFile
foreach ($h in @($cfg.RecentHex)) { if (("$h").Trim() -ne '') { [void]$cmbHex.Items.Add($h) } }
if ($cmbHex.Text -ne '' -and -not $cmbHex.Items.Contains($cmbHex.Text)) { [void]$cmbHex.Items.Add($cmbHex.Text) }
$tip.SetToolTip($cmbHex, $cfg.HexFile)
$cmbHex.Add_SelectedIndexChanged({ Sync-HexFromCombo })
$cmbHex.Add_Leave({ Sync-HexFromCombo })
$cmbHex.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Sync-HexFromCombo } })
$lblHexAge = New-Object Windows.Forms.Label; $lblHexAge.Text = 'age unknown'
$lblHexAge.Location = New-Object Drawing.Point(10, 121); $lblHexAge.Size = New-Object Drawing.Size(278, 14); $gBuf.Controls.Add($lblHexAge)
$tip.SetToolTip($lblHexAge, 'Time since hex file was last built')
$lblNewer = New-Object Windows.Forms.Label; $lblNewer.Text = ''
$lblNewer.Location = New-Object Drawing.Point(10, 136); $lblNewer.Size = New-Object Drawing.Size(278, 16)
$lblNewer.ForeColor = [Drawing.Color]::Blue; $lblNewer.Cursor = [Windows.Forms.Cursors]::Hand; $lblNewer.Visible = $false
$gBuf.Controls.Add($lblNewer)
$tip.SetToolTip($lblNewer, 'A newer hex build exists - click to switch (never auto-switches)')
$script:NewerHexPath = $null
$lblNewer.Add_Click({ if ($script:NewerHexPath -ne $null -and (Test-Path $script:NewerHexPath)) { $cmbHex.Text = $script:NewerHexPath; Add-RecentHex $script:NewerHexPath; Update-HexInfo; Update-StateNext 'Press Run (F5)'; Log ('switched to newer build: ' + $script:NewerHexPath) } })
$btnBrowse = New-Object Windows.Forms.Button; $btnBrowse.Text = 'Browse...'
$btnBrowse.Location = New-Object Drawing.Point(10, 124); $btnBrowse.Size = New-Object Drawing.Size(120, 24); $gBuf.Controls.Add($btnBrowse)
$tip.SetToolTip($btnBrowse, 'Browse... - pick a hex file (Ctrl+O)')
$btnNewest = New-Object Windows.Forms.Button; $btnNewest.Text = 'Newest Hex'
$btnNewest.Location = New-Object Drawing.Point(140, 124); $btnNewest.Size = New-Object Drawing.Size(120, 24); $gBuf.Controls.Add($btnNewest)
$tip.SetToolTip($btnNewest, 'Newest Hex - auto-pick newest CodeBlocks bin\*.hex')
$logo = New-Object Windows.Forms.Label; $logo.Text = 'FLIPpen Hel'; $logo.Font = New-Object Drawing.Font('Arial Black', 26, ([Drawing.FontStyle]::Bold -bor [Drawing.FontStyle]::Italic))
$logo.ForeColor = [Drawing.Color]::Gray; $logo.Location = New-Object Drawing.Point(10, 170); $logo.Size = New-Object Drawing.Size(278, 50); $logo.TextAlign = 'MiddleCenter'
$gBuf.Controls.Add($logo)
$tip.SetToolTip($logo, 'FLIPpen Hel - a zero-install Flip replacement for AT89LP51RD2 development')
$lblLogoSub = New-Object Windows.Forms.Label; $lblLogoSub.Text = "Want Atmel FLIP was 'n groot FLOP"; $lblLogoSub.ForeColor = [Drawing.Color]::Gray; $lblLogoSub.Font = New-Object Drawing.Font($form.Font.FontFamily, 10); $lblLogoSub.Location = New-Object Drawing.Point(10, 224); $lblLogoSub.Size = New-Object Drawing.Size(278, 20); $lblLogoSub.TextAlign = 'MiddleCenter'
$tip.SetToolTip($lblLogoSub, "Subtitle in Afrikaans: 'Wish Atmel FLIP was a big FLOP' - the Dutch/Afrikaans pun behind the name FLIPpen Hel")
$gBuf.Controls.Add($lblLogoSub)

# right: device panel
$gDev = New-Object Windows.Forms.GroupBox; $gDev.Text = $DefaultDevice
$gDev.Location = New-Object Drawing.Point(568, $top); $gDev.Size = New-Object Drawing.Size($PW_RIGHT, 380)
$form.Controls.Add($gDev)
$tip.SetToolTip($gDev, ('Device frame - ' + $DefaultDevice + '. Signature bytes, boot ids, hardware/security bits, then the run buttons. Collapse with the +/- toggle'))
$script:SigControls = @()
$btnSigToggle = New-Object Windows.Forms.Button; $btnSigToggle.Text = '-'
$btnSigToggle.Location = New-Object Drawing.Point(264, 0); $btnSigToggle.Size = New-Object Drawing.Size(20, 16)
$gDev.Controls.Add($btnSigToggle)
$tip.SetToolTip($btnSigToggle, 'Hide signature rows (display-only)')
function Dev-Row($yy, $label, $n) {
    $x = New-Object Windows.Forms.Label; $x.Text = $label; $x.Location = New-Object Drawing.Point(10, ($yy + 3)); $x.Size = New-Object Drawing.Size(95, 20); $gDev.Controls.Add($x)
    $tip.SetToolTip($x, ($label + ' - read from the device signature (display only; use Device > Write/Read Special Bits to change the writable ones)'))
    $script:SigControls += $x
    $boxes = @()
    for ($i = 0; $i -lt $n; $i++) {
        $t = New-Object Windows.Forms.TextBox; $t.Size = New-Object Drawing.Size(34, 20)
        $t.Location = New-Object Drawing.Point((110 + ($i * 40)), $yy); $t.ReadOnly = $true; $gDev.Controls.Add($t); $boxes += $t
        $tip.SetToolTip($t, ($label + ' byte ' + ($i + 1) + ' - hex value read from the chip'))
        $script:SigControls += $t
    }
}
Dev-Row 22 'Signature Bytes' 3
Dev-Row 50 'Device Boot Ids' 2
$bl = New-Object Windows.Forms.Label; $bl.Text = 'Hardware Byte'; $bl.Location = New-Object Drawing.Point(10, 81); $bl.Size = New-Object Drawing.Size(95, 20); $gDev.Controls.Add($bl)
$tip.SetToolTip($bl, 'Hardware revision byte from device signature')
$txtHw = New-Object Windows.Forms.TextBox; $txtHw.Size = New-Object Drawing.Size(34, 20); $txtHw.Location = New-Object Drawing.Point(110, 78); $txtHw.ReadOnly = $true; $gDev.Controls.Add($txtHw)
$tip.SetToolTip($txtHw, 'Hardware Byte - hex value read from the chip. A full chip erase resets it to default')
$chkBljb = New-Object Windows.Forms.CheckBox; $chkBljb.Text = 'BLJB'; $chkBljb.Location = New-Object Drawing.Point(150, 78); $chkBljb.Size = New-Object Drawing.Size(55, 20); $chkBljb.Enabled = $false; $gDev.Controls.Add($chkBljb)
$tip.SetToolTip($chkBljb, 'Boot loader jump bit - display only')
$chkX2 = New-Object Windows.Forms.CheckBox; $chkX2.Text = 'X2'; $chkX2.Location = New-Object Drawing.Point(205, 78); $chkX2.Size = New-Object Drawing.Size(45, 20); $chkX2.Enabled = $false; $gDev.Controls.Add($chkX2)
$tip.SetToolTip($chkX2, 'X2 mode bit - display only')
$sl = New-Object Windows.Forms.Label; $sl.Text = 'Security Level'; $sl.Location = New-Object Drawing.Point(10, 108); $sl.Size = New-Object Drawing.Size(250, 16); $gDev.Controls.Add($sl)
$tip.SetToolTip($sl, 'Flash security level from device signature')
$rb0 = New-Object Windows.Forms.RadioButton; $rb0.Text = 'Level 0'; $rb0.Checked = $true; $rb0.Location = New-Object Drawing.Point(10, 126); $rb0.Size = New-Object Drawing.Size(80, 20); $rb0.Enabled = $false; $gDev.Controls.Add($rb0)
$tip.SetToolTip($rb0, 'Security Level 0 - no protection')
$rb1 = New-Object Windows.Forms.RadioButton; $rb1.Text = 'Level 1'; $rb1.Location = New-Object Drawing.Point(100, 126); $rb1.Size = New-Object Drawing.Size(80, 20); $rb1.Enabled = $false; $gDev.Controls.Add($rb1)
$tip.SetToolTip($rb1, 'Security Level 1 - write protect')
$rb2 = New-Object Windows.Forms.RadioButton; $rb2.Text = 'Level 2'; $rb2.Location = New-Object Drawing.Point(190, 126); $rb2.Size = New-Object Drawing.Size(80, 20); $rb2.Enabled = $false; $gDev.Controls.Add($rb2)
$tip.SetToolTip($rb2, 'Security Level 2 - read/write protect')
$note = New-Object Windows.Forms.Label
$note.Text = 'Signature/security boxes are display-only in FLIPpen Hel (read from Flip if needed).'
$note.Location = New-Object Drawing.Point(10, 150); $note.Size = New-Object Drawing.Size(272, 30); $gDev.Controls.Add($note)
$tip.SetToolTip($note, 'These fields are for display only; FLIPpen Hel does not read them from the chip')
$script:SigControls += @($bl, $txtHw, $chkBljb, $chkX2, $sl, $rb0, $rb1, $rb2, $note)
$btnStartApp = New-Object Windows.Forms.Button; $btnStartApp.Text = 'Start Application'
$btnStartApp.Location = New-Object Drawing.Point(10, 190); $btnStartApp.Size = New-Object Drawing.Size(132, 28); $gDev.Controls.Add($btnStartApp)
$tip.SetToolTip($btnStartApp, 'Start Application - START RESET 0 only, no flash (F6)')
$btnFwReset = New-Object Windows.Forms.Button; $btnFwReset.Text = 'Firmware Reset'
$btnFwReset.Location = New-Object Drawing.Point(10, 222); $btnFwReset.Size = New-Object Drawing.Size(124, 28); $gDev.Controls.Add($btnFwReset)
$tip.SetToolTip($btnFwReset, 'Firmware Reset - send !!!RESET!!! over serial to reboot the app (Ctrl+R). Needs the snippet in firmware.')
$btnFwHelp = New-Object Windows.Forms.Button; $btnFwHelp.Text = '?'
$btnFwHelp.Location = New-Object Drawing.Point(140, 222); $btnFwHelp.Size = New-Object Drawing.Size(18, 28); $gDev.Controls.Add($btnFwHelp)
$tip.SetToolTip($btnFwHelp, 'What does Firmware Reset do? Opens the reset explanation window (no shortcut)')
$script:SigGroupH = $gDev.Size.Height
$script:SigCollapsedH = 285
function Set-SigCollapsed($collapsed) {
    $collapsed = [bool]$collapsed
    foreach ($c in $script:SigControls) { $c.Visible = (-not $collapsed) }
    if ($collapsed) {
        $gDev.Size = New-Object Drawing.Size($PW_RIGHT, $script:SigCollapsedH)
        $btnSigToggle.Text = '+'
        $tip.SetToolTip($btnSigToggle, 'Show signature rows (display-only)')
    } else {
        $gDev.Size = New-Object Drawing.Size($PW_RIGHT, $script:SigGroupH)
        $btnSigToggle.Text = '-'
        $tip.SetToolTip($btnSigToggle, 'Hide signature rows (display-only)')
    }
    $cfg.CollapsedSig = $collapsed
    Save-Config $cfg
}
$btnSigToggle.Add_Click({ Set-SigCollapsed (-not [bool]$cfg.CollapsedSig) })
$initSig = $true
try { if ($cfg.CollapsedSig -ne $null) { $initSig = [bool]$cfg.CollapsedSig } } catch {}
Set-SigCollapsed $initSig

# Device picker dialog (modeless, owned)
function Show-DevicePicker {
    $devTokens = @(Get-DeviceTokens)
    if ($devTokens.Count -eq 0) { Log 'no device tokens found in Flip part files'; return }
    $pickForm = New-Object Windows.Forms.Form
    $pickForm.Text = 'Select Device'
    $pickForm.Size = New-Object Drawing.Size(360, 400)
    $pickForm.StartPosition = 'CenterParent'
    $pickForm.FormBorderStyle = 'FixedDialog'
    $pickForm.MaximizeBox = $false
    $pickForm.MinimizeBox = $false
    $pickForm.ShowInTaskbar = $false
    [void]$form.AddOwnedForm($pickForm)
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = 'Click a device to select:'; $lbl.Location = New-Object Drawing.Point(12, 12); $lbl.Size = New-Object Drawing.Size(320, 20); $pickForm.Controls.Add($lbl)
    $tip.SetToolTip($lbl, 'Devices harvested from the Flip part description files - this is the same list Flip offers')
    $lb = New-Object Windows.Forms.ListBox; $lb.Location = New-Object Drawing.Point(12, 36); $lb.Size = New-Object Drawing.Size(320, 300); $pickForm.Controls.Add($lb)
    $tip.SetToolTip($lb, 'Device list - click one, then OK to use it for flashing')
    foreach ($t in $devTokens) { [void]$lb.Items.Add($t) }
    $btnOK = New-Object Windows.Forms.Button; $btnOK.Text = 'OK'; $btnOK.Location = New-Object Drawing.Point(180, 340); $btnOK.Size = New-Object Drawing.Size(70, 26); $pickForm.Controls.Add($btnOK)
    $tip.SetToolTip($btnOK, 'OK - use the selected device and close this window')
    $btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = 'Cancel'; $btnCancel.Location = New-Object Drawing.Point(260, 340); $btnCancel.Size = New-Object Drawing.Size(70, 26); $pickForm.Controls.Add($btnCancel)
    $tip.SetToolTip($btnCancel, 'Cancel - close without changing the device')
    $btnOK.Add_Click(({ if ($lb.SelectedItem) { $txtDev.Text = $lb.SelectedItem; $tip.SetToolTip($txtDev, ('device: ' + $lb.SelectedItem + ' (batchisp -device name)')); Update-StateNext 'Press Run (F5)'; Log ('device: ' + $lb.SelectedItem) }; $pickForm.Close() }).GetNewClosure())
    $btnCancel.Add_Click(({ $pickForm.Close() }).GetNewClosure())
    $lb.Add_DoubleClick(({ if ($lb.SelectedItem) { $btnOK.PerformClick() } }).GetNewClosure())
    $pickForm.Show($form)
}

# ---------- firmware reset help dialog (modeless, owned by main form) ----------
function Copy-FirmwareSnippet {
    try { [Windows.Forms.Clipboard]::SetText($FirmwareSnippet); Log 'firmware snippet copied - paste into main.c + call UartResetPoll() in while(1)' }
    catch { Log ('clipboard failed: ' + $_.Exception.Message) }
}
$helpForm = New-Object Windows.Forms.Form
$helpForm.Text = 'firmware reset - explanation'
$helpForm.Size = New-Object Drawing.Size(520, 480)
$helpForm.StartPosition = 'CenterParent'
$helpForm.FormBorderStyle = 'FixedDialog'
$helpForm.MaximizeBox = $false
$helpForm.MinimizeBox = $false
$helpForm.ShowInTaskbar = $false
$helpForm.KeyPreview = $true
$txtHelpExplain = New-Object Windows.Forms.TextBox
$txtHelpExplain.Multiline = $true; $txtHelpExplain.ScrollBars = 'Vertical'; $txtHelpExplain.ReadOnly = $true
$txtHelpExplain.Location = New-Object Drawing.Point(12, 12); $txtHelpExplain.Size = New-Object Drawing.Size(480, 150)
$txtHelpExplain.Text = "What firmware reset does:`r`nSends !!!RESET!!! + CRLF on the open serial port. The snippet below (UartResetPoll) watches for 3x '!' and reboots the APP from address 0 - a fast restart for testing without reflashing.`r`n`r`nWhat it does NOT do:`r`nIt cannot enter the bootloader over TX/RX. Entering the bootloader still needs the ISP hardware condition / BLJB / AutoISP wiring - a serial text command alone cannot do that.`r`n`r`nWiring notes:`r`nFor true hands-free flashing use DTR->RST (Arduino-style auto-reset) plus the ISP hardware condition or BLJB/AutoISP wiring. The Settings window has a 120ms DTR pulse button (needs DTR->RST wiring)."
$tip.SetToolTip($txtHelpExplain, 'Explanation of what firmware reset does and what it cannot do')
$helpForm.Controls.Add($txtHelpExplain)
$txtHelpSnippet = New-Object Windows.Forms.TextBox
$txtHelpSnippet.Multiline = $true; $txtHelpSnippet.ScrollBars = 'Both'; $txtHelpSnippet.ReadOnly = $true
$txtHelpSnippet.Font = New-Object Drawing.Font('Consolas', 9)
$txtHelpSnippet.Location = New-Object Drawing.Point(12, 170); $txtHelpSnippet.Size = New-Object Drawing.Size(480, 200)
$txtHelpSnippet.Text = $FirmwareSnippet
$helpForm.Controls.Add($txtHelpSnippet)
$tip.SetToolTip($txtHelpSnippet, 'C code to paste into your main loop - press Copy Code (Ctrl+Shift+C) to put it on the clipboard')
$btnHelpCopy = New-Object Windows.Forms.Button; $btnHelpCopy.Text = 'Copy Code'
$btnHelpCopy.Location = New-Object Drawing.Point(12, 378); $btnHelpCopy.Size = New-Object Drawing.Size(120, 26)
$helpForm.Controls.Add($btnHelpCopy)
$tip.SetToolTip($btnHelpCopy, 'Copy Code - copy the C reset snippet to clipboard (Ctrl+Shift+C)')
$btnHelpClose = New-Object Windows.Forms.Button; $btnHelpClose.Text = 'Close'
$btnHelpClose.Location = New-Object Drawing.Point(400, 378); $btnHelpClose.Size = New-Object Drawing.Size(90, 26)
$btnHelpClose.Add_Click({ $helpForm.Close() }); $helpForm.Controls.Add($btnHelpClose)
$tip.SetToolTip($btnHelpClose, 'Close - hide this window (reopens on demand, settings kept)')
$btnHelpCopy.Add_Click({ Copy-FirmwareSnippet })
$helpForm.Add_KeyDown({ if ($_.Control -and $_.Shift -and $_.KeyCode -eq 'C') { Copy-FirmwareSnippet; $_.Handled = $true } })
[void]$form.AddOwnedForm($helpForm)
function Show-Help { if ($helpForm.Visible) { $helpForm.Activate() } else { $helpForm.Show($form) } }
$helpForm.Add_FormClosing({ if ($form.Visible) { $_.Cancel = $true; $helpForm.Hide() } })
$btnFwHelp.Add_Click({ Show-Help })
$chkDtr = New-Object Windows.Forms.CheckBox; $chkDtr.Text = 'DTR'; $chkDtr.Location = New-Object Drawing.Point(180, 190); $chkDtr.Size = New-Object Drawing.Size(55, 20); $gDev.Controls.Add($chkDtr)
$chkRts = New-Object Windows.Forms.CheckBox; $chkRts.Text = 'RTS'; $chkRts.Location = New-Object Drawing.Point(235, 190); $chkRts.Size = New-Object Drawing.Size(55, 20); $gDev.Controls.Add($chkRts)
$tip.SetToolTip($chkDtr, 'DTR line state. Only resets chip if DTR is wired to RST')
$tip.SetToolTip($chkRts, 'RTS line state. Only enters ISP if wired to PSEN')
$btnPulse = New-Object Windows.Forms.Button; $btnPulse.Text = 'Pulse DTR'
$btnPulse.Location = New-Object Drawing.Point(180, 214); $btnPulse.Size = New-Object Drawing.Size(105, 24); $gDev.Controls.Add($btnPulse)
$tip.SetToolTip($btnPulse, 'Pulse DTR - 120ms DTR reset pulse (needs DTR->RST wiring)')

# connection row + serial monitor (Termite-like, below the Flip panels)
$cy = $top + 308
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$lblP = New-Object Windows.Forms.Label; $lblP.Text = 'Port'; $lblP.Location = New-Object Drawing.Point(12, ($cy + 4)); $lblP.Size = New-Object Drawing.Size(35, 20); $form.Controls.Add($lblP)
$cmbPort = New-Object Windows.Forms.ComboBox; $cmbPort.Location = New-Object Drawing.Point(50, $cy); $cmbPort.Size = New-Object Drawing.Size(100, 20); $cmbPort.DropDownStyle = 'DropDown'
$form.Controls.Add($cmbPort)
$tip.SetToolTip($cmbPort, 'Auto-scanned, Bluetooth excluded. Click Refresh to rescan')
$btnRefresh = New-Object Windows.Forms.Button; $btnRefresh.Text = 'Refresh'
$btnRefresh.Location = New-Object Drawing.Point(155, ($cy - 1)); $btnRefresh.Size = New-Object Drawing.Size(65, 23); $form.Controls.Add($btnRefresh)
$tip.SetToolTip($btnRefresh, 'Refresh - rescan COM ports (Bluetooth ignored)')
$lblB = New-Object Windows.Forms.Label; $lblB.Text = 'ISP'; $lblB.Location = New-Object Drawing.Point(228, ($cy + 4)); $lblB.Size = New-Object Drawing.Size(28, 20); $form.Controls.Add($lblB)
$tip.SetToolTip($lblB, 'ISP baud rate for batchisp')
$txtIspBaud = New-Object Windows.Forms.TextBox; $txtIspBaud.Text = $cfg.IspBaud; $txtIspBaud.Location = New-Object Drawing.Point(256, $cy); $txtIspBaud.Size = New-Object Drawing.Size(70, 20); $form.Controls.Add($txtIspBaud)
$tip.SetToolTip($txtIspBaud, 'ISP baud rate for batchisp (default 115200)')
$lblM = New-Object Windows.Forms.Label; $lblM.Text = 'Mon'; $lblM.Location = New-Object Drawing.Point(332, ($cy + 4)); $lblM.Size = New-Object Drawing.Size(32, 20); $form.Controls.Add($lblM)
$tip.SetToolTip($lblM, 'Monitor baud rate for serial terminal')
$txtMonBaud = New-Object Windows.Forms.TextBox; $txtMonBaud.Text = $cfg.MonBaud; $txtMonBaud.Location = New-Object Drawing.Point(364, $cy); $txtMonBaud.Size = New-Object Drawing.Size(70, 20); $form.Controls.Add($txtMonBaud)
$tip.SetToolTip($txtMonBaud, 'App serial baud. Your projects use 9600 8N1')
$txtDev = New-Object Windows.Forms.TextBox; $txtDev.Text = $cfg.Device; $txtDev.Location = New-Object Drawing.Point(440, $cy); $txtDev.Size = New-Object Drawing.Size(110, 20); $form.Controls.Add($txtDev)
$tip.SetToolTip($txtDev, 'batchisp -device name. Flip 3.4.7 knows AT89C51RD2, not AT89LP51RD2')
$btnConnect = New-Object Windows.Forms.Button; $btnConnect.Text = 'Serial: Connect'
$btnConnect.Location = New-Object Drawing.Point(10, 254); $btnConnect.Size = New-Object Drawing.Size(110, 23); $gDev.Controls.Add($btnConnect)
$tip.SetToolTip($btnConnect, 'Serial: Connect/Disconnect - open/close the serial monitor (Ctrl+T)')
$btnClear = New-Object Windows.Forms.Button; $btnClear.Text = 'Clear'
$btnClear.Location = New-Object Drawing.Point(671, ($cy - 1)); $btnClear.Size = New-Object Drawing.Size(60, 23); $form.Controls.Add($btnClear)
$tip.SetToolTip($btnClear, 'Clear monitor (Ctrl+L)')

# ---------- Settings dialog (Task 4: connection extras live here, off the main face; Task 18: modeless owned window) ----------
$settingsForm = New-Object Windows.Forms.Form
$settingsForm.Text = 'Settings'
$settingsForm.Size = New-Object Drawing.Size(380, 292)
$settingsForm.StartPosition = 'CenterParent'
$settingsForm.FormBorderStyle = 'FixedDialog'
$settingsForm.MaximizeBox = $false
$settingsForm.MinimizeBox = $false
$settingsForm.ShowInTaskbar = $false
$lblDevName = New-Object Windows.Forms.Label; $lblDevName.Text = 'Device'; $lblDevName.Location = New-Object Drawing.Point(12, 76); $lblDevName.Size = New-Object Drawing.Size(45, 20); $settingsForm.Controls.Add($lblDevName)
$tip.SetToolTip($lblDevName, 'batchisp -device name (e.g. AT89C51RD2)')
$btnSettingsClose = New-Object Windows.Forms.Button; $btnSettingsClose.Text = 'Close'
$btnSettingsClose.Location = New-Object Drawing.Point(140, 214); $btnSettingsClose.Size = New-Object Drawing.Size(90, 26)
$btnSettingsClose.Add_Click({ $settingsForm.Close() }); $settingsForm.Controls.Add($btnSettingsClose)
$tip.SetToolTip($btnSettingsClose, 'Close settings (changes saved automatically)')
$settingsItem = New-Object Windows.Forms.ToolStripMenuItem; $settingsItem.Text = 'Connection settings...'
$settingsItem.ToolTipText = 'Open connection settings dialog'
$settingsItem.Add_Click({ Show-Settings }); [void]$settingsMenu.DropDownItems.Add($settingsItem)
$termItem = New-Object Windows.Forms.ToolStripMenuItem; $termItem.Text = 'Terminal window...'
$termItem.ToolTipText = 'Open pop-out terminal window'
$termItem.Add_Click({ Show-Terminal }); [void]$settingsMenu.DropDownItems.Add($termItem)
$deviceMenu = New-Object Windows.Forms.ToolStripMenuItem; $deviceMenu.Text = 'Device'
$deviceMenu.ToolTipText = 'Recent device picks (click to fill the device field)'
[void]$settingsMenu.DropDownItems.Add($deviceMenu)
$deviceMenu.Add_DropDownOpening({ Update-DeviceMenu })
function Move-ToSettings($c, $x, $y) {
    $form.Controls.Remove($c); $gBuf.Controls.Remove($c); $gDev.Controls.Remove($c)
    $c.Location = New-Object Drawing.Point($x, $y)
    [void]$settingsForm.Controls.Add($c)
}
Move-ToSettings $lblP 12 16
Move-ToSettings $cmbPort 60 12
Move-ToSettings $btnRefresh 170 11
Move-ToSettings $lblB 245 16
Move-ToSettings $txtIspBaud 273 12
Move-ToSettings $lblM 12 46
Move-ToSettings $txtMonBaud 60 42
Move-ToSettings $txtDev 60 72
Move-ToSettings $chkDtr 12 102
Move-ToSettings $chkRts 70 102
Move-ToSettings $btnPulse 130 100
Move-ToSettings $btnBrowse 12 132
Move-ToSettings $btnNewest 142 132
$chkSerialAuto = New-Object Windows.Forms.CheckBox; $chkSerialAuto.Text = 'Serial auto-open on RX data'
$chkSerialAuto.Location = New-Object Drawing.Point(12, 184); $chkSerialAuto.Size = New-Object Drawing.Size(340, 20)
$chkSerialAuto.Checked = [bool]$cfg.SerialAuto; $settingsForm.Controls.Add($chkSerialAuto)
$tip.SetToolTip($chkSerialAuto, 'ON shows the terminal on first RX bytes (Serial: Auto). OFF is fully manual (Serial: Connect).')
# Task 18: modeless owned Settings. Live-write-through (each control saves on
# change) + save-on-close, so no OK gate can lose a value. Run-BatchIsp
# snapshots control values at click time, so an open Settings never desyncs.
[void]$form.AddOwnedForm($settingsForm)
function Save-SettingsToConfig {
    try { $cfg.Device = ("$($txtDev.Text)").Trim() } catch {}
    try { $cfg.Port = ("$($cmbPort.Text)").Trim() } catch {}
    try { $cfg.IspBaud = ("$($txtIspBaud.Text)").Trim() } catch {}
    try { $cfg.MonBaud = ("$($txtMonBaud.Text)").Trim() } catch {}
    try { $cfg.AutoIsp = [bool]$chkAuto.Checked } catch {}
    try { $cfg.SerialAuto = [bool]$chkSerialAuto.Checked } catch {}
    try {
        if ($chkAutoFlow -ne $null) {
            $flow = @{}
            foreach ($k in @($chkAutoFlow.Keys)) { $flow[$k] = [bool]$chkAutoFlow[$k].Checked }
            $cfg.AutoFlow = $flow
        }
    } catch {}
    try { $cfg.HexFile = ("$($cmbHex.Text)").Trim('" ').Trim() } catch {}
    Save-Config $cfg
}
function Show-Settings { if ($settingsForm.Visible) { $settingsForm.Activate() } else { $settingsForm.Show($form) } }
$settingsForm.Add_FormClosing({ Save-SettingsToConfig; if ($form.Visible) { $_.Cancel = $true; $settingsForm.Hide() } })
$txtDev.Add_TextChanged({ Save-SettingsToConfig })
$txtIspBaud.Add_TextChanged({ Save-SettingsToConfig })
$txtMonBaud.Add_TextChanged({ Save-SettingsToConfig })
$cmbPort.Add_TextChanged({ Save-SettingsToConfig })
$chkAuto.Add_CheckedChanged({ Save-SettingsToConfig })
$chkSerialAuto.Add_CheckedChanged({ Save-SettingsToConfig; Update-SerialButtons; try { $chkAutoFlow['Auto-open terminal'].Checked = [bool]$chkSerialAuto.Checked } catch {} })
# Operations Flow automation checkboxes write through to the Settings mirror and
# to the config, so a switch off in either place sticks. Wired further down,
# once the flow checkboxes exist.
function Wire-AutoFlowCheckboxes {
    if ($script:autoFlowWired) { return }
    $script:autoFlowWired = $true
    foreach ($k in @($chkAutoFlow.Keys)) {
        $cb = $chkAutoFlow[$k]
        $cb.Add_CheckedChanged(({
            try { if ($k -eq 'Auto-open terminal') { $chkSerialAuto.Checked = [bool]$cb.Checked } } catch {}
            try { Save-SettingsToConfig } catch {}
        }).GetNewClosure())
    }
}
$lblBatchisp = New-Object Windows.Forms.Label; $lblBatchisp.Text = 'batchisp'; $lblBatchisp.Location = New-Object Drawing.Point(12, 160); $lblBatchisp.Size = New-Object Drawing.Size(55, 20); $settingsForm.Controls.Add($lblBatchisp)
$tip.SetToolTip($lblBatchisp, 'Path to Atmel batchisp.exe (auto-detected from your Flip install)')
$txtBatchisp = New-Object Windows.Forms.TextBox; $txtBatchisp.Text = $BatchIsp; $txtBatchisp.ReadOnly = $true; $txtBatchisp.Location = New-Object Drawing.Point(70, 158); $txtBatchisp.Size = New-Object Drawing.Size(280, 20); $settingsForm.Controls.Add($txtBatchisp)
$tip.SetToolTip($txtBatchisp, 'Path to Atmel batchisp.exe (auto-detected)')

# Port label in Settings needs its tooltip too
$tip.SetToolTip($lblP, 'COM port used for both ISP and the serial monitor. Bluetooth ports are excluded')

$termLog = New-Object Windows.Forms.TextBox
$termLog.Multiline = $true; $termLog.ScrollBars = 'Vertical'; $termLog.ReadOnly = $true
$termLog.Font = New-Object Drawing.Font('Consolas', 9)
$termLog.Location = New-Object Drawing.Point(8, ($cy + 28)); $termLog.Size = New-Object Drawing.Size(766, 150)
$form.Controls.Add($termLog)
$tip.SetToolTip($termLog, 'Serial monitor - every byte received from the chip, plus action log lines')
$txtSend = New-Object Windows.Forms.TextBox; $txtSend.Location = New-Object Drawing.Point(8, ($cy + 182)); $txtSend.Size = New-Object Drawing.Size(660, 20); $form.Controls.Add($txtSend)
$tip.SetToolTip($txtSend, 'Type here, Enter to send')
$btnSend = New-Object Windows.Forms.Button; $btnSend.Text = 'Send'
$btnSend.Location = New-Object Drawing.Point(674, ($cy + 181)); $btnSend.Size = New-Object Drawing.Size(100, 23); $form.Controls.Add($btnSend)
$tip.SetToolTip($btnSend, 'Send text from input box + CRLF (Enter in input box)')

# ---------- terminal pop-out (owned window, auto-shows on RX) ----------
$termForm = New-Object Windows.Forms.Form
$termForm.Text = 'Terminal (disconnected)'
$termForm.Size = New-Object Drawing.Size(640, 400)
$termForm.StartPosition = 'CenterParent'
$termForm.KeyPreview = $true
$termForm.ShowInTaskbar = $true
[void]$form.AddOwnedForm($termForm)
function Update-TermTitle {
    if ($script:port -ne $null -and $script:port.IsOpen) {
        $pname = $script:port.PortName
        if ([bool]$script:PortAuto) { $pname += ' (auto)' }
        $termForm.Text = ('Terminal - ' + $pname + ' @ ' + $txtMonBaud.Text)
    }
    else { $termForm.Text = 'Terminal (disconnected)' }
}
function Show-Terminal { Update-TermTitle; if (-not $termForm.Visible) { $termForm.Show() } }
function Hide-Terminal { $termForm.Hide() }
function Toggle-Terminal { if ($termForm.Visible) { Hide-Terminal } else { Show-Terminal } }
$termForm.Add_FormClosing({
    if ($form.Visible) { $_.Cancel = $true; Hide-Terminal }
})
$termForm.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq 'L') { $btnClear.PerformClick(); $_.Handled = $true }
})
$btnTermDisconnect = New-Object Windows.Forms.Button; $btnTermDisconnect.Text = 'Disconnect'
$btnTermDisconnect.Location = New-Object Drawing.Point(140, 293); $btnTermDisconnect.Size = New-Object Drawing.Size(120, 23)
$btnTermDisconnect.Add_Click({ Close-Serial; Log 'serial closed' })
$termForm.Controls.Add($btnTermDisconnect)
$tip.SetToolTip($btnTermDisconnect, 'Disconnect - drop the serial port (window stays open)')
function Move-ToTerminal($c, $x, $y, $w, $h) {
    $form.Controls.Remove($c); $gDev.Controls.Remove($c); $gBuf.Controls.Remove($c); $settingsForm.Controls.Remove($c)
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, $h)
    [void]$termForm.Controls.Add($c)
}
Move-ToTerminal $termLog 8 8 600 250
Move-ToTerminal $txtSend 8 266 420 20
Move-ToTerminal $btnSend 434 265 80 23
Move-ToTerminal $btnClear 520 265 88 23
Move-ToTerminal $chkDtr 8 295 55 20
Move-ToTerminal $chkRts 70 295 55 20

$status = New-Object Windows.Forms.StatusStrip
$stComm = New-Object Windows.Forms.ToolStripStatusLabel; $stComm.Text = 'Communication OFF'; $stComm.ToolTipText = 'Serial port open/closed state'
[void]$status.Items.Add($stComm)
$stInfo = New-Object Windows.Forms.ToolStripStatusLabel; $stInfo.Text = 'idle'; $stInfo.ToolTipText = 'Last action log message'
[void]$status.Items.Add($stInfo)
$stState = New-Object Windows.Forms.ToolStripStatusLabel; $stState.Text = 'State: ...'; $stState.ToolTipText = 'Current hex file, device, and COM port'
[void]$status.Items.Add($stState)
$stNext = New-Object Windows.Forms.ToolStripStatusLabel; $stNext.Text = 'Next: ...'; $stNext.ToolTipText = 'Suggested next step'
[void]$status.Items.Add($stNext)
$form.Controls.Add($status)

function Log($s) { $termLog.AppendText($s + "`r`n"); $stInfo.Text = $s }

# Single place that refreshes the State + Next strip fields. State always
# recomputed (hex leaf + age | device | port); Next only overwritten when a
# $Hint is passed, so timer/focus refreshes never clobber the last suggestion.
function Update-StateNext([string]$Hint = '') {
    try {
        $hexPath = ''
        try { $hexPath = ("$($cmbHex.Text)").Trim('" ').Trim() } catch {}
        $hexLeaf = 'no hex'
        $age = ''
        try { $age = ("$($lblHexAge.Text)").Trim() } catch {}
        if ($hexPath -ne '') {
            try { $hexLeaf = Split-Path $hexPath -Leaf } catch { $hexLeaf = $hexPath }
            if ($age -ne '') { $hexLeaf = ($hexLeaf + ' (' + $age + ')') }
        }
        $dev = ''
        try { $dev = ("$($txtDev.Text)").Trim() } catch {}
        if ($dev -eq '') { $dev = 'no device' }
        $prt = ''
        try { $prt = ("$($cmbPort.Text)").Trim() } catch {}
        if ($prt -eq '') { $prt = 'no port' }
        elseif ([bool]$script:PortAuto) { $prt += ' (auto)' }
        $stState.Text = ('State: ' + $hexLeaf + ' | ' + $dev + ' | ' + $prt)
        try {
            if ($hexPath -ne '' -and (Test-Path $hexPath)) { $stState.ToolTipText = ([IO.Path]::GetFullPath($hexPath)) }
            else { $stState.ToolTipText = $hexPath }
        } catch {}
        try {
            if ($hexPath -ne '' -and (Test-Path $hexPath)) { $tip.SetToolTip($cmbHex, ([IO.Path]::GetFullPath($hexPath))) } catch {}
            $tip.SetToolTip($txtDev, ('device: ' + $dev + ' (batchisp -device name)'))
        } catch {}
        if ($Hint -ne $null -and $Hint -ne '') { $stNext.Text = ('Next: ' + $Hint) }
        elseif ($stNext.Text -eq '' -or $stNext.Text -eq 'Next: ...') {
            $connected = $false
            try { $connected = ($script:port -ne $null -and $script:port.IsOpen) } catch {}
            if ($connected) { $stNext.Text = 'Next: Send !!! via Firmware Reset (Ctrl+R) or watch output' }
            else { $stNext.Text = 'Next: Connect serial (Ctrl+T)' }
        }
    } catch {}
}

function Update-HexInfo {
    $h = ("$($cmbHex.Text)").Trim('" ').Trim()
    $variant = 'hex'
    if ($h -match '[\\/]Debug[\\/]') { $variant = 'Debug' } elseif ($h -match '[\\/]Release[\\/]') { $variant = 'Release' }
    if ($h -ne '' -and (Test-Path $h)) {
        try {
            $min = [uint32]::MaxValue; $max = 0; $n = 0
            foreach ($line in (Get-Content $h)) {
                if ($line.StartsWith(':')) {
                    $cnt = [Convert]::ToUInt32($line.Substring(1, 2), 16)
                    $addr = [Convert]::ToUInt32($line.Substring(3, 4), 16)
                    $typ = $line.Substring(7, 2)
                    if ($typ -eq '00') { $n += $cnt; if ($addr -lt $min) { $min = $addr }; if ($addr + $cnt -gt $max) { $max = $addr + $cnt } }
                }
            }
            if ($max -eq 0) { $min = 0 }
            $lblSize.Text = ('Size  {0:N1} KB   Range 0x{1:X} - 0x{2:X}' -f ($n / 1KB), $min, $max)
            $lblSum.Text = ('{0:N0} data bytes [{1}]  |  {2}' -f $n, $variant, (Split-Path $h -Leaf))
        } catch { $lblSum.Text = ('[{0}] {1}' -f $variant, (Split-Path $h -Leaf)) }
        try { $lblHexAge.Text = Get-HexAgeText ((Get-Item $h).LastWriteTime) } catch { $lblHexAge.Text = 'age unknown' }
        try { $tip.SetToolTip($cmbHex, ([IO.Path]::GetFullPath($h))) } catch { $tip.SetToolTip($cmbHex, $h) }
        # Update Buffer menu items
        try {
            $script:bufSizeItem.Text = ('Hex size: {0:N1} KB   Range 0x{1:X} - 0x{2:X}' -f ($n / 1KB), $min, $max)
            $script:bufSizeItem.Enabled = $true
            $script:bufVariantItem.Text = ('Variant: {0}' -f $variant)
            $script:bufVariantItem.Enabled = $true
        } catch {}
    } else {
        $lblSize.Text = 'Size  64 KB   Range 0x0 - 0x0'; $lblSum.Text = 'Checksum 0xFF'
        if ($h -eq '') { $lblHexAge.Text = 'no hex selected' } else { $lblHexAge.Text = 'file not found' }
        # Disable Buffer menu items
        try {
            $script:bufSizeItem.Text = 'Hex size: (no hex)'
            $script:bufSizeItem.Enabled = $false
            $script:bufVariantItem.Text = 'Variant: (no hex)'
            $script:bufVariantItem.Enabled = $false
        } catch {}
    }
    try {
        $script:NewerHexPath = $null
        $lblNewer.Visible = $false
        $newest = Find-NewestHex $CodeBlocksRoot
        if ($newest -ne $null -and $newest -ne '' -and $h -ne '' -and (Test-Path $h) -and (Test-Path $newest)) {
            if (("$newest").ToUpperInvariant() -ne ("$h").ToUpperInvariant()) {
                $selTime = (Get-Item $h).LastWriteTime
                $newTime = (Get-Item $newest).LastWriteTime
                if ($newTime -gt $selTime) {
                    # Auto-reload newest hex ON = switch silently and say so.
                    # OFF = show the blue notice and wait, which is what FLIP
                    # does (it never looks at your build directory at all).
                    if (Get-AutoFlow 'Auto-reload newest hex') {
                        $script:NewerHexPath = $newest
                        Add-RecentHex $newest
                        Update-StateNext 'Press Run (F5)'
                        Log ('auto-reloaded newer build: ' + $newest)
                    } else {
                        $script:NewerHexPath = $newest
                        $lblNewer.Text = ('NEWER BUILD available (' + $newTime.ToString('HH:mm') + ') - click to switch')
                        $lblNewer.Visible = $true
                    }
                }
            }
        }
    } catch {}
    Update-StateNext
}

function Refresh-Ports {
    $ports = @(Get-ComPortsFiltered)
    $sel = $cmbPort.Text
    $cmbPort.Items.Clear()
    if ($ports.Count -gt 0) { [void]$cmbPort.Items.AddRange([string[]]$ports) }
    # Auto-pick port off = whatever is already typed, or empty, wins. FLIP does
    # not go picking ports for you either.
    if (-not (Get-AutoFlow 'Auto-pick COM port')) {
        if ($sel -ne '') { $cmbPort.Text = $sel; $script:PortAuto = $false }
        return
    }
    if ($sel -ne '' -and ($ports -contains $sel)) { $cmbPort.Text = $sel; $script:PortAuto = $false }
    elseif ($cfg.Port -ne '' -and ($ports -contains $cfg.Port)) { $cmbPort.Text = $cfg.Port; $script:PortAuto = $false }
    elseif ($ports.Count -gt 0) { $cmbPort.Text = $ports[0]; $script:PortAuto = $true }
    else { $script:PortAuto = $false }
}

# ---------- serial ----------
$port = $null
function Close-Serial {
    try { if ($pollTimer -ne $null) { $pollTimer.Stop() } } catch {}
    if ($port -ne $null) { try { $port.Close() } catch {}; $script:port = $null }
    $stComm.Text = 'Communication OFF'
    Update-SerialButtons
    Update-TermTitle
    Update-StateNext 'Connect serial (Ctrl+T)'
}
function Open-Serial {
    Close-Serial
    if ($cmbPort.Text -eq '') { Log 'no COM port selected'; return }
    try {
        $p = New-Object System.IO.Ports.SerialPort($cmbPort.Text, [int]$txtMonBaud.Text, 'None', 8, 'One')
        $p.DtrEnable = $chkDtr.Checked; $p.RtsEnable = $chkRts.Checked
        $p.Open(); $script:port = $p
        $pollTimer.Start()
        $stComm.Text = 'Communication ON'
        Update-SerialButtons
        Log ("serial open " + $cmbPort.Text + ' @ ' + $txtMonBaud.Text + ' 8N1')
        Show-Terminal
        Update-StateNext 'Send !!! via Firmware Reset (Ctrl+R) or watch output'
    } catch { Log ('serial open FAILED: ' + $_.Exception.Message) }
}
function Toggle-Serial {
    if ($port -ne $null -and $port.IsOpen) { Close-Serial; Log 'serial closed' } else { Open-Serial }
}
# ---------- progress popup for staged flash ----------
$progForm = New-Object Windows.Forms.Form
$progForm.Text = 'FLIPpen Hel - Flash Progress'
$progForm.Size = New-Object Drawing.Size(480, 320)
$progForm.StartPosition = 'CenterParent'
$progForm.FormBorderStyle = 'FixedDialog'
$progForm.MaximizeBox = $false
$progForm.MinimizeBox = $false
$progForm.ShowInTaskbar = $false
[void]$form.AddOwnedForm($progForm)
$progOverall = New-Object Windows.Forms.ProgressBar; $progOverall.Location = New-Object Drawing.Point(12, 12); $progOverall.Size = New-Object Drawing.Size(440, 24); $progForm.Controls.Add($progOverall)
$tip.SetToolTip($progOverall, 'Overall progress across all ISP stages')
$lblStage = New-Object Windows.Forms.Label; $lblStage.Text = 'Preparing...'; $lblStage.Location = New-Object Drawing.Point(12, 44); $lblStage.Size = New-Object Drawing.Size(440, 20); $progForm.Controls.Add($lblStage)
$tip.SetToolTip($lblStage, 'Current ISP stage and its position in the sequence')
$progStage = New-Object Windows.Forms.ProgressBar; $progStage.Location = New-Object Drawing.Point(12, 68); $progStage.Size = New-Object Drawing.Size(440, 24); $progForm.Controls.Add($progStage)
$tip.SetToolTip($progStage, 'Progress of the current stage')
$lblDetail = New-Object Windows.Forms.Label; $lblDetail.Text = ''; $lblDetail.Location = New-Object Drawing.Point(12, 98); $lblDetail.Size = New-Object Drawing.Size(440, 16); $progForm.Controls.Add($lblDetail)
$tip.SetToolTip($lblDetail, 'Detail line - COM port and retry information')
$txtProgLog = New-Object Windows.Forms.TextBox; $txtProgLog.Multiline = $true; $txtProgLog.ScrollBars = 'Vertical'; $txtProgLog.ReadOnly = $true; $txtProgLog.Font = New-Object Drawing.Font('Consolas', 8); $txtProgLog.Location = New-Object Drawing.Point(12, 120); $txtProgLog.Size = New-Object Drawing.Size(440, 130); $progForm.Controls.Add($txtProgLog)
$tip.SetToolTip($txtProgLog, 'Batchisp output log for each stage')
$btnProgCancel = New-Object Windows.Forms.Button; $btnProgCancel.Text = 'Cancel'; $btnProgCancel.Location = New-Object Drawing.Point(360, 260); $btnProgCancel.Size = New-Object Drawing.Size(90, 28); $progForm.Controls.Add($btnProgCancel)
$tip.SetToolTip($btnProgCancel, 'Cancel - stop after the current batchisp run finishes')
$script:progCancel = $false
$btnProgCancel.Add_Click({ $script:progCancel = $true; $btnProgCancel.Enabled = $false; $lblDetail.Text = 'Cancelling...' })

function Show-ProgPopup { $script:progCancel = $false; $progOverall.Value = 0; $progStage.Value = 0; $txtProgLog.Clear(); $progForm.Show($form) }
function Hide-ProgPopup { $progForm.Hide() }
function Log-Prog($s) { $txtProgLog.AppendText($s + "`r`n"); $txtProgLog.SelectionStart = $txtProgLog.Text.Length; $txtProgLog.ScrollToCaret(); Log $s }

# Staged flash: runs Erase / BlankCheck / Program / Verify / Start as separate batchisp calls
function Run-StagedFlash {
    $hex = ("$($cmbHex.Text)").Trim('" ').Trim()
    $snapDev = ("$($txtDev.Text)").Trim()
    $snapPort = ("$($cmbPort.Text)").Trim()
    $snapIsp = ("$($txtIspBaud.Text)").Trim()
    if ($hex -eq '' -or -not (Test-Path $hex)) { Log 'pick a valid .hex file first (Ctrl+O)'; return }
    if (-not (Test-Path $BatchIsp)) { Log ('batchisp not found: ' + $BatchIsp); return }
    $wasOpen = ($port -ne $null -and $port.IsOpen)
    Close-Serial; Start-Sleep -Milliseconds 200
    $auto = ''; if ($chkAuto.Checked) { $auto = '-autoisp 1 0' }

    # Build port retry list. Auto-retry off = try only the chosen port, exactly
    # like FLIP, which fails once and stops.
    $allPorts = @(Get-ComPortsFiltered)
    $retryPorts = @()
    if ($snapPort -ne '' -and ($allPorts -contains $snapPort)) { $retryPorts += $snapPort }
    if (Get-AutoFlow 'Auto-retry other ports') {
        foreach ($p in $allPorts) { if ($p -ne $snapPort) { $retryPorts += $p } }
    } else { Log 'auto-retry off - only trying ' + $snapPort }

    # Build stages from checkboxes. Start Application is a checkbox here, so a
    # FLIP refusenik can flash and leave the chip halted.
    $stages = @()
    if ($chkOps['Erase'].Checked) { $stages += @{ Name='Erase'; Op='MEMORY FLASH ERASE F' } }
    if ($chkOps['Blank Check'].Checked) { $stages += @{ Name='Blank Check'; Op='MEMORY FLASH BLANKCHECK' } }
    $stages += @{ Name='Program'; Op=('MEMORY FLASH LOADBUFFER "{0}" PROGRAM' -f $hex) }
    if ($chkOps['Verify'].Checked) { $stages += @{ Name='Verify'; Op='MEMORY FLASH VERIFY' } }
    if ($chkOps['Start Application'].Checked) { $stages += @{ Name='Start Application'; Op='MEMORY FLASH START RESET 0' } }

    $flashOk = $false
    $btnRun.Enabled = $false; $btnStartApp.Enabled = $false
    Show-ProgPopup
    $progOverall.Maximum = $stages.Count
    $progStage.Maximum = 100

    foreach ($tryPort in $retryPorts) {
        $portOk = $true
        $stageIdx = 0
        foreach ($st in $stages) {
            if ($script:progCancel) { $portOk = $false; break }
            $stageIdx++
            $progOverall.Value = $stageIdx - 1
            $progStage.Value = 0
            $lblStage.Text = "Stage $stageIdx / $($stages.Count): $($st.Name)"
            $lblDetail.Text = "Port: $tryPort"
            Log-Prog ("[$($st.Name)] $($st.Op)")
            $progStage.Value = 30
            $args = "-device $snapDev -hardware RS232 -port $tryPort -baudrate $snapIsp $auto -operation $($st.Op)"
            $stOk = $true
            try {
                $p = Start-Process -FilePath $BatchIsp -ArgumentList $args -NoNewWindow -Wait -PassThru
                $progStage.Value = 100
                if ($p.ExitCode -ne 0) { Log-Prog ("FAIL exit $($p.ExitCode) on $tryPort"); $stOk = $false }
                else { Log-Prog "OK" }
            } catch { Log-Prog ("EXCEPTION: $($_.Exception.Message)"); $stOk = $false }
            # Flip-style feedback: the stage checkbox turns green on pass, red on fail
            try { Set-OpResult $st.Name $stOk } catch {}
            if (-not $stOk) { $portOk = $false; break }
        }
        if ($portOk -and -not $script:progCancel) {
            $flashOk = $true
            $snapPort = $tryPort; $cmbPort.Text = $tryPort
            $script:PortAuto = ($tryPort -ne $retryPorts[0])
            Log-Prog 'ALL STAGES OK'
            break
        }
        if ($script:progCancel) { Log-Prog 'CANCELLED'; break }
        Log-Prog ("Port $tryPort failed -- trying next")
    }
    Hide-ProgPopup
    $btnRun.Enabled = $true; $btnStartApp.Enabled = $true
    $cfg.HexFile = $hex; $cfg.Device = $snapDev; $cfg.Port = $snapPort
    $cfg.IspBaud = $snapIsp; $cfg.MonBaud = $txtMonBaud.Text; $cfg.AutoIsp = $chkAuto.Checked
    Save-Config $cfg
    if ($flashOk) { Add-RecentDevice $txtDev.Text; Update-DeviceMenu; Add-RecentHex $hex; Update-HexInfo; Update-StateNext 'Open Terminal (Ctrl+T)' } else { Update-StateNext 'Check device/port/ISP mode, then Press Run (F5)' }
    if ($wasOpen) { Open-Serial }
}

# Task 19: Serial Auto mode. cfg.SerialAuto (default ON) picks the label:
# ON = fixed 'Serial: Auto' (click connects if needed + shows terminal, RX
# auto-opens, disconnect only via the Terminal window); OFF = manual
# 'Serial: Connect'/'Serial: Disconnect' toggle, never auto-pops.
function Update-SerialButtons {
    $open = ($port -ne $null -and $port.IsOpen)
    if ([bool]$cfg.SerialAuto) {
        $btnConnect.Text = 'Serial: Auto'; $tbConnect.Text = 'Serial: Auto'
        $tip.SetToolTip($btnConnect, 'Serial: Auto - click connects (if needed) + opens terminal (Ctrl+T). RX data auto-opens the terminal. Disconnect via the Terminal window')
        $tbConnect.ToolTipText = 'Serial: Auto - click connects (if needed) + opens terminal (Ctrl+T). RX data auto-opens the terminal. Disconnect via the Terminal window'
    } elseif ($open) {
        $btnConnect.Text = 'Serial: Disconnect'; $tbConnect.Text = 'Serial: Disconnect'
        $tip.SetToolTip($btnConnect, 'Serial: Disconnect - drop the serial port (Ctrl+T)')
        $tbConnect.ToolTipText = 'Serial: Disconnect - drop the serial port (Ctrl+T)'
    } else {
        $btnConnect.Text = 'Serial: Connect'; $tbConnect.Text = 'Serial: Connect'
        $tip.SetToolTip($btnConnect, 'Serial: Connect - open serial + show terminal (Ctrl+T)')
        $tbConnect.ToolTipText = 'Serial: Connect - open serial + show terminal (Ctrl+T)'
    }
}
# Single handler for the box + toolbar Serial buttons (and Ctrl+T):
# connect (if needed) + open the terminal in both modes. Auto ON never
# disconnects here (button stays 'Serial: Auto'); Auto OFF keeps the
# manual Connect/Disconnect toggle.
function Invoke-SerialButton {
    if ($port -ne $null -and $port.IsOpen) {
        if ([bool]$cfg.SerialAuto) { Show-Terminal } else { Toggle-Serial }
    } else { Open-Serial }
}

# Two-field parameter prompt used by range-based operations (Erase Blocks etc.).
function Show-Prompt($title, $label1, $val1, $label2, $val2, $onOk) {
    $f = New-Object Windows.Forms.Form
    $f.Text = $title; $f.Size = New-Object Drawing.Size(360, 180)
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    [void]$form.AddOwnedForm($f)
    $l1 = New-Object Windows.Forms.Label; $l1.Text = $label1; $l1.Location = New-Object Drawing.Point(12, 14); $l1.Size = New-Object Drawing.Size(180, 20); $f.Controls.Add($l1)
    $tip.SetToolTip($l1, ($label1 + ' - hex value without the 0x prefix'))
    $t1 = New-Object Windows.Forms.TextBox; $t1.Text = $val1; $t1.Location = New-Object Drawing.Point(200, 12); $t1.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($t1)
    $tip.SetToolTip($t1, ('Hex value, no 0x prefix - ' + $label1))
    $l2 = New-Object Windows.Forms.Label; $l2.Text = $label2; $l2.Location = New-Object Drawing.Point(12, 48); $l2.Size = New-Object Drawing.Size(180, 20); $f.Controls.Add($l2)
    $tip.SetToolTip($l2, ($label2 + ' - hex value without the 0x prefix'))
    $t2 = New-Object Windows.Forms.TextBox; $t2.Text = $val2; $t2.Location = New-Object Drawing.Point(200, 46); $t2.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($t2)
    $tip.SetToolTip($t2, ('Hex value, no 0x prefix - ' + $label2))
    $bOk = New-Object Windows.Forms.Button; $bOk.Text = 'OK'; $bOk.Location = New-Object Drawing.Point(120, 90); $bOk.Size = New-Object Drawing.Size(90, 26); $f.Controls.Add($bOk)
    $tip.SetToolTip($bOk, 'OK - run this operation with the values you typed')
    $bCn = New-Object Windows.Forms.Button; $bCn.Text = 'Cancel'; $bCn.Location = New-Object Drawing.Point(220, 90); $bCn.Size = New-Object Drawing.Size(90, 26); $f.Controls.Add($bCn)
    $tip.SetToolTip($bCn, 'Cancel - close without running anything')
    $bOk.Add_Click(({ & $onOk ("$($t1.Text)").Trim() ("$($t2.Text)").Trim(); $f.Close() }).GetNewClosure())
    $bCn.Add_Click(({ $f.Close() }).GetNewClosure())
    $f.Add_FormClosing({ if ($form.Visible) { $_.Cancel = $true; $f.Hide() } })
    $f.Show($form)
}

# ---------- Flip Device-menu operations (batchisp single-operation runs) ----------
# Mirrors the documented Flip Device menu: Erase, Blank Check, Read, Verify,
# Check Communications, Write/Read Special Bits. Each reuses the exact batchisp
# argument construction as Run (same flags, two-arg -autoisp), auto-retries the
# next non-Bluetooth port on failure, and reports per-op pass/fail in the log.
function Get-BatchArgs($port, $op) {
    $dev = ("$($txtDev.Text)").Trim()
    $isp = ("$($txtIspBaud.Text)").Trim()
    $auto = ''; if ($chkAuto.Checked) { $auto = '-autoisp 1 0' }
    $mem = 'FLASH'
    try { $m1 = ("$($chkTarget.Text)").Trim(); if ($m1 -ne '') { $mem = $m1 } } catch {}
    return ("-device {0} -hardware RS232 -port {1} -baudrate {2} {3} -operation MEMORY {4} {5}" -f $dev, $port, $isp, $auto, $mem, $op)
}
# Runs one batchisp operation across the retry port list. Returns the port that
# worked (empty on failure). Logs every attempt loudly.
function Invoke-OpOnPorts($op, $label) {
    $all = @(Get-ComPortsFiltered)
    $sel = ("$($cmbPort.Text)").Trim()
    $list = @()
    if ($sel -ne '' -and ($all -contains $sel)) { $list += $sel }
    if (Get-AutoFlow 'Auto-retry other ports') {
        foreach ($p in $all) { if ($p -ne $sel) { $list += $p } }
    } else { Log 'auto-retry off - only trying ' + $sel }
    if ($list.Count -eq 0) { Log ('no COM ports available for ' + $label); return '' }
    foreach ($tryPort in $list) {
        Log ("$label on ${tryPort}: batchisp.exe " + (Get-BatchArgs $tryPort $op))
        try {
            $p = Start-Process -FilePath $BatchIsp -ArgumentList (Get-BatchArgs $tryPort $op) -NoNewWindow -Wait -PassThru
        } catch { Log ("$label launch failed on ${tryPort}: " + $_.Exception.Message); continue }
        if ($p.ExitCode -eq 0) {
            Log ("$label OK on ${tryPort}")
            $cmbPort.Text = $tryPort
            return $tryPort
        }
        Log ("$label FAIL exit " + $p.ExitCode + " on ${tryPort} -- trying next port")
    }
    Log ("$label failed on all " + $list.Count + " port(s)")
    return ''
}
function Device-Erase($blocks) {
    Close-Serial; Start-Sleep -Milliseconds 150
    $op = 'ERASE F'
    $ok = (Invoke-OpOnPorts $op 'Erase') -ne ''
    Set-OpResult 'Erase' $ok
    Update-StateNext (if ($ok) { 'Open Terminal (Ctrl+T)' } else { 'Check device/port/ISP mode, then try Erase' })
}
function Device-BlankCheck {
    Close-Serial; Start-Sleep -Milliseconds 150
    $ok = (Invoke-OpOnPorts 'BLANKCHECK' 'Blank Check') -ne ''
    Set-OpResult 'Blank Check' $ok
    Update-StateNext (if ($ok) { 'Flash is blank - press Run (F5)' } else { 'Erase first, then recheck' })
}
function Device-Verify {
    Close-Serial; Start-Sleep -Milliseconds 150
    $ok = (Invoke-OpOnPorts 'VERIFY' 'Verify') -ne ''
    Set-OpResult 'Verify' $ok
    Update-StateNext (if ($ok) { 'Program verified OK' } else { 'Reprogram, then Verify again' })
}
function Device-Read {
    Close-Serial; Start-Sleep -Milliseconds 150
    $ok = (Invoke-OpOnPorts 'READ' 'Read') -ne ''
    Log 'read into buffer - buffer info below reflects the hex file, not the readback'
    Update-HexInfo
    Update-StateNext (if ($ok) { 'Read done' } else { 'Read failed - check wiring' })
}
function Device-CommCheck {
    Close-Serial; Start-Sleep -Milliseconds 150
    $ok = (Invoke-OpOnPorts 'BLANKCHECK' 'Communications check') -ne ''
    if ($ok) { Log 'communications OK - device answers on ' + $cmbPort.Text } else { Log 'communications FAILED - check port, ISP mode and cable' }
    Update-StateNext (if ($ok) { 'Device answers - press Run (F5)' } else { 'No answer - check port/ISP wiring' })
}
# Write/Read special bits dialog (BLJB active-low, X2, BSB/SBV, Security Level)
function Show-SpecialBits {
    $f = New-Object Windows.Forms.Form
    $f.Text = 'Special Bits and Bytes'; $f.Size = New-Object Drawing.Size(340, 250)
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    [void]$form.AddOwnedForm($f)
    $l1 = New-Object Windows.Forms.Label; $l1.Text = 'BLJB (active low)'; $l1.Location = New-Object Drawing.Point(12, 14); $l1.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($l1)
    $tip.SetToolTip($l1, 'BLJB - Boot Loader Jump Bit. Active LOW: checking the box enables it')
    $cBljb = New-Object Windows.Forms.CheckBox; $cBljb.Location = New-Object Drawing.Point(150, 12); $cBljb.Size = New-Object Drawing.Size(60, 20); $f.Controls.Add($cBljb)
    $tip.SetToolTip($cBljb, 'BLJB - Boot Loader Jump Bit, ACTIVE LOW. Checking the box ENABLES the bit (drives it low); a full chip erase resets it')
    $l2 = New-Object Windows.Forms.Label; $l2.Text = 'X2'; $l2.Location = New-Object Drawing.Point(12, 44); $l2.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($l2)
    $tip.SetToolTip($l2, 'X2 - clock mode bit of the hardware byte')
    $cX2 = New-Object Windows.Forms.CheckBox; $cX2.Location = New-Object Drawing.Point(150, 42); $cX2.Size = New-Object Drawing.Size(60, 20); $f.Controls.Add($cX2)
    $tip.SetToolTip($cX2, 'X2 clock mode bit for the hardware byte')
    $l3 = New-Object Windows.Forms.Label; $l3.Text = 'BSB / SBV'; $l3.Location = New-Object Drawing.Point(12, 74); $l3.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($l3)
    $tip.SetToolTip($l3, 'BSB / SBV - Boot Status Byte and Software Boot Vector')
    $tBsb = New-Object Windows.Forms.TextBox; $tBsb.Location = New-Object Drawing.Point(150, 72); $tBsb.Size = New-Object Drawing.Size(70, 20); $f.Controls.Add($tBsb)
    $tip.SetToolTip($tBsb, 'BSB / SBV - Boot Status Byte / Software Boot Vector. Program sets BSB to 0x00; type 2 hex digits (no 0x) to write')
    $l4 = New-Object Windows.Forms.Label; $l4.Text = 'Security Level'; $l4.Location = New-Object Drawing.Point(12, 104); $l4.Size = New-Object Drawing.Size(130, 20); $f.Controls.Add($l4)
    $tip.SetToolTip($l4, 'Security Level - 0 unprotected, 1 write protect, 2 read+write protect')
    $cbSec = New-Object Windows.Forms.ComboBox; $cbSec.DropDownStyle = 'DropDownList'
    $cbSec.Items.AddRange([string[]]@('Level 0', 'Level 1', 'Level 2')); $cbSec.SelectedIndex = 0
    $cbSec.Location = New-Object Drawing.Point(150, 102); $cbSec.Size = New-Object Drawing.Size(100, 20); $f.Controls.Add($cbSec)
    $tip.SetToolTip($cbSec, 'Security Level - Level 0 unprotected, Level 1 write protect, Level 2 read+write protect')
    $bW = New-Object Windows.Forms.Button; $bW.Text = 'Write'; $bW.Location = New-Object Drawing.Point(40, 150); $bW.Size = New-Object Drawing.Size(90, 26); $f.Controls.Add($bW)
    $tip.SetToolTip($bW, 'Write - send BLJB, X2, BSB/SBV and Security Level to the device')
    $bR = New-Object Windows.Forms.Button; $bR.Text = 'Read'; $bR.Location = New-Object Drawing.Point(140, 150); $bR.Size = New-Object Drawing.Size(90, 26); $f.Controls.Add($bR)
    $tip.SetToolTip($bR, 'Read - read the current special bits and bytes from the device (values go to the log)')
    $bW.Add_Click(({
        $hex = ("$($tBsb.Text)").Trim()
        if ($hex -ne '' -and $hex -notmatch '^[0-9A-Fa-f]{1,2}$') { Log 'special bits: BSB/SBV must be 2 hex digits'; return }
        $parts = @()
        if ($cBljb.Checked) { $parts += 'BLJB' }
        if ($cX2.Checked) { $parts += 'X2' }
        if ($hex -ne '') { $parts += ('BSB ' + $hex) }
        $lvl = ("$($cbSec.Text)").Trim() -replace 'Level ', ''
        $parts += ('SECURITY ' + $lvl)
        $ok = (Invoke-OpOnPorts ($parts -join ' ') 'Write special bits') -ne ''
        Update-StateNext (if ($ok) { 'Special bits written' } else { 'Special bits write failed' })
    }).GetNewClosure())
    $bR.Add_Click(({
        $ok = (Invoke-OpOnPorts 'READ' 'Read special bits') -ne ''
        Update-StateNext (if ($ok) { 'Special bits read into log' } else { 'Special bits read failed' })
    }).GetNewClosure())
    $bC = New-Object Windows.Forms.Button; $bC.Text = 'Close'; $bC.Location = New-Object Drawing.Point(240, 150); $bC.Size = New-Object Drawing.Size(80, 26); $f.Controls.Add($bC)
    $tip.SetToolTip($bC, 'Close - hide this window (your entries are kept while the app runs)')
    $bC.Add_Click(({ $f.Close() }).GetNewClosure())
    $f.Add_FormClosing({ if ($form.Visible) { $_.Cancel = $true; $f.Hide() } })
    $f.Show($form)
}

function Run-BatchIsp($extraOp) {
    # Task 18: snapshot live control values up front --- an open modeless
    # Settings can never desync a flash started from the main window.
    $hex = ("$($cmbHex.Text)").Trim('" ').Trim()
    $snapDev = ("$($txtDev.Text)").Trim()
    $snapPort = ("$($cmbPort.Text)").Trim()
    $snapIsp = ("$($txtIspBaud.Text)").Trim()
    if ($hex -eq '' -or -not (Test-Path $hex)) { Log 'pick a valid .hex file first (Ctrl+O)'; return }
    if (-not (Test-Path $BatchIsp)) { Log ('batchisp not found: ' + $BatchIsp); return }
    $wasOpen = ($port -ne $null -and $port.IsOpen)
    Close-Serial; Start-Sleep -Milliseconds 200
    $auto = ''; if ($chkAuto.Checked) { $auto = '-autoisp 1 0' }

    # Build port retry list: start with selected port, then all other non-BT ports
    $allPorts = @(Get-ComPortsFiltered)
    $retryPorts = @()
    if ($snapPort -ne '' -and ($allPorts -contains $snapPort)) { $retryPorts += $snapPort }
    foreach ($p in $allPorts) { if ($p -ne $snapPort) { $retryPorts += $p } }

    $flashOk = $false
    $btnRun.Enabled = $false; $btnStartApp.Enabled = $false
    foreach ($tryPort in $retryPorts) {
        $args = "-device $snapDev -hardware RS232 -port $tryPort -baudrate $snapIsp $auto -operation $extraOp"
        Log ("running on ${tryPort}: batchisp.exe " + $args)
        try {
            $p = Start-Process -FilePath $BatchIsp -ArgumentList $args -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                $flashOk = $true
                $snapPort = $tryPort  # remember working port
                $cmbPort.Text = $tryPort
                $script:PortAuto = ($tryPort -ne $retryPorts[0])  # auto if not first choice
                Log 'OK -- done'
                break
            } else {
                Log ("batchisp exit " + $p.ExitCode + " on $tryPort -- trying next port")
            }
        } catch { Log ("failed on ${tryPort}: " + $_.Exception.Message) }
    }
    $btnRun.Enabled = $true; $btnStartApp.Enabled = $true
    $cfg.HexFile = $hex; $cfg.Device = $snapDev; $cfg.Port = $snapPort
    $cfg.IspBaud = $snapIsp; $cfg.MonBaud = $txtMonBaud.Text; $cfg.AutoIsp = $chkAuto.Checked
    Save-Config $cfg
    if ($flashOk) { Add-RecentDevice $txtDev.Text; Update-DeviceMenu; Add-RecentHex $hex; Update-HexInfo; Update-StateNext 'Open Terminal (Ctrl+T)' } else { Update-StateNext 'Check device/port/ISP mode, then Press Run (F5)' }
    if ($wasOpen) { Open-Serial }
}

# ---------- events ----------
# Root cause: ShowDialog() with no owner while another dialog may
# own focus puts the picker behind / blocks it, so it never appears. Modal to
# the main form fixes z-order in all cases. InitialDirectory guarded so a
# bare filename cannot throw before the dialog opens.
function Invoke-BrowseHex {
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Filter = 'HEX files (*.hex;*.ihx)|*.hex;*.ihx|All files (*.*)|*.*'
    try {
        $cur = ("$($cmbHex.Text)").Trim('" ').Trim()
        if ($cur -ne '') {
            $dir = Split-Path $cur -Parent -ErrorAction Stop
            if ($dir -ne '' -and (Test-Path $dir)) { $d.InitialDirectory = $dir }
        }
    } catch {}
    if ($d.ShowDialog($form) -eq 'OK') { $cmbHex.Text = $d.FileName; Add-RecentHex $d.FileName; Update-HexInfo; Update-StateNext 'Press Run (F5)' }
}
function Invoke-NewestHex {
    $n = Find-NewestHex $CodeBlocksRoot
    if ($n) { $cmbHex.Text = $n; Add-RecentHex $n; Update-HexInfo; Update-StateNext 'Press Run (F5)'; Log ('newest hex: ' + $n) } else { Log 'no .hex found' }
}
# File > Save Buffer Contents - copies the loaded Intel HEX to a new file
# (Flip's equivalent writes the buffer out as a .hex).
function Save-BufferContents {
    $src = ("$($cmbHex.Text)").Trim('" ').Trim()
    if ($src -eq '' -or -not (Test-Path $src)) { Log 'pick a valid .hex file first (Ctrl+O)'; return }
    $d = New-Object Windows.Forms.SaveFileDialog
    $d.Filter = 'HEX files (*.hex)|*.hex|All files (*.*)|*.*'
    $d.FileName = ([IO.Path]::GetFileNameWithoutExtension($src) + '_copy.hex')
    try { $dir = Split-Path $src -Parent -ErrorAction Stop; if ($dir -ne '' -and (Test-Path $dir)) { $d.InitialDirectory = $dir } } catch {}
    if ($d.ShowDialog($form) -eq 'OK') {
        try { Copy-Item -LiteralPath $src -Destination $d.FileName -Force; Log ('buffer saved to ' + $d.FileName); Update-StateNext 'Press Run (F5)' }
        catch { Log ('save buffer FAILED: ' + $_.Exception.Message) }
    }
}
$btnBrowse.Add_Click({ Invoke-BrowseHex })
$btnNewest.Add_Click({ Invoke-NewestHex })
$btnRun.Add_Click({ Run-StagedFlash })
$btnStartApp.Add_Click({ Run-BatchIsp 'START RESET 0' })
$btnConnect.Add_Click({ Invoke-SerialButton })
$btnClear.Add_Click({ $termLog.Clear() })
$btnSend.Add_Click({
    if ($port -eq $null -or -not $port.IsOpen) { Log 'not connected (Ctrl+T)'; return }
    try { $port.Write($txtSend.Text + "`r`n"); $txtSend.Clear() } catch { Log ('send failed: ' + $_.Exception.Message) }
})
$txtSend.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnSend.PerformClick(); $_.SuppressKeyPress = $true } })
$btnFwReset.Add_Click({
    if ($port -eq $null -or -not $port.IsOpen) { Log 'open serial first (Ctrl+T), then Firmware Reset'; Update-StateNext 'Connect serial (Ctrl+T)'; return }
    try { $port.Write($ResetMagic + "`r`n"); Log 'sent !!!RESET!!! (app reboots if snippet is in firmware)'; Update-StateNext 'watch output' }
    catch { Log ('reset failed: ' + $_.Exception.Message); Update-StateNext 'Check connection, then Send !!! via Firmware Reset (Ctrl+R)' }
})
$chkDtr.Add_CheckedChanged({ if ($port -ne $null -and $port.IsOpen) { $port.DtrEnable = $chkDtr.Checked } })
$chkRts.Add_CheckedChanged({ if ($port -ne $null -and $port.IsOpen) { $port.RtsEnable = $chkRts.Checked } })
$btnPulse.Add_Click({
    if ($port -eq $null -or -not $port.IsOpen) { Log 'open serial first to Pulse DTR'; return }
    try { $port.DtrEnable = $true; Start-Sleep -Milliseconds 120; $port.DtrEnable = $false; Log 'DTR pulse sent (needs DTR->RST wiring)' }
    catch { Log ('pulse failed: ' + $_.Exception.Message) }
})
$btnRefresh.Add_Click({ Refresh-Ports; Log ('ports: ' + (($cmbPort.Items | ForEach-Object { $_ }) -join ', ')) })
$cmbPort.Add_DropDown({ Refresh-Ports })
$cmbPort.Add_DropDownClosed({ if ($cmbPort.Text -ne '') { $script:PortAuto = $false } })

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 3000
$timer.Add_Tick({ if (($port -eq $null -or -not $port.IsOpen) -and -not $cmbPort.DroppedDown) { Refresh-Ports }; Update-HexInfo })
$form.Add_Activated({ Update-HexInfo })

$pollTimer = New-Object Windows.Forms.Timer; $pollTimer.Interval = 50
$pollTimer.Add_Tick({
    try {
        if ($script:port -ne $null -and $script:port.IsOpen -and $script:port.BytesToRead -gt 0) {
            $termLog.AppendText($script:port.ReadExisting())
            if ((-not $termForm.Visible) -and [bool]$cfg.SerialAuto -and (Get-AutoFlow 'Auto-open terminal')) { Show-Terminal }
        }
    } catch {
        Close-Serial
        Log ('serial read failed: ' + $_.Exception.Message)
    }
})

$form.Add_KeyDown({
    if ($_.KeyCode -eq 'F5') { $btnRun.PerformClick(); $_.Handled = $true }
    elseif ($_.KeyCode -eq 'F6') { $btnStartApp.PerformClick(); $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'O') { Invoke-BrowseHex; $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'S') { Save-BufferContents; $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'B') { Device-BlankCheck; $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'T') { Invoke-SerialButton; $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'L') { $btnClear.PerformClick(); $_.Handled = $true }
    elseif ($_.Control -and $_.KeyCode -eq 'R') { $btnFwReset.PerformClick(); $_.Handled = $true }
})

$form.Add_FormClosing({ Close-Serial; try { $timer.Stop() } catch {}; try { $pollTimer.Stop() } catch {} })

Refresh-Ports
# Restore saved automation choices (and keep them consistent with SerialAuto)
try {
    if ($cfg.AutoFlow -ne $null) {
        foreach ($p in ($cfg.AutoFlow.PSObject.Properties)) {
            if ($chkAutoFlow.ContainsKey($p.Name)) { $chkAutoFlow[$p.Name].Checked = [bool]$p.Value }
        }
    }
    if ([bool]$cfg.SerialAuto -eq $false) { $chkAutoFlow['Auto-open terminal'].Checked = $false }
    else { $chkAutoFlow['Auto-open terminal'].Checked = $true }
} catch {}
Wire-AutoFlowCheckboxes
Update-SerialButtons
Update-DeviceMenu
Update-HexInfo
if (($cmbHex.Text -ne '') -and (Test-Path $cmbHex.Text)) { Update-StateNext 'Press Run (F5)' } else { Update-StateNext 'Pick a valid hex (Ctrl+O)' }
if ($hexFallbackNotice) { Log $hexFallbackNotice }
$timer.Start()
[void]$form.ShowDialog()

