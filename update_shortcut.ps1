$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut("C:\Users\Ahmed Shaban\Desktop\Silver Stone.lnk")
$shortcut.IconLocation = "d:\silverstone-work\working-tracker-app\windows\runner\resources\app_icon.ico,0"
$shortcut.Save()
Write-Host "Shortcut icon updated"
