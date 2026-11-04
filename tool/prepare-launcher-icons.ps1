$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskDensities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
foreach ($taskDay in @('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')) {
    $taskSource = [System.Drawing.Bitmap]::new((Join-Path $taskRoot "artwork\launcher-icons\$taskDay.png"))
    try {
        # Trim transparent padding only, then fit the complete artwork into a common square.
        $taskLeft = $taskSource.Width
        $taskTop = $taskSource.Height
        $taskRight = -1
        $taskBottom = -1
        for ($taskY = 0; $taskY -lt $taskSource.Height; $taskY++) {
            for ($taskX = 0; $taskX -lt $taskSource.Width; $taskX++) {
                if ($taskSource.GetPixel($taskX, $taskY).A -gt 16) {
                    $taskLeft = [Math]::Min($taskLeft, $taskX)
                    $taskRight = [Math]::Max($taskRight, $taskX)
                    $taskTop = [Math]::Min($taskTop, $taskY)
                    $taskBottom = [Math]::Max($taskBottom, $taskY)
                }
            }
        }
        if ($taskRight -lt 0) { throw "Empty artwork: $taskDay" }
        $taskRect = [System.Drawing.Rectangle]::new($taskLeft, $taskTop, ($taskRight - $taskLeft + 1), ($taskBottom - $taskTop + 1))
        foreach ($taskDensity in $taskDensities.GetEnumerator()) {
            $taskSize = [int]$taskDensity.Value
            $taskCanvas = [System.Drawing.Bitmap]::new($taskSize, $taskSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $taskGraphics = [System.Drawing.Graphics]::FromImage($taskCanvas)
            try {
                $taskGraphics.Clear([System.Drawing.Color]::Transparent)
                $taskGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $taskGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $taskScale = ($taskSize * 0.92) / [Math]::Max($taskRect.Width, $taskRect.Height)
                $taskWidth = [int][Math]::Round($taskRect.Width * $taskScale)
                $taskHeight = [int][Math]::Round($taskRect.Height * $taskScale)
                $taskDestination = [System.Drawing.Rectangle]::new([int](($taskSize - $taskWidth) / 2), [int](($taskSize - $taskHeight) / 2), $taskWidth, $taskHeight)
                $taskGraphics.DrawImage($taskSource, $taskDestination, $taskRect, [System.Drawing.GraphicsUnit]::Pixel)
                $taskDirectory = Join-Path $taskRoot "android\app\src\main\res\mipmap-$($taskDensity.Key)"
                New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
                $taskCanvas.Save((Join-Path $taskDirectory "weekly_$taskDay.png"), [System.Drawing.Imaging.ImageFormat]::Png)
                $taskCanvas.Save((Join-Path $taskDirectory "weekly_${taskDay}_art.png"), [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $taskGraphics.Dispose()
                $taskCanvas.Dispose()
            }
        }
    } finally { $taskSource.Dispose() }
    # Keep a legacy transparent bitmap: some OEM launchers render the transparent
    # adaptive-icon background as a black plate around the emoji.
    # Remove old adaptive overrides as well, so regeneration cannot restore it.
    $taskAdaptiveIcon = Join-Path $taskRoot "android\app\src\main\res\mipmap-anydpi-v26\weekly_$taskDay.xml"
    if (Test-Path -LiteralPath $taskAdaptiveIcon) {
        Remove-Item -LiteralPath $taskAdaptiveIcon
    }
}