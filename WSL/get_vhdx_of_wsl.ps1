$lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'

Get-ChildItem $lxss | ForEach-Object {
    $name = $_.GetValue('DistributionName')
    $base = $_.GetValue('BasePath')
    $vhdx = Join-Path $base 'ext4.vhdx'

    [pscustomobject]@{
        Distro = $name
        VhdxPath = $vhdx
        Exists = Test-Path $vhdx
    }
} | Sort-Object Distro | Format-Table -AutoSize
