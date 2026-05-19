param([string]$Path)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new($Path)
$w = $bmp.Width
$h = $bmp.Height
function Show($x, $y, $label) {
    $p = $bmp.GetPixel([int]$x, [int]$y)
    Write-Output ("{0,-12} R={1,3} G={2,3} B={3,3} A={4,3}" -f $label, $p.R, $p.G, $p.B, $p.A)
}
Show 5 5 'top-left'
Show ($w - 5) 5 'top-right'
Show 5 ($h - 5) 'bot-left'
Show ($w - 5) ($h - 5) 'bot-right'
Show ($w / 2) 5 'top-center'
Show ($w / 2) ($h / 2) 'center'
$bmp.Dispose()
