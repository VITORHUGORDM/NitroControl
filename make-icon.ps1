# Gera icon.ico (imagens PNG dentro de um .ico, suportado desde o Windows Vista). Rodar so se quiser refazer o icone.
param([string]$PreviewPng)
Add-Type -AssemblyName System.Drawing

function Render($s) {
    $bmp = New-Object Drawing.Bitmap $s, $s
    $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
    # fundo: quadrado arredondado escuro
    $r = [math]::Max(4, [int]($s * 0.22)); $e = $s - 1
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $r, $r, 180, 90); $path.AddArc($e - $r, 0, $r, $r, 270, 90)
    $path.AddArc($e - $r, $e - $r, $r, $r, 0, 90); $path.AddArc(0, $e - $r, $r, $r, 90, 90); $path.CloseFigure()
    $g.FillPath((New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point 0, 0), (New-Object Drawing.Point $s, $s), [Drawing.Color]::FromArgb(48, 20, 8), [Drawing.Color]::FromArgb(10, 6, 4))), $path)
    # simbolo do topo do app (M5 3 l7 6 7-6 v18 l-7-6 -7 6 z, grade 24x24)
    $k = $s / 24
    $pts = @((5, 3), (12, 9), (19, 3), (19, 21), (12, 15), (5, 21)) | % { New-Object Drawing.PointF ($_[0] * $k), ($_[1] * $k) }
    $g.FillPolygon((New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Point 0, $s), (New-Object Drawing.Point $s, 0), [Drawing.Color]::FromArgb(255, 178, 26), [Drawing.Color]::FromArgb(255, 30, 60))), [Drawing.PointF[]]$pts)
    $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
    if ($PreviewPng -and $s -eq 256) { $bmp.Save($PreviewPng) }
    , $ms.ToArray()
}

$sizes = 16, 32, 48, 256
$pngs = $sizes | % { , (Render $_) }
$out = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $out
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = [byte]($sizes[$i] % 256)  # 256 vira 0 no formato ICO
    $w.Write($d); $w.Write($d); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
$pngs | % { $w.Write($_) }; $w.Flush()
[IO.File]::WriteAllBytes("$PSScriptRoot\icon.ico", $out.ToArray())
