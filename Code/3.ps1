##Cross-compiling PowerShell core for Raspbian (ie doing it the hard way)

#Build Machine Steps
#Step 1 - Install PowerShell

#Prerequisites: git, curl
# Import the public repository GPG keys
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

# Register the Microsoft Ubuntu repository
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list

# Update the list of products
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell

# Clone PowerShell
git clone --recursive https://github.com/PowerShell/PowerShell

#Build
cd ./PowerShell
pwsh
Import-Module ./build.psm1
Start-PSBootstrap -BuildLinuxArm
Start-PSBuild -Clean -Runtime linux-arm -PSModuleRestore

#Copy to pi
scp -r "$(split-path (Get-PSOutput))/*" pi@yourPi:/home/pi/powershell

#Pi Steps
# Install prerequisites
sudo apt-get install libunwind8

# Run PowerShell

##Install PowerShell the Microsoft Approved way

# Install prerequisites
sudo apt-get install libunwind8

# Grab the latest tar.gz
wget https://github.com/PowerShell/PowerShell/releases/download/v6.0.2/powershell-6.0.2-linux-arm32.tar.gz

# Make folder to put powershell
mkdir ~/powershell

# Unpack the tar.gz file
tar -xvf ./powershell-6.0.0-rc.2-linux-arm32.tar.gz -C ~/powershell