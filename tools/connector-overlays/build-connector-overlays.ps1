<#
.SYNOPSIS
Builds the 12V connector variants of Volt Sleek Meters Universal from an installed overlay.

.DESCRIPTION
Reads a Volt Sleek Meters Universal .ovl and its atlas (by default the Smoke theme from the RTSS
Overlays folder) and writes these copies, each with its own atlas:

  volt_sleek_meters_universal_12v_conn_smoke      "12V CONNECTOR" title over the connector temp, metered stats
  volt_sleek_meters_universal_12v_conn_bar_smoke  FPS-style: big connector temp, headroom bar, metered stats
  volt_sleek_meters_universal_12v_conn_ring_smoke CPU/GPU-style: headroom ring, title over temp, metered stats

Each section sits left of FPS and replaces the 12V section; the 12V voltage becomes one of the Ambient /
12V / Shutdown secondary stats, which are stacked with a meter underneath like CPU Power / Clock / RAM.

(volt_sleek_meters_universal_conn_smoke, the CONN section to the right of 12V, is not generated here.)

Like the CONN layout, each atlas is a copy of the source atlas with the panel strip rebuilt. The unused
64 px 12V meter frames are replaced by a green 30-frame ring, and green 104 px meter frames go in the
empty space right of the last CPU ring row, so the atlas keeps its standard size. Panels wider than the
atlas are drawn as two image layers (see Get-PanelHead).

The atlases use short "volt_smu_*" names: OverlayEditor passes "Plugins\Client\Overlays\<atlas>" to RTSS, and
at 76+ characters RTSS no longer loads the image and draws font glyphs instead of the panel.

The connector values come from the HWiNFO custom sensor published by tools\edge-hub-hwinfo-bridge
("Lian Li Edge Hub"). The temperature blends from white to amber at the L-Connect warning limit and to red halfway
between the warning and shutdown limits. The headroom ring/bar and the Shutdown meter fill to 100% at the shutdown
limit, the Ambient meter at the warning limit. Values that drive meters are HWiNFO sources with a formula: a HAL
Stub source with the same formula works in text and colours, but <AI> images always show its first (empty) frame.
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
$AtlasW = 1024; $PanelTailX = 600   # tail of a split panel starts at this strip x (plain, after the GPU divider)
$FpsTail = 168   # panel width right of the FPS section start (FPS plus right padding)
$Green = [System.Drawing.Color]::FromArgb(0x30, 0xD1, 0x58)   # 12V / FPS green
$Blue = [System.Drawing.Color]::FromArgb(0x0A, 0x84, 0xFF)    # CPU ring / meter blue
$Title = '12V CONNECTOR'
$TitleW = 116    # "12V CONNECTOR" is ~113 px at Size=66

# Source atlas frames that the connector frames are recoloured from.
$SrcRingY = 94; $SrcRingSize = 67; $SrcRingCols = 15; $SrcRingFrames = 51
$SrcMeterY = 634; $SrcMeterW = 104; $SrcMeterH = 32; $SrcMeterCols = 9; $SrcMeterFrames = 51
$Old12VMeterY = 995   # 64 px 12V meter frames (y 1022-1150), unused by these layouts; cleared from here down
# Generated green frames.
$RingY = 996; $RingFrames = 30
$MeterX = 402; $MeterY = 295; $MeterH = 6; $MeterCols = 5   # bar line is the top 6 px of a meter frame
$ConnRing = "0,$RingY,$SrcRingSize,$SrcRingSize,$RingFrames,$SrcRingCols,0"
$ConnMeter = "$MeterX,$MeterY,$SrcMeterW,$MeterH,$SrcMeterFrames,$MeterCols,0"

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

function New-Layer([string]$name, [string]$text, [int]$x, [int]$y, [int]$ex = 0, [int]$ey = 0, [int]$origin = 0, [int]$size = 0, [string]$color = $null) {
    $l = [ordered]@{ Name = $name; Text = $text; PositionX = $x; PositionY = $y; ExtentX = $ex; ExtentY = $ey; ExtentOrigin = $origin }
    if ($size) { $l['Size'] = $size }
    if ($color) { $l['TextColor'] = $color }
    $l
}

# A secondary stat in the Sleek Meters style: grey label and white value on one line, green meter underneath.
function Add-Row($ovl, [string]$label, [string]$value, [string]$pctSource, [int]$x, [int]$y) {
    [void]$ovl.Layers.Add((New-Layer "Conn $label label" $label $x ($y + 2) 0 0 0 58 'E5E5EA'))
    [void]$ovl.Layers.Add((New-Layer "Conn $label" $value $x $y $SrcMeterW 16 2 65 'FFFFFF'))
    [void]$ovl.Layers.Add((New-Layer "Conn $label meter" "<AI=$pctSource,0,0,0,102,$ConnMeter>" $x ($y + 18) $SrcMeterW $MeterH 0))
}

# Ambient / 12V / Shutdown rows at the CPU row positions.
function Add-Rows($ovl, [int]$x) {
    Add-Row $ovl 'Ambient' "%Ambient temp%$Deg" 'Ambient pct' $x 36
    Add-Row $ovl '12V' '%12V cable% V' '12V pct' $x 58
    Add-Row $ovl 'Shutdown' "%Conn shutdown%$Deg" 'Conn pct' $x 80
}

function Add-HwInfoSource($ovl, [string]$name, [string]$reading, [string]$units = "${Deg}C", [string]$formula = '') {
    [void]$ovl.Sources.Add([ordered]@{ Name = $name; Units = $units; Format = '%.0f'; Formula = $formula; Provider = 'HwInfo'
        SensorInst = 0; ReadingType = 1; ReadingName = $reading })
}

function Add-ConnectorSources($ovl) {
    Add-HwInfoSource $ovl 'GPU conn temp' 'GPU 1 Connector'
    Add-HwInfoSource $ovl 'Ambient temp' 'Hub Ambient'
    Add-HwInfoSource $ovl 'Conn warning' 'Connector Warning Limit'
    Add-HwInfoSource $ovl 'Conn shutdown' 'Connector Shutdown Limit'
    # Distance into the warning zone: 0 at the warning limit, 1 halfway to shutdown, 2 at shutdown.
    Add-HwInfoSource $ovl 'Conn heat' 'GPU 1 Connector' '' '(x - "Conn warning") * 2 / ("Conn shutdown" - "Conn warning")'
    Add-HwInfoSource $ovl 'Conn pct' 'GPU 1 Connector' '%' 'x * 100 / "Conn shutdown"'
    Add-HwInfoSource $ovl 'Ambient pct' 'Hub Ambient' '%' 'x * 100 / "Conn warning"'
}

# Removes the 12V section; its voltage moves into the connector rows. Returns the 12V title colour.
function Remove-12V($ovl) {
    $color = (Get-Layer $ovl 'Cable label')['TextColor']
    Remove-Layers $ovl 'Cable label', 'Cable voltage', 'Cable V', 'Cable meter'
    $color
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
    $headW = Get-PanelHead $newPanelW
    $panel['Text'] = "<I=0,0,0,0,$headW,$PanelH>"
    $panel['ExtentX'] = $headW
    if ($headW -lt $newPanelW) {
        # The rest of the panel is drawn from the strip's tail (see Build-Atlas).
        $tail = [ordered]@{ Name = 'Panel tail'; Text = "<I=0,0,$PanelTailX,0,$($newPanelW - $headW),$PanelH>"
            PositionX = $newX0 + $headW; PositionY = $panel['PositionY']; ExtentX = $newPanelW - $headW; ExtentY = $PanelH; ExtentOrigin = 0 }
        $ovl.Layers.Insert($ovl.Layers.IndexOf($panel) + 1, $tail)
    }
    $newX0
}

# Panels wider than the atlas are drawn as a head (strip 0..headW) and a tail (strip $PanelTailX..AtlasW), dropping
# surplus plain columns right of the GPU divider. Returns the head width.
function Get-PanelHead([int]$panelW) {
    if ($panelW -le $AtlasW) { return $panelW }
    $PanelTailX + $panelW - $AtlasW
}

# Copies the source atlas and rebuilds only the panel strip at $panelW with dividers centred at $dividers.
function Build-Atlas([string]$srcPng, [string]$dstPng, [int]$panelW, [int[]]$dividers) {
    $src = [System.Drawing.Bitmap]::FromFile($srcPng)
    $dst = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImageUnscaled($src, 0, 0)
    $g.Dispose()
    if ($src.Width -ne $AtlasW) { throw "Expected a $AtlasW px wide source atlas" }
    $cap = 30; $plain = 700; $srcDividerX = $SrcDivider - 2
    $headW = Get-PanelHead $panelW
    $shift = $panelW - $AtlasW   # strip x >= headW holds panel x + shift
    # Strip PanelTailX..headW is drawn by both the head and the tail, so it must be plain in both places.
    foreach ($d in $dividers) { if ($shift -gt 0 -and $d + 2 -ge $PanelTailX -and $d - 2 -lt $headW + $shift) { throw "Divider $d falls in the shared panel strip" } }
    for ($sx0 = 0; $sx0 -lt $src.Width; $sx0++) {
        $x = if ($sx0 -lt $headW) { $sx0 } else { $sx0 + [Math]::Max(0, $shift) }   # panel column
        if ($x -ge $panelW) { $sx = -1 }
        elseif ($x -lt $cap) { $sx = $x }
        elseif ($x -ge $panelW - $cap) { $sx = $SrcPanelW - ($panelW - $x) }
        else { $sx = $plain }
        foreach ($d in $dividers) { if ($x -ge $d - 2 -and $x -le $d + 2) { $sx = $srcDividerX + ($x - ($d - 2)) } }
        for ($y = 0; $y -lt $PanelH; $y++) {
            $dst.SetPixel($sx0, $y, $(if ($sx -lt 0) { [System.Drawing.Color]::Transparent } else { $src.GetPixel($sx, $y) }))
        }
    }
    $src.Dispose()
    Add-ConnectorFrames $dst
    $dst.Save($dstPng, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

# Copies a source frame with its blue fill shifted to green; the grey track is left as is.
function Copy-GreenFrame($bmp, [int]$sx, [int]$sy, [int]$dx, [int]$dy, [int]$w, [int]$h) {
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $bmp.GetPixel($sx + $x, $sy + $y)
            $t = [Math]::Max(0.0, [Math]::Min(1.0, ($c.B - $c.R) / ($Blue.B - $Blue.R)))   # how much of the pixel is blue fill
            $r = [Math]::Round($c.R + $t * ($Green.R - $Blue.R)); $gr = [Math]::Round($c.G + $t * ($Green.G - $Blue.G))
            $b = [Math]::Round($c.B + $t * ($Green.B - $Blue.B))
            $bmp.SetPixel($dx + $x, $dy + $y, [System.Drawing.Color]::FromArgb($c.A,
                [Math]::Max(0, [Math]::Min(255, $r)), [Math]::Max(0, [Math]::Min(255, $gr)), [Math]::Max(0, [Math]::Min(255, $b))))
        }
    }
}

# Replaces the unused 64 px 12V meter frames with a green ring and adds green 104 px meter frames.
function Add-ConnectorFrames($bmp) {
    for ($y = $Old12VMeterY; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent) }
    }
    for ($i = 0; $i -lt $RingFrames; $i++) {
        $s = [int][Math]::Round($i * ($SrcRingFrames - 1) / ($RingFrames - 1))
        Copy-GreenFrame $bmp (($s % $SrcRingCols) * $SrcRingSize) ($SrcRingY + [Math]::Floor($s / $SrcRingCols) * $SrcRingSize) `
            (($i % $SrcRingCols) * $SrcRingSize) ($RingY + [Math]::Floor($i / $SrcRingCols) * $SrcRingSize) $SrcRingSize $SrcRingSize
    }
    for ($i = 0; $i -lt $SrcMeterFrames; $i++) {
        Copy-GreenFrame $bmp (($i % $SrcMeterCols) * $SrcMeterW) ($SrcMeterY + [Math]::Floor($i / $SrcMeterCols) * $SrcMeterH) `
            ($MeterX + ($i % $MeterCols) * $SrcMeterW) ($MeterY + [Math]::Floor($i / $MeterCols) * $MeterH) $SrcMeterW $MeterH
    }
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

# Places a connector section of width $cw at panel-local $s, left of FPS. Returns its screen x.
function Set-Section($ovl, [string]$png, [int]$s, [int]$cw) {
    $divider = $s + $cw + 12
    $w = $divider + 12 + $FpsTail
    $x0 = Set-Positions $ovl $w ($divider + 12)
    Build-Atlas $SrcPng $png $w @(296, 594, $divider)
    $x0 + $s
}

# CPU/GPU-style title with the connector temp centred underneath.
function Add-TitleColumn($ovl, [int]$x, [string]$color) {
    [void]$ovl.Layers.Add((New-Layer 'Conn title' $Title $x 36 $TitleW 13 4 66 $color))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" ($x + 3) 56 $TitleW 32 4 150 $ConnHeatColor))
}

$Gap = 18          # title column to stats
$ConnStart = 610   # panel-local start of the connector section (after the GPU divider)

# 1) Title over the connector temp, metered stats on the right.
New-Variant '12v_conn' '12V Conn' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $x = Set-Section $ovl $png $ConnStart ($TitleW + $Gap + $SrcMeterW)
    Add-TitleColumn $ovl $x $color
    Add-Rows $ovl ($x + $TitleW + $Gap)
}

# 2) FPS-style: big connector temp with a headroom meter underneath, metered stats on the right.
New-Variant '12v_conn_bar' '12V Conn Bar' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $x = Set-Section $ovl $png $ConnStart ($TitleW + $Gap + $SrcMeterW)
    [void]$ovl.Layers.Add((New-Layer 'Conn title' $Title $x 36 0 0 0 66 $color))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" $x 49 0 0 0 170 $ConnHeatColor))
    [void]$ovl.Layers.Add((New-Layer 'Conn meter' "<AI=Conn pct,0,0,0,102,$ConnMeter>" $x 98 $SrcMeterW $MeterH 0))
    Add-Rows $ovl ($x + $TitleW + $Gap)
}

# 3) CPU/GPU-style: headroom ring with the % inside, title over temp, metered stats on the right.
New-Variant '12v_conn_ring' '12V Conn Ring' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $col = $SrcRingSize + 11
    $x = Set-Section $ovl $png $ConnStart ($col + $TitleW + $Gap + $SrcMeterW)
    [void]$ovl.Layers.Add((New-Layer 'Conn ring' "<AI=Conn pct,0,0,0,102,$ConnRing>" $x 37 $SrcRingSize $SrcRingSize 0))
    [void]$ovl.Layers.Add((New-Layer 'Conn pct' '%Conn pct%' $x 37 $SrcRingSize $SrcRingSize 4 86 'FFFFFF'))
    Add-TitleColumn $ovl ($x + $col) $color
    Add-Rows $ovl ($x + $col + $TitleW + $Gap)
}