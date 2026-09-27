@echo off
REM Adds a Windows Firewall inbound rule so other POS terminals can reach
REM this host station on the sync port. Must be run as Administrator
REM (right-click - Run as administrator).
netsh advfirewall firewall add rule name="POS LAN Sync (TCP 4242)" dir=in action=allow protocol=TCP localport=4242
if %errorlevel%==0 echo Firewall rule added. Other terminals can now connect.
if %errorlevel% neq 0 echo Failed - run this file as administrator.
pause
