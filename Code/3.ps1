#Creating a headless Pi at first boot with an encrypted PSK

#Enable SSH by creating an empty file in the boot partition called SSH

Enable-PiSSH -TargetVolume D

#Enable Wifi by creating an appropriately
#configured wpa_supplicant.conf file in the boot partition

Enable-PiWifi -TargetVolume D -WifiCredential (Get-Credential) -EncryptPSK

#PSK Encrpytion in linux:
wpa_passphrase RaspberryPifi


#PSK Encryption in .NET:
$Salt = [System.Text.Encoding]::ASCII.GetBytes("RaspberryPifi")

#Initializes a new instance of the Rfc2898DeriveBytes class 
#using a password, a salt, and number of iterations to derive the key.
$rfc = [System.Security.Cryptography.Rfc2898DeriveBytes]::New("HotDogs99",$Salt,4096)

#Returns the pseudo-random key for this object with 
#the number of pseudo-random key bytes to generate as your parameter
Write-Output (Convert-ByteArrayToHexString -ByteArray $rfc.GetBytes(32) -Delimiter "").ToLower()

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