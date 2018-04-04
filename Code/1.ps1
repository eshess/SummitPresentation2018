#Imaging an SD card using (im)pure PowerShell

#Introducing PoshberryPi 0.0.2 on PowerShellGallery
Install-Module PoshberryPi
Import-Module PoshberryPi

Get-Command -Module PoshberryPi

Write-PiImage -TargetVolume D -FileName "C:\RaspberryPi\2018-03-13-raspbian-stretch-lite"

