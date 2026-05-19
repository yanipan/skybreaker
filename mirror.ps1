Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile('C:\Users\User\Skybreaker\assets\sprites\playerbankingleft.png')
$src.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
$src.Save('C:\Users\User\Skybreaker\assets\sprites\playerbankingright.png', [System.Drawing.Imaging.ImageFormat]::Png)
$src.Dispose()
Write-Output 'mirrored ok'
