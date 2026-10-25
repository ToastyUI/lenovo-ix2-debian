# Receive Linux netconsole (UDP 6666, also broadcast) and append it to netconsole.log next to
# this script. Run in its own PowerShell window before rebooting the NAS; Ctrl+C stops it.
#   powershell -ExecutionPolicy Bypass -File ts41x-netconsole-listen.ps1
$port = 6666
$log = Join-Path $PSScriptRoot 'netconsole.log'
$udp = New-Object System.Net.Sockets.UdpClient($port)
$ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
Write-Host "listening on UDP $port, writing $log"
while ($true) {
  $bytes = $udp.Receive([ref]$ep)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  Add-Content -Path $log -Value $text -NoNewline
  Write-Host -NoNewline $text
}
