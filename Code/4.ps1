#Using PowerShell core to setup a TCP server for PSRemoting

#On the Raspberry Pi
Install-Module PoshberryPi
Start-PiServer -Verbose

#The code

$Port=1655
#Create the Listener port
$Listener = New-Object System.Net.Sockets.TcpListener -ArgumentList $Port

#Start the listener; opens up port for incoming connections
$Listener.Start()
$Active = $True
While ($Active) {
    #Blocking
    $incomingClient = $Listener.AcceptTcpClient()
    #Let it buffer for a second
    Start-Sleep -Milliseconds 1000

    #Get the data stream from connected client
    $stream = $incomingClient.GetStream()
    $stringBuilder = New-Object Text.StringBuilder
    While ($incomingClient.Connected) {
        #Is there data available to process
        If ($Stream.DataAvailable) {
            Do {
                [byte[]]$byte = New-Object byte[] 1024
                $bytesReceived = $Stream.Read($byte, 0, $byte.Length)
                If ($bytesReceived -gt 0) {
                    [void]$stringBuilder.Append([text.Encoding]::Ascii.GetString($byte[0..($bytesReceived - 1)]))
                }
            } While ($Stream.DataAvailable)
            $string = $stringBuilder.ToString()
            $Data = [scriptblock]::Create($string).Invoke()
            $serialized = [System.Management.Automation.PSSerializer]::Serialize($Data)
            #Resend the Data back to the client
            $bytes  = [text.Encoding]::Ascii.GetBytes($serialized)
            #Send the data back to the client
            $Stream.Write($bytes,0,$bytes.length)
            $Stream.Flush()
            $incomingClient.Close()
        }
        Start-Sleep -Milliseconds 1000
    }
    [void]$stringBuilder.Clear()
}

#On your PC

Invoke-PiCommand -Computername "192.168.43.219" -Command "Write-Output 'Hello World'"

#The code

$Computername = "192.168.1.1"
$Port = 1655
$Command = "Write-Output 'Hello World'"
$Endpoint = new-object System.Net.IPEndpoint ([ipaddress]::any,$SourcePort)
$TcpClient = [Net.Sockets.TCPClient]$endpoint
$TcpClient.Connect($Computername,$Port)
$ServerStream = $TcpClient.GetStream()
#Make the recieve buffer a little larger
$TcpClient.ReceiveBufferSize = 1MB
##Client
$data = [text.Encoding]::Ascii.GetBytes($Command)
#Send Data
$ServerStream.Write($data,0,$data.length)
$ServerStream.Flush()
#Wait for Response
$stringBuilder = New-Object Text.StringBuilder
$Waiting = $True
While ($Waiting) {
    While ($TcpClient.available -gt 0) {
        #Process return bytes
        [byte[]]$inStream = New-Object byte[] $TcpClient.Available
        $buffSize = $TcpClient.Available
        $return = $ServerStream.Read($inStream, 0, $buffSize)
        [void]$stringBuilder.Append([System.Text.Encoding]::ASCII.GetString($inStream[0..($return-1)]))
        Start-Sleep -Seconds 1
    }
    If ($stringBuilder.length -gt 0) {
        $returnedData = [System.Management.Automation.PSSerializer]::DeSerialize($stringBuilder.ToString())
        Remove-Variable String -ErrorAction SilentlyContinue
        $Waiting = $False
    }
}
Write-Output $returnedData
If ($ServerStream) {$ServerStream.Dispose()}
If ($TcpClient) {$TcpClient.Dispose()}


$Output = Invoke-PiCommand -Computername "192.168.43.219" -Command "Get-Process pwsh"


Invoke-PiCommand -Computername "192.168.43.219" -Command "exit"