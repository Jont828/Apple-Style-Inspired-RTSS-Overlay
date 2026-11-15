<#
.SYNOPSIS
Builds the 12V connector variants of Volt Sleek Meters Universal from an installed overlay.

.DESCRIPTION
Reads a Volt Sleek Meters Universal .ovl and its atlas (by default the Smoke theme from the RTSS
Overlays folder) and writes these copies, each with its own atlas:

  volt_sleek_meters_universal_12v_conn_smoke      12V + connector merged into "12V Connector", left of FPS
  volt_sleek_meters_universal_12v_conn_bar_smoke  FPS-style: big connector temp, headroom bar, side stats
  volt_sleek_meters_universal_12v_conn_ring_smoke CPU/GPU-style: headroom ring with temp, side stats

(volt_sleek_meters_universal_conn_smoke, the CONN section to the right of 12V, is not generated here.)

Like the CONN layout, each atlas is a copy of the source atlas with only the panel strip rebuilt; the
bar and ring reuse the existing 12V bar and CPU ring frames.

The atlases use short "volt_smu_*" names: OverlayEditor passes "Plugins\Client\Overlays\<atlas>" to RTSS, and
at 76+ characters RTSS no longer loads the image and draws font glyphs instead of the panel.

The connector values come from the HWiNFO custom sensor published by tools\edge-hub-hwinfo-bridge
("Lian Li Edge Hub"). The temperature blends from white to amber at the L-Connect warning limit and to red halfway
between the warning and shutdown limits. Bars and rings fill to 100% at the shutdown limit.
#>
param(
    [string]$SourceOvl = 'C:\Program Files (x86)\RivaTuner Statistics Server\Plugins\Client\Overlays\volt_sleek_meters_universal_smoke.ovl',
    [string]$OutDir = (Join-Path $PSScriptRoot '..\..\overlays\volt\sleek-meters-universal-connector\smoke\5120x1440'),
    [string]$Theme = 'smoke'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Enc = [System.Text.Encoding]::GetEncoding(1252)
$Deg = [char]0xB0
$ScreenCenter = 2560
# Same blended white -> amber -> red ramp as the CPU/GPU temperatures, driven by "Conn heat".
$ConnHeatColor = "FFFFFF,,0,FF9F0A,0,1,FF453A,1,(Conn heat,1)"
# Longest atlas path known to load ("Plugins\Client\Overlays\volt_sleek_meters_universal_conn_smoke_atlas.png").
$MaxAtlasPath = 72

# Source panel geometry (panel-local x).
$SrcPanelW = 859; $PanelH = 92
$SrcFpsX = 606; $SrcDivider = 769
$CpuRing = '0,94,67,67,51,15,0'   # CPU usage ring frames
$CableBar = '0,1022,64,32,51,16,0'   # 12V meter frames

function Read-Ovl([string]$path) {
    $sections = New-Object System.Collections.ArrayList
    $current = $null
    foreach ($line in [System.IO.File]::ReadAllLines($path, $Enc)) {
        if ($line -match '^\[(.+)\]$') {
            $current = [pscustomobject]@{ Name = $Matches[1]; Props = [ordered]@{} }
            [void]$sections.Add($current)
        } elseif ($current -and $line -match '^([^=]+)=(.*)$') {
            $current.Props[$Matches[1]] = $Matches[2]
        }
    }
    [pscustomobject]@{
        Head    = @($sections | Where-Object { $_.Name -notmatch '^(Source|Layer)\d+$' })
        Sources = [System.Collections.ArrayList]@($sections | Where-Object { $_.Name -match '^Source\d+$' } | ForEach-Object { $_.Props })
        Layers  = [System.Collections.ArrayList]@($sections | Where-Object { $_.Name -match '^Layer\d+$' } | ForEach-Object { $_.Props })
    }
}

function Write-Ovl($ovl, [string]$path) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($s in $ovl.Head) {
        if ($s.Name -eq 'General') { $s.Props['Sources'] = $ovl.Sources.Count; $s.Props['Layers'] = $ovl.Layers.Count }
        [void]$sb.Append("[$($s.Name)]`r`n")
        foreach ($k in $s.Props.Keys) { [void]$sb.Append("$k=$($s.Props[$k])`r`n") }
    }
    for ($i = 0; $i -lt $ovl.Sources.Count; $i++) {
        [void]$sb.Append("[Source$i]`r`n")
        foreach ($k in $ovl.Sources[$i].Keys) { [void]$sb.Append("$k=$($ovl.Sources[$i][$k])`r`n") }
    }
    for ($i = 0; $i -lt $ovl.Layers.Count; $i++) {
        [void]$sb.Append("[Layer$i]`r`n")
        foreach ($k in $ovl.Layers[$i].Keys) { [void]$sb.Append("$k=$($ovl.Layers[$i][$k])`r`n") }
    }
    [System.IO.File]::WriteAllText($path, $sb.ToString(), $Enc)
}

function Get-Layer($ovl, [string]$name) { $ovl.Layers | Where-Object { $_['Name'] -eq $name } | Select-Object -First 1 }
function Remove-Layers($ovl, [string[]]$names) { foreach ($n in $names) { $l = Get-Layer $ovl $n; if ($l) { $ovl.Layers.Remove($l) } } }
function Remove-Source($ovl, [string]$name) { $s = $ovl.Sources | Where-Object { $_['Name'] -eq $name } | Select-Object -First 1; if ($s) { $ovl.Sources.Remove($s) } }

function New-Layer([string]$name, [string]$text, [int]$x, [int]$y, [int]$ex = 0, [int]$ey = 0, [int]$origin = 0, [int]$size = 0, [string]$color = $null) {
    $l = [ordered]@{ Name = $name; Text = $text; PositionX = $x; PositionY = $y; ExtentX = $ex; ExtentY = $ey; ExtentOrigin = $origin }
    if ($size) { $l['Size'] = $size }
    if ($color) { $l['TextColor'] = $color }
    $l
}

# A secondary stat in the Sleek Meters style: grey label on the left, white value right-aligned.
function Add-Row($ovl, [string]$label, [string]$value, [int]$x, [int]$y, [int]$w) {
    [void]$ovl.Layers.Add((New-Layer "Conn $label label" $label $x ($y + 2) 0 0 0 58 'E5E5EA'))
    [void]$ovl.Layers.Add((New-Layer "Conn $label" $value $x $y $w 16 2 65 'FFFFFF'))
}

function Add-HwInfoSource($ovl, [string]$name, [string]$reading) {
    [void]$ovl.Sources.Add([ordered]@{ Name = $name; Units = "${Deg}C"; Format = '%.0f'; Formula = ''; Provider = 'HwInfo'
        SensorInst = 0; ReadingType = 1; ReadingName = $reading })
}

function Add-StubSource($ovl, [string]$name, [string]$units, [string]$formula) {
    [void]$ovl.Sources.Add([ordered]@{ Name = $name; Units = $units; Format = '%.0f'; Formula = $formula; Provider = 'HAL'; ID = 'Stub' })
}

function Add-ConnectorSources($ovl, [bool]$withPct) {
    Add-HwInfoSource $ovl 'GPU conn temp' 'GPU 1 Connector'
    Add-HwInfoSource $ovl 'Case temp' 'Hub Ambient'
    Add-HwInfoSource $ovl 'Conn warning' 'Connector Warning Limit'
    Add-HwInfoSource $ovl 'Conn shutdown' 'Connector Shutdown Limit'
    # Distance into the warning zone: 0 at the warning limit, 1 halfway to shutdown, 2 at shutdown.
    Add-StubSource $ovl 'Conn heat' '' '("GPU conn temp" - "Conn warning") * 2 / ("Conn shutdown" - "Conn warning")'
    if ($withPct) { Add-StubSource $ovl 'Conn pct' '%' '"GPU conn temp" * 100 / "Conn shutdown"' }
}

# Re-centres the panel at its new width; FPS layers additionally move to $fpsLocalX. Returns the new panel X.
function Set-Positions($ovl, [int]$newPanelW, [int]$fpsLocalX) {
    $srcX0 = [int](Get-Layer $ovl 'Panel')['PositionX']
    $newX0 = $ScreenCenter - [Math]::Floor($newPanelW / 2)
    $fpsLayers = 'FPS label', 'FPS', '1% label', '1%', 'FT label', 'FT', 'Frametime graph'
    foreach ($l in $ovl.Layers) {
        $local = [int]$l['PositionX'] - $srcX0
        if ($fpsLayers -contains $l['Name']) { $local += $fpsLocalX - $SrcFpsX }
        $l['PositionX'] = $newX0 + $local
    }
    $panel = Get-Layer $ovl 'Panel'
    $panel['Text'] = "<I=0,0,0,0,$newPanelW,$PanelH>"
    $panel['ExtentX'] = $newPanelW
    $newX0
}

# Copies the source atlas and rebuilds only the panel strip at $panelW with dividers centred at $dividers.
function Build-Atlas([string]$srcPng, [string]$dstPng, [int]$panelW, [int[]]$dividers) {
    $src = [System.Drawing.Bitmap]::FromFile($srcPng)
    $dst = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImageUnscaled($src, 0, 0)
    $g.Dispose()
    $cap = 30; $plain = 700; $srcDividerX = $SrcDivider - 2
    for ($x = 0; $x -lt $src.Width; $x++) {
        if ($x -ge $panelW) { $sx = -1 }
        elseif ($x -lt $cap) { $sx = $x }
        elseif ($x -ge $panelW - $cap) { $sx = $SrcPanelW - ($panelW - $x) }
        else { $sx = $plain }
        foreach ($d in $dividers) { if ($x -ge $d - 2 -and $x -le $d + 2) { $sx = $srcDividerX + ($x - ($d - 2)) } }
        for ($y = 0; $y -lt $PanelH; $y++) {
            $dst.SetPixel($x, $y, $(if ($sx -lt 0) { [System.Drawing.Color]::Transparent } else { $src.GetPixel($sx, $y) }))
        }
    }
    $src.Dispose()
    $dst.Save($dstPng, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

function New-Variant([string]$suffix, [string]$displayName, [scriptblock]$build) {
    $base = "volt_sleek_meters_universal_${suffix}_$Theme"
    $atlas = "volt_smu_${suffix}_${Theme}_atlas.png"
    if (("Plugins\Client\Overlays\" + $atlas).Length -gt $MaxAtlasPath) { throw "Atlas name $atlas is too long for RTSS" }
    $ovl = Read-Ovl $SourceOvl
    $settings = ($ovl.Head | Where-Object Name -eq 'Settings').Props
    $settings['Name'] = "Volt Sleek Meters Universal $displayName " + (Get-Culture).TextInfo.ToTitleCase($Theme)
    $settings['EmbeddedImage'] = $atlas
    [void](& $build $ovl (Join-Path $OutDir $atlas))
    Write-Ovl $ovl (Join-Path $OutDir "$base.ovl")
    "Wrote $base"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$srcSettings = ((Read-Ovl $SourceOvl).Head | Where-Object Name -eq 'Settings').Props
$SrcPng = Join-Path (Split-Path $SourceOvl) $srcSettings['EmbeddedImage']

# 1) "12V Connector": voltage + meter and connector temp in one section, left of FPS.
New-Variant '12v_conn' '12V Conn' {
    param($ovl, $png)
    $s = 610; $divider = 752; $fps = 764; $w = 932
    Add-ConnectorSources $ovl $false
    $x0 = Set-Positions $ovl $w $fps
    $dx = $x0 + $s - [int](Get-Layer $ovl 'Cable label')['PositionX']
    foreach ($n in 'Cable label', 'Cable voltage', 'Cable V', 'Cable meter') { $l = Get-Layer $ovl $n; $l['PositionX'] = [int]$l['PositionX'] + $dx }
    (Get-Layer $ovl 'Cable label')['Text'] = '12V Connector'
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" ($x0 + $s + 84) 56 0 0 0 105 $ConnHeatColor))
    [void]$ovl.Layers.Add((New-Layer 'CONN sub' "Case %Case temp%$Deg" ($x0 + $s + 85) 80 0 0 0 60 'E5E5EA'))
    Build-Atlas $SrcPng $png $w @(296, 594, $divider)
}

# 3a) FPS-style: big connector temp with a headroom bar underneath, secondary stats on the right.
New-Variant '12v_conn_bar' '12V Conn Bar' {
    param($ovl, $png)
    $s = 610; $divider = 798; $fps = 810; $w = 978
    Add-ConnectorSources $ovl $true
    $titleColor = (Get-Layer $ovl 'Cable label')['TextColor']
    Remove-Layers $ovl 'Cable label', 'Cable voltage', 'Cable V', 'Cable meter'
    Remove-Source $ovl '12V pct'
    $x0 = Set-Positions $ovl $w $fps
    $x = $x0 + $s
    [void]$ovl.Layers.Add((New-Layer 'Conn title' '12V Connector' $x 36 0 0 0 66 $titleColor))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" $x 49 0 0 0 170 $ConnHeatColor))
    [void]$ovl.Layers.Add((New-Layer 'Conn bar' "<AI=Conn pct,0,0,0,102,$CableBar>" $x 92 64 32 0))
    Add-Row $ovl 'Case' "%Case temp%$Deg" ($x + 84) 36 92
    Add-Row $ovl '12V' '%12V cable% V' ($x + 84) 58 92
    Add-Row $ovl 'Shutdown' "%Conn shutdown%$Deg" ($x + 84) 80 92
    Build-Atlas $SrcPng $png $w @(296, 594, $divider)
}

# 3b) CPU/GPU-style: headroom ring with the connector temp inside, title and secondary stats on the right.
New-Variant '12v_conn_ring' '12V Conn Ring' {
    param($ovl, $png)
    $s = 610; $divider = 801; $fps = 813; $w = 981
    Add-ConnectorSources $ovl $true
    $titleColor = ($ovl.Layers | Where-Object { $_['Text'] -eq 'CPU' } | Select-Object -First 1)['TextColor']   # matches the CPU ring
    Remove-Layers $ovl 'Cable label', 'Cable voltage', 'Cable V', 'Cable meter'
    Remove-Source $ovl '12V pct'
    $x0 = Set-Positions $ovl $w $fps
    $x = $x0 + $s
    [void]$ovl.Layers.Add((New-Layer 'Conn ring' "<AI=Conn pct,0,0,0,102,$CpuRing>" $x 37 67 67 0))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" $x 37 67 67 4 86 $ConnHeatColor))
    [void]$ovl.Layers.Add((New-Layer 'Conn title' '12V Connector' ($x + 79) 36 0 0 0 66 $titleColor))
    Add-Row $ovl 'Case' "%Case temp%$Deg" ($x + 79) 55 100
    Add-Row $ovl '12V' '%12V cable% V' ($x + 79) 72 100
    Add-Row $ovl 'Shutdown' "%Conn shutdown%$Deg" ($x + 79) 89 100
    Build-Atlas $SrcPng $png $w @(296, 594, $divider)
}
