param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "assets\StudioDisplayXdr.ico")
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

function New-IconPngBytes {
    param([int]$Size)

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $scale = $Size / 256.0
        $monitor = [System.Drawing.RectangleF]::new(38 * $scale, 54 * $scale, 180 * $scale, 122 * $scale)
        $inner = [System.Drawing.RectangleF]::new(54 * $scale, 70 * $scale, 148 * $scale, 88 * $scale)
        $stand = [System.Drawing.RectangleF]::new(116 * $scale, 176 * $scale, 24 * $scale, 38 * $scale)
        $base = [System.Drawing.RectangleF]::new(82 * $scale, 212 * $scale, 92 * $scale, 14 * $scale)

        $outerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $outerRadius = 24 * $scale
        $outerPath.AddArc($monitor.Left, $monitor.Top, $outerRadius, $outerRadius, 180, 90)
        $outerPath.AddArc($monitor.Right - $outerRadius, $monitor.Top, $outerRadius, $outerRadius, 270, 90)
        $outerPath.AddArc($monitor.Right - $outerRadius, $monitor.Bottom - $outerRadius, $outerRadius, $outerRadius, 0, 90)
        $outerPath.AddArc($monitor.Left, $monitor.Bottom - $outerRadius, $outerRadius, $outerRadius, 90, 90)
        $outerPath.CloseFigure()

        $innerPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $innerRadius = 12 * $scale
        $innerPath.AddArc($inner.Left, $inner.Top, $innerRadius, $innerRadius, 180, 90)
        $innerPath.AddArc($inner.Right - $innerRadius, $inner.Top, $innerRadius, $innerRadius, 270, 90)
        $innerPath.AddArc($inner.Right - $innerRadius, $inner.Bottom - $innerRadius, $innerRadius, $innerRadius, 0, 90)
        $innerPath.AddArc($inner.Left, $inner.Bottom - $innerRadius, $innerRadius, $innerRadius, 90, 90)
        $innerPath.CloseFigure()

        $basePath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $baseRadius = 7 * $scale
        $basePath.AddArc($base.Left, $base.Top, $baseRadius, $baseRadius, 180, 90)
        $basePath.AddArc($base.Right - $baseRadius, $base.Top, $baseRadius, $baseRadius, 270, 90)
        $basePath.AddArc($base.Right - $baseRadius, $base.Bottom - $baseRadius, $baseRadius, $baseRadius, 0, 90)
        $basePath.AddArc($base.Left, $base.Bottom - $baseRadius, $baseRadius, $baseRadius, 90, 90)
        $basePath.CloseFigure()

        $shadowBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(42, 0, 0, 0))
        $screenBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $monitor,
            [System.Drawing.Color]::FromArgb(255, 35, 35, 40),
            [System.Drawing.Color]::FromArgb(255, 8, 8, 11),
            [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $glassBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $inner,
            [System.Drawing.Color]::FromArgb(255, 64, 64, 72),
            [System.Drawing.Color]::FromArgb(255, 32, 32, 38),
            [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
        $trimPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(255, 154, 154, 162), [Math]::Max(2, 5 * $scale))
        $standBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 158, 158, 166))
        $baseBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 150, 150, 158))
        $dotBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 52, 199, 89))

        $graphics.FillEllipse($shadowBrush, 48 * $scale, 206 * $scale, 160 * $scale, 26 * $scale)
        $graphics.FillPath($screenBrush, $outerPath)
        $graphics.DrawPath($trimPen, $outerPath)
        $graphics.FillPath($glassBrush, $innerPath)
        $graphics.FillRectangle($standBrush, $stand)
        $graphics.FillPath($baseBrush, $basePath)
        $graphics.FillEllipse($dotBrush, 188 * $scale, 38 * $scale, 30 * $scale, 30 * $scale)
    }
    finally {
        $graphics.Dispose()
    }

    $stream = [System.IO.MemoryStream]::new()
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $bitmap.Dispose()
    }
}

$destination = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $destination)) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
}

$sizes = @(256, 128, 64, 48, 32, 16)
$images = foreach ($size in $sizes) {
    [pscustomobject]@{
        Size = $size
        Bytes = New-IconPngBytes -Size $size
    }
}

$stream = [System.IO.File]::Create($OutputPath)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $encodedSize = if ($image.Size -eq 256) { 0 } else { $image.Size }
        $writer.Write([byte]$encodedSize)
        $writer.Write([byte]$encodedSize)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$image.Bytes.Length)
        $writer.Write([UInt32]$offset)
        $offset += $image.Bytes.Length
    }

    foreach ($image in $images) {
        $writer.Write($image.Bytes)
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Get-Item -LiteralPath $OutputPath
