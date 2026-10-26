# Runs as SYSTEM: expose Kiro's loopback-only CDP port (9222) to the Mac host only.
param([int]$Inner = 9222, [int]$Outer = 9223, [string]$Mac = '10.211.55.2')
$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Ethernet).IPAddress
netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$Outer 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$Outer connectaddress=127.0.0.1 connectport=$Inner
Get-NetFirewallRule -DisplayName 'Kiro CDP from Mac' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Kiro CDP from Mac' -Direction Inbound -Protocol TCP -LocalPort $Outer -RemoteAddress $Mac -Action Allow | Out-Null
Set-Service iphlpsvc -StartupType Automatic; Start-Service iphlpsvc
netsh interface portproxy show v4tov4
