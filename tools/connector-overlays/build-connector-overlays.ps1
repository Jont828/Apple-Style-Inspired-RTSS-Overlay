<#
.SYNOPSIS
Builds the 12V connector variants of Volt Sleek Meters Universal from an installed overlay.

.DESCRIPTION
Reads a Volt Sleek Meters Universal .ovl and its atlas (by default the Smoke theme from the RTSS
Overlays folder) and writes these copies, each with its own atlas:

  volt_sleek_meters_universal_12v_conn_smoke      "12V-2x6" title over the connector temp, metered stats
  volt_sleek_meters_universal_12v_conn_bar_smoke  FPS-style: big connector temp, headroom bar, metered stats
  volt_sleek_meters_universal_12v_conn_ring_smoke CPU/GPU-style: headroom ring, title over temp, metered stats
  volt_sleek_meters_universal_12v_conn_ring_power_smoke
                                                  Ring layout, but the ring shows the GPU power (full at the
                                                  connector's 600 W rating) with the wattage inside it, and the
                                                  GPU Power stat is replaced by VRAM Temp
  volt_sleek_meters_universal_12v_conn_thermometer_smoke
                                                  Ring layout with a thermometer instead of the ring: it fills
                                                  toward the shutdown limit and is green below the warning limit,
                                                  yellow up to halfway to shutdown, then red

Each section sits left of FPS and replaces the 12V section; the 12V voltage becomes one of the Ambient /
12V / Shutdown secondary stats, which are stacked with a meter underneath like CPU Power / Clock / RAM.

(volt_sleek_meters_universal_conn_smoke, the CONN section to the right of 12V, is not generated here.)

Like the CONN layout, each atlas is a copy of the source atlas with the panel strip rebuilt. The 64 px 12V
meter frames move (as 6 px tall frames) to the empty space right of the last GPU ring row, and their old
place holds a green 30-frame ring; green 104 px meter frames go in the empty space right of the last CPU
ring row, so the atlas keeps its standard size. Panels wider than the atlas are drawn as two image layers
(see Get-PanelHead).

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
$Title = '12V-2x6'
$TitleW = 60     # same title column as CPU/GPU; "12V-2x6" is ~55 px at Size=66

# Source atlas frames that the connector frames are recoloured from.
$SrcRingY = 94; $SrcRingSize = 67; $SrcRingCols = 15; $SrcRingFrames = 51
$SrcMeterY = 634; $SrcMeterW = 104; $SrcMeterH = 32; $SrcMeterCols = 9; $SrcMeterFrames = 51
$Src12VMeterY = 1022; $Src12VMeterW = 64; $Src12VMeterCols = 16   # 64 px 12V meter frames (51, 32 px tall)
$Old12VMeterY = 995   # the 12V meter frames are moved, then cleared from here down
# Generated frames.
$RingY = 996; $RingFrames = 30
$MeterX = 402; $MeterY = 295; $MeterH = 6; $MeterCols = 5   # bar line is the top 6 px of a meter frame
$ShortMeterX = 402; $ShortMeterY = 565; $ShortMeterCols = 9
# RTSS stretches an image shorter than its layer's text line height to that height, which turns the 3 px line of a
# 6 px meter frame into a ~10 px block at the default size; a 25% font size keeps the line height under 6 px.
$MeterSize = 25
$ConnRing = "0,$RingY,$SrcRingSize,$SrcRingSize,$RingFrames,$SrcRingCols,0"
$ConnMeter = "$MeterX,$MeterY,$SrcMeterW,$MeterH,$SrcMeterFrames,$MeterCols,0"
$ConnShortMeter = "$ShortMeterX,$ShortMeterY,$Src12VMeterW,$MeterH,$SrcMeterFrames,$ShortMeterCols,0"
# Thermometer frames take the ring's place in the thermometer atlas: $ThermoFrames fill levels for each colour band.
$ThermoW = 22; $ThermoH = $SrcRingSize; $ThermoFrames = 30; $ThermoCols = [Math]::Floor($AtlasW / $ThermoW)
$ThermoBands = @(
    [System.Drawing.Color]::FromArgb(0x30, 0xD1, 0x58),   # green: below the warning limit
    [System.Drawing.Color]::FromArgb(0xFF, 0xD6, 0x0A),   # yellow: warning limit to halfway to shutdown
    [System.Drawing.Color]::FromArgb(0xFF, 0x45, 0x3A))   # red: past halfway to shutdown
$ThermoBandMax = 102   # value range of one band, as for the rings
$ConnThermo = "0,$RingY,$ThermoW,$ThermoH,$($ThermoFrames * $ThermoBands.Count),$ThermoCols,0"

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
    [void]$ovl.Layers.Add((New-Layer "Conn $label meter" "<AI=$pctSource,0,0,0,102,$ConnMeter>" $x ($y + 18) $SrcMeterW $MeterH 0 $MeterSize))
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

function Add-HalSource($ovl, [string]$name, [string]$id, [string]$units, [string]$formula) {
    [void]$ovl.Sources.Add([ordered]@{ Name = $name; Units = $units; Format = '%.0f'; Formula = $formula; Provider = 'HAL'; ID = $id })
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

# Turns the GPU section's Power stat into VRAM Temp (meter from "VRAM temp pct") and drops the VRAM temp under the
# GPU temperature, which would repeat it.
function Set-VramTempRow($ovl) {
    $label = Get-Layer $ovl 'GPU Power label'; $value = Get-Layer $ovl 'GPU Power'; $meter = Get-Layer $ovl 'GPU Power meter'
    if (-not ($label -and $value -and $meter -and $meter['Text'] -like '<AI=GPU power pct,*')) { throw 'Unexpected GPU Power stat' }
    $label['Name'] = 'GPU VRAM temp label'; $label['Text'] = 'VRAM Temp'
    $value['Name'] = 'GPU VRAM temp'; $value['Text'] = "%GPU mem temp%$Deg"
    $meter['Name'] = 'GPU VRAM temp meter'; $meter['Text'] = $meter['Text'].Replace('<AI=GPU power pct,', '<AI=VRAM temp pct,')
    Remove-Layers $ovl 'GPU sub'
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
# $frames, if given, is run on the finished atlas bitmap to add variant-specific frames.
function Build-Atlas([string]$srcPng, [string]$dstPng, [int]$panelW, [int[]]$dividers, [scriptblock]$frames = $null) {
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
    if ($frames) { & $frames $dst }
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

# Moves the 64 px 12V meter frames, puts a green ring in their place and adds green 104 px meter frames.
function Add-ConnectorFrames($bmp) {
    for ($i = 0; $i -lt $SrcMeterFrames; $i++) {
        $sx = ($i % $Src12VMeterCols) * $Src12VMeterW; $sy = $Src12VMeterY + [Math]::Floor($i / $Src12VMeterCols) * $SrcMeterH
        $dx = $ShortMeterX + ($i % $ShortMeterCols) * $Src12VMeterW; $dy = $ShortMeterY + [Math]::Floor($i / $ShortMeterCols) * $MeterH
        for ($y = 0; $y -lt $MeterH; $y++) { for ($x = 0; $x -lt $Src12VMeterW; $x++) { $bmp.SetPixel($dx + $x, $dy + $y, $bmp.GetPixel($sx + $x, $sy + $y)) } }
    }
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

# Anti-aliased coverage (0..1 per pixel) of the shapes $draw fills on a $w x $h canvas, rendered at 4x and averaged.
function Get-Coverage([int]$w, [int]$h, [scriptblock]$draw) {
    $ss = 4
    $big = New-Object System.Drawing.Bitmap(($w * $ss), ($h * $ss), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($big)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.ScaleTransform($ss, $ss)
    & $draw $g ([System.Drawing.Brushes]::White)
    $g.Dispose()
    $data = $big.LockBits((New-Object System.Drawing.Rectangle(0, 0, $big.Width, $big.Height)),
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $big.PixelFormat)
    $bytes = New-Object byte[] ($data.Stride * $big.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $big.UnlockBits($data); $big.Dispose()
    $cov = New-Object double[] ($w * $h)
    for ($y = 0; $y -lt $h * $ss; $y++) {
        $row = $y * $data.Stride; $o = [Math]::Floor($y / $ss) * $w
        for ($x = 0; $x -lt $w * $ss; $x++) { $cov[$o + [Math]::Floor($x / $ss)] += $bytes[$row + $x * 4 + 3] }
    }
    for ($i = 0; $i -lt $cov.Length; $i++) { $cov[$i] /= 255 * $ss * $ss }
    , $cov
}

# Replaces the ring frames with thermometers in the ring's track grey: a tube with a bulb, holding a narrower column
# of liquid that rises from the bulb. Frame (band * $ThermoFrames + level) is drawn in that band's colour.
function Add-ThermometerFrames($bmp) {
    $rows = [Math]::Ceiling($ThermoFrames * $ThermoBands.Count / $ThermoCols)
    if ($RingY + $rows * $ThermoH -gt $bmp.Height) { throw 'Thermometer frames do not fit in the atlas' }
    for ($y = $RingY; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent) }
    }
    $trackAlpha = 125 / 255   # same as the ring track
    $bulbY = 56; $emptyTop = 49; $fullTop = 3   # bulb centre; liquid column top when empty and when full
    $track = Get-Coverage $ThermoW $ThermoH {
        param($g, $b)
        $g.FillEllipse($b, 1, ($bulbY - 10), 20, 20); $g.FillEllipse($b, 6, 1, 10, 10); $g.FillRectangle($b, 6, 6, 10, ($bulbY - 6))
    }
    for ($k = 0; $k -lt $ThermoFrames; $k++) {
        $top = $emptyTop + ($fullTop - $emptyTop) * $k / ($ThermoFrames - 1)
        $liquid = Get-Coverage $ThermoW $ThermoH {
            param($g, $b)
            $g.FillEllipse($b, 4, ($bulbY - 7), 14, 14); $g.FillEllipse($b, 8, $top, 6, 6)
            $g.FillRectangle($b, 8, ($top + 3), 6, ($bulbY - $top - 3))
        }
        for ($band = 0; $band -lt $ThermoBands.Count; $band++) {
            $c = $ThermoBands[$band]; $i = $band * $ThermoFrames + $k
            $dx = ($i % $ThermoCols) * $ThermoW; $dy = $RingY + [Math]::Floor($i / $ThermoCols) * $ThermoH
            for ($p = 0; $p -lt $track.Length; $p++) {
                $l = $liquid[$p]; $t = $track[$p] * $trackAlpha * (1 - $l); $a = $l + $t
                if ($a -le 0) { continue }
                $bmp.SetPixel($dx + $p % $ThermoW, $dy + [Math]::Floor($p / $ThermoW), [System.Drawing.Color]::FromArgb(
                    [int][Math]::Round(255 * $a), [int][Math]::Round(($c.R * $l + 255 * $t) / $a),
                    [int][Math]::Round(($c.G * $l + 255 * $t) / $a), [int][Math]::Round(($c.B * $l + 255 * $t) / $a)))
            }
        }
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
function Set-Section($ovl, [string]$png, [int]$s, [int]$cw, [scriptblock]$frames = $null) {
    $divider = $s + $cw + 12
    $w = $divider + 12 + $FpsTail
    $x0 = Set-Positions $ovl $w ($divider + 12)
    Build-Atlas $SrcPng $png $w @(296, 594, $divider) $frames
    $x0 + $s
}

# CPU/GPU-style title with the connector temp centred underneath.
function Add-TitleColumn($ovl, [int]$x, [string]$color) {
    [void]$ovl.Layers.Add((New-Layer 'Conn title' $Title $x 36 $TitleW 13 4 66 $color))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" ($x + 3) 56 $TitleW 32 4 150 $ConnHeatColor))
}

$Gap = 29          # title column to stats, as for CPU/GPU
$ConnStart = 607   # panel-local start of the connector section (13 px after the GPU divider, as for CPU/GPU)
$FpsGap = 84       # big value to stats, as for FPS

# 1) Title over the connector temp, metered stats on the right.
New-Variant '12v_conn' '12V Conn' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $x = Set-Section $ovl $png $ConnStart ($TitleW + $Gap + $SrcMeterW)
    Add-TitleColumn $ovl $x $color
    Add-Rows $ovl ($x + $TitleW + $Gap)
}

# 2) FPS-style: big connector temp with a 12V-sized headroom meter underneath, metered stats on the right.
New-Variant '12v_conn_bar' '12V Conn Bar' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $x = Set-Section $ovl $png $ConnStart ($FpsGap + $SrcMeterW)
    [void]$ovl.Layers.Add((New-Layer 'Conn title' $Title $x 36 0 0 0 66 $color))
    [void]$ovl.Layers.Add((New-Layer 'CONN temperature' "%GPU conn temp%$Deg" $x 49 0 0 0 170 $ConnHeatColor))
    [void]$ovl.Layers.Add((New-Layer 'Conn meter' "<AI=Conn pct,0,0,0,102,$ConnShortMeter>" $x 98 $Src12VMeterW $MeterH 0 $MeterSize))
    Add-Rows $ovl ($x + $FpsGap)
}

# 3) CPU/GPU-style: headroom ring, title over temp, metered stats on the right.
New-Variant '12v_conn_ring' '12V Conn Ring' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $color = Remove-12V $ovl
    $col = $SrcRingSize + 11
    $x = Set-Section $ovl $png $ConnStart ($col + $TitleW + $Gap + $SrcMeterW)
    [void]$ovl.Layers.Add((New-Layer 'Conn ring' "<AI=Conn pct,0,0,0,102,$ConnRing>" $x 37 $SrcRingSize $SrcRingSize 0))
    Add-TitleColumn $ovl ($x + $col) $color
    Add-Rows $ovl ($x + $col + $TitleW + $Gap)
}

# 4) Ring layout with the ring showing GPU power against the connector's 600 W rating and the wattage inside it; the
#    GPU section's Power stat becomes VRAM Temp (and the VRAM temp under the GPU temperature goes, as it would repeat).
New-Variant '12v_conn_ring_power' '12V Conn Ring Power' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    Add-HalSource $ovl 'Conn power pct' 'GPU1 power' '%' 'x / 6'
    Add-HalSource $ovl 'VRAM temp pct' 'GPU1 memory temperature' '%' 'x / 1.1'   # full at 110 C
    $color = Remove-12V $ovl
    Set-VramTempRow $ovl
    $col = $SrcRingSize + 11
    $x = Set-Section $ovl $png $ConnStart ($col + $TitleW + $Gap + $SrcMeterW)
    [void]$ovl.Layers.Add((New-Layer 'Conn ring' "<AI=Conn power pct,0,0,0,102,$ConnRing>" $x 37 $SrcRingSize $SrcRingSize 0))
    # Wattage centred a little high, like the CPU/GPU usage, with a small unit underneath.
    [void]$ovl.Layers.Add((New-Layer 'Conn power' '%GPU1 power%' $x 37 $SrcRingSize 60 4 86 'FFFFFF'))
    [void]$ovl.Layers.Add((New-Layer 'Conn power unit' 'W' $x 80 $SrcRingSize 13 4 58 'E5E5EA'))
    Add-TitleColumn $ovl ($x + $col) $color
    Add-Rows $ovl ($x + $col + $TitleW + $Gap)
}

# 5) Ring layout with a thermometer in place of the ring. "Conn thermo" picks the frame: the band (0 green, 1 yellow,
#    2 red, switching at the warning limit and halfway to shutdown, like the temperature colour) times
#    $ThermoBandMax, plus the fill toward the shutdown limit (capped at 100%), plus 1 so a band's first and last
#    levels never round into the neighbouring band.
New-Variant '12v_conn_thermometer' '12V Conn Thermometer' {
    param($ovl, $png)
    Add-ConnectorSources $ovl
    $band = '((x > "Conn warning") + (x > ("Conn warning" + "Conn shutdown") / 2))'
    $fill = '100 * (x - (x - "Conn shutdown") * (x > "Conn shutdown")) / "Conn shutdown"'
    Add-HwInfoSource $ovl 'Conn thermo' 'GPU 1 Connector' '' "$ThermoBandMax * $band + $fill + 1"
    $color = Remove-12V $ovl
    $col = $ThermoW + 11
    $x = Set-Section $ovl $png $ConnStart ($col + $TitleW + $Gap + $SrcMeterW) { param($bmp) Add-ThermometerFrames $bmp }
    $max = $ThermoBandMax * $ThermoBands.Count
    [void]$ovl.Layers.Add((New-Layer 'Conn thermometer' "<AI=Conn thermo,0,0,0,$max,$ConnThermo>" $x 37 $ThermoW $ThermoH 0))
    Add-TitleColumn $ovl ($x + $col) $color
    Add-Rows $ovl ($x + $col + $TitleW + $Gap)
}
