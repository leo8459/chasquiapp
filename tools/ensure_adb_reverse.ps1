param(
    [int] $Port = 8001,
    [int] $IntervalSeconds = 3
)

$adbPath = 'C:\Users\Ryzen\AppData\Local\Android\Sdk\platform-tools\adb.exe'

while ($true) {
    if (Test-Path -LiteralPath $adbPath) {
        $connectedDevices = & $adbPath devices 2>$null
        if ($connectedDevices -match "`tdevice$") {
            & $adbPath reverse "tcp:$Port" "tcp:$Port" *> $null
        }
    }

    Start-Sleep -Seconds ([Math]::Max(1, $IntervalSeconds))
}
