#Creating a headless Pi at first boot with an encrypted PSK

#Enable SSH by creating an empty file in the boot partition called SSH

Enable-PiSSH -TargetVolume D

#Enable Wifi by creating an appropriately
#configured wpa_supplicant.conf file in the boot partition

Enable-PiWifi -TargetVolume D -WifiCredential (Get-Credential)

#Under the hood

#PSK Encryption in .NET:
$Salt = [System.Text.Encoding]::ASCII.GetBytes("RaspberryPifi")
$rfc = [System.Security.Cryptography.Rfc2898DeriveBytes]::New("HotDogs99",$Salt,4096)
Write-Output (Convert-ByteArrayToHexString -ByteArray $rfc.GetBytes(32) -Delimiter "").ToLower()

#PSK Encrpytion in linux:
wpa_passphrase RaspberryPifi


#File Contents:
$Output = @"
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$CountryCode

network={
    ssid="$SSID"
    psk=$PSK
    key_mgmt=$KeyMgmt
}
"@

#Export to ascii format with linux line endings
$Output.Replace("`r`n","`n") | Out-File "$TargetVolume\wpa_supplicant.conf" -Encoding ascii