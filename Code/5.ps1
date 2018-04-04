#Extra bits

$Procs = Invoke-PiCommand -Computername "192.168.1.1" -Command "Get-Process | where Name -eq 'pwsh'"

#Setup your PowerShell TCP server to open at runtime
#Open crontab (select 2 to use nano to edit)
crontab -e 

#Add this line to the end of the file
@reboot sudo ~/powershell/pwsh -noe -noni -Command "& {Start-PiServer -verbose}"
