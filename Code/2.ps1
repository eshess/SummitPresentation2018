#Imaging an SD card using (im)pure PowerShell

#Introducing PoshberryPi on PowerShellGallery
Install-Module PoshberryPi
Import-Module PoshberryPi

Write-PiImage -TargetVolume D -FileName "C:\RaspberryPi\2018-03-13-raspbian-stretch-lite.img"


#Native class load
try { [Posh.DiskWriter.Win32DiskAccess] | Out-Null } 
catch { Add-Type -Path "$PSScriptRoot\classes\Win32DiskAccess.cs" }

#Variable initialization and file validation
$Completed = $false
$dtStart = (Get-Date)
if((Test-Path $FileName) -eq $false)
{
    Write-Error "$FileName doesn't exist"
    return $Completed
}
$TargetVolume = Format-DriveLetter $TargetVolume

#Validate we're not targeting the system drive and the drive we're targeting is empty
if($TargetVolume -eq $ENV:SystemDrive) {
    Write-Error "System Drive cannot be used as source"
    return $Completed
} elseif ((Get-ChildItem $TargetVolume).Count -gt 0) {
    Write-Error "Target volume is not empty. Use diskpart to clean and reformat the target partition to FAT32."
    return $Completed
} else {
    $DiskAccess = Get-DiskAccess -TargetVolume $TargetVolume
}

#Validate disk access is operational
if($DiskAccess) {
    #Get drive size and open the physical drive
    $PhysicalDrive = Get-PhysicalDrive -TargetVolume $TargetVolume
    if($PhysicalDrive){
        $physicalHandle = Get-DiskHandle -DiskAccess $DiskAccess -PhysicalDrive $PhysicalDrive.DeviceID
    }
}else {
    return $Completed
}

#if($physicalHandle)
#Initialize buffers, streams, and readers
[console]::TreatControlCAsInput = $true
$maxBufferSize = 1048576
$buffer = [System.Array]::CreateInstance([Byte],$maxBufferSize)
[long]$offset = 0;
$fileLength = ([System.Io.FileInfo]::new($fileName)).Length
$basefs = [System.Io.FileStream]::new($fileName, [System.Io.FileMode]::Open,[System.Io.FileAccess]::Read)
$bufferOffset = 0;
$BinanaryReader = [System.IO.BinaryReader]::new($basefs)


while ($offset -lt $fileLength -and !$IsCancelling)
{
    #Check for Ctrl-C and break if found
    if ([console]::KeyAvailable) {
        $key = [system.console]::readkey($true)
        if (($key.modifiers -band [consolemodifiers]"control") -and ($key.key -eq "C")) {
            $IsCancelling = $true
            break
        }
    }

    #Fill buffer from file bytes
    [int]$readBytes = 0
    do
    {
        $readBytes = $BinanaryReader.Read($buffer, $bufferOffset, $buffer.Length - $bufferOffset)
        $bufferOffset += $readBytes
    } while ($bufferOffset -lt $maxBufferSize -and $readBytes -ne 0)

    [int]$wroteBytes = 0
    $bytesToWrite = $bufferOffset;
    $trailingBytes = 0;

    #Assume that the underlying physical drive will at least accept powers of two!
    if(Get-IsPowerOfTwo $bufferOffset)
    {
        #Find highest bit (32-bit max)
        $highBit = 31;
        for (; (($bufferOffset -band (1 -shl $highBit)) -eq 0) -and $highBit -ge 0; $highBit--){}

        #Work out trailing bytes after last power of two
        $lastPowerOf2 = 1 -shl $highBit;

        $bytesToWrite = $lastPowerOf2;
        $trailingBytes = $bufferOffset - $lastPowerOf2;
    }

    if ($DiskAccess.Write($buffer, $bytesToWrite, [ref]$wroteBytes) -lt 0)
    {
        Write-Error "Null disk handle"
        return $Completed
    }

    if ($wroteBytes -ne $bytesToWrite)
    {
        Write-Error "Error writing data to drive - past EOF?"
        return $Completed
    }

    #Move trailing bytes up
    if ($trailingBytes -gt 0)
    {
        $Buffer.BlockCopy($buffer, $bufferOffset - $trailingBytes, $buffer, 0, $trailingBytes);
        $bufferOffset = $trailingBytes;
    }
    else
    {
        $bufferOffset = 0;
    }
    $offset += $wroteBytes;

    #Progress report
    $percentDone = [int](100 * $offset / $fileLength);
    $tsElapsed = (Get-Date) - $dtStart
    $bytesPerSec = $offset / $tsElapsed.TotalSeconds;
    Write-Progress -Activity "Writing to Disk" -Status "Writing at $bytesPerSec" -PercentComplete $percentDone
}


#Release disk and revery Control C changes
$DiskAccess.Close()
$DiskAccess.UnlockDrive()
if(-not $IsCancelling) {
    $Completed = $true
    $tstotalTime = (Get-Date) - $dtStart
    Write-Verbose "All Done - Wrote $offset bytes. Elapsed time $($tstotalTime.ToString("dd\.hh\:mm\:ss"))"
} else {
    Write-Output "Imaging was terminated early. Please clean and reformat the target volume before trying again."
}
[console]::TreatControlCAsInput = $false
return $completed