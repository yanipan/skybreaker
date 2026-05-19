param([string]$Path)
Add-Type -AssemblyName System.Drawing
# Load source then re-draw into a fresh 32bppArgb bitmap so we have a real alpha channel
$src = [System.Drawing.Bitmap]::new($Path)
$bmp = [System.Drawing.Bitmap]::new($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.DrawImage($src, 0, 0, $src.Width, $src.Height)
$gfx.Dispose()
$src.Dispose()

$rect = [System.Drawing.Rectangle]::new(0, 0, $bmp.Width, $bmp.Height)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $bmp.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
# BGRA byte order. Threshold 240 — only near-white turns transparent.
for ($i = 0; $i -lt $bytes.Length; $i += 4) {
    $b = $bytes[$i]
    $g = $bytes[$i+1]
    $r = $bytes[$i+2]
    if ($r -ge 240 -and $g -ge 240 -and $b -ge 240) {
        $bytes[$i+3] = 0
    }
}
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$bmp.UnlockBits($data)
$tmp = [System.IO.Path]::GetTempFileName() + '.png'
$bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Move-Item -Force $tmp $Path
Write-Output "removed white from $Path"
