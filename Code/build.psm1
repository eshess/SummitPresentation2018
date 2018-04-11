# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.


#Environment data is loaded
function Start-PSBuild {

    [string]$Runtime = "linux-arm"
    Write-Log "Cleaning your working directory. You can also do it with 'git clean -fdX'"
    Push-Location $PSScriptRoot
    try {
        git clean -fdX
        # Extra cleaning is required to delete the CMake temporary files.
        # These are not cleaned when using "X" and cause CMake to retain state, leading to
        # mis-configured environment issues when switching between x86 and x64 compilation
        # environments.
        git clean -fdx .\src\powershell-native
    } finally {
        Pop-Location
    }
    # create the telemetry flag file
    $null = new-item -force -type file "$psscriptroot/DELETE_ME_TO_DISABLE_CONSOLEHOST_TELEMETRY"

    # Add .NET CLI tools to PATH
    Find-Dotnet

    # Verify we have .NET SDK in place to do the build, and abort if the precheck failed
    $precheck = precheck 'dotnet' "Build dependency 'dotnet' not found in PATH. Run Start-PSBootstrap. Also see: https://dotnet.github.io/getting-started/"
    if (-not $precheck) {
        return
    }

    # Verify if the dotnet in-use is the required version
    #<code omitted>
    
    # Add .NET CLI tools to PATH
    Find-Dotnet

    $Configuration = "Linux"
    $PowerShellDir = "powershell-unix"
    $Top = [IO.Path]::Combine($PSScriptRoot, "src", $PowerShellDir)
    Write-Verbose "Top project directory is $Top"
    $Framework = "netcoreapp2.0"
    $Runtime = "linux-x64"
    $Executable = "pwsh"
    $Output = [IO.Path]::Combine($Top, "bin", $Configuration, $Framework, $Runtime, "publish", $Executable)
    $RootInfo = @{RepoPath = $PSScriptRoot}


    # setup arguments
    $Arguments = @("publish","--no-restore","/property:GenerateFullPaths=true")

    $Arguments += "--configuration", $Options.Configuration
    $Arguments += "--framework", $Options.Framework

    # handle Restore
    Restore-PSPackage -Options $Options -Force:$Restore

    # handle ResGen
    # Heuristic to run ResGen on the fresh machine
    if ($ResGen -or -not (Test-Path "$PSScriptRoot/src/Microsoft.PowerShell.ConsoleHost/gen")) {
        Write-Log "Run ResGen (generating C# bindings for resx files)"
        # Add .NET CLI tools to PATH
        Find-Dotnet

        Push-Location "$PSScriptRoot/src/ResGen"
        try {
            Start-NativeExecution { dotnet run } | Write-Verbose
        } finally {
            Pop-Location
        }
    }

    # Handle TypeGen
    # .inc file name must be different for Windows and Linux to allow build on Windows and WSL.
    $incFileName = "powershell_$($Options.Runtime).inc"
    if ($TypeGen -or -not (Test-Path "$PSScriptRoot/src/TypeCatalogGen/$incFileName")) {
        Write-Log "Run TypeGen (generating CorePsTypeCatalog.cs)"
        Start-TypeGen -IncFileName $incFileName
    }

    # Get the folder path where pwsh.exe is located.
    $publishPath = Split-Path $Options.Output -Parent
    # Relative paths do not work well if cwd is not changed to project
    Push-Location $Options.Top
    Write-Log "Run dotnet $Arguments from $pwd"
    Start-NativeExecution { dotnet $Arguments }

    Write-Log "PowerShell output: $($Options.Output)"
    Pop-Location

    # publish netcoreapp2.0 reference assemblies
    Push-Location "$PSScriptRoot/src/TypeCatalogGen"
    $refAssemblies = Get-Content -Path $incFileName | Where-Object { $_ -like "*microsoft.netcore.app*" } | ForEach-Object { $_.TrimEnd(';') }
    $refDestFolder = Join-Path -Path $publishPath -ChildPath "ref"

    New-Item -Path $refDestFolder -ItemType Directory -Force -ErrorAction Stop > $null
    Copy-Item -Path $refAssemblies -Destination $refDestFolder -Force -ErrorAction Stop
    Pop-Location
}

function Start-PSBootstrap {
    Write-Log "Installing PowerShell build dependencies"

    Push-Location $PSScriptRoot/tools
    # This allows sudo install to be optional; needed when running in containers / as root
    # Note that when it is null, Invoke-Expression (but not &) must be used to interpolate properly
    $sudo = if (!$NoSudo) { "sudo" }
    # Update googletest submodule for linux native cmake
    Push-Location $PSScriptRoot
    $Submodule = "$PSScriptRoot/src/libpsl-native/test/googletest"
    Remove-Item -Path $Submodule -Recurse -Force -ErrorAction SilentlyContinue
    git submodule --quiet update --init -- $submodule
    Pop-Location


    # Install ours and .NET's dependencies
    $Deps = @()
    # Build tools
    $Deps += "curl", "g++", "cmake", "make"

    if ($BuildLinuxArm) {
        $Deps += "gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"
    }

    # .NET Core required runtime libraries
    $Deps += "libunwind8"
    $Deps += "libicu55"

    # Install dependencies
    # change the fontend from apt-get to noninteractive
    $originalDebianFrontEnd=$env:DEBIAN_FRONTEND
    $env:DEBIAN_FRONTEND='noninteractive'
        Start-NativeExecution {
        Invoke-Expression "$sudo apt-get update -qq"
        Invoke-Expression "$sudo apt-get install -y -qq $Deps"
    }
    $env:DEBIAN_FRONTEND=$originalDebianFrontEnd
    # Try to locate dotnet-SDK before installing it
    Find-Dotnet

    # Install dotnet-SDK
    $dotNetExists = precheck 'dotnet' $null
    $dotNetVersion = [string]::Empty
    if($dotNetExists) {
        $dotNetVersion = (dotnet --version)
    }

    $DotnetArguments = @{ Channel=$Channel; Version=$Version; NoSudo=$NoSudo }
    $Channel = $dotnetCLIChannel
    $Version = $dotnetCLIRequiredVersion

    $obtainUrl = "https://raw.githubusercontent.com/dotnet/cli/master/scripts/obtain"
    $installScript = "dotnet-install.sh"
    Start-NativeExecution {
        curl -sO $obtainUrl/$installScript
        bash ./$installScript -c $Channel -v $Version
    }
    Pop-Location
}


function Start-TypeGen
{
    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        $IncFileName = 'powershell.inc'
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    $GetDependenciesTargetPath = "$PSScriptRoot/src/Microsoft.PowerShell.SDK/obj/Microsoft.PowerShell.SDK.csproj.TypeCatalog.targets"
    $GetDependenciesTargetValue = @'
<Project>
    <Target Name="_GetDependencies"
            DependsOnTargets="ResolveAssemblyReferencesDesignTime">
        <ItemGroup>
            <_RefAssemblyPath Include="%(_ReferencesFromRAR.ResolvedPath)%3B" Condition=" '%(_ReferencesFromRAR.Type)' == 'assembly' And '%(_ReferencesFromRAR.PackageName)' != 'Microsoft.Management.Infrastructure' " />
        </ItemGroup>
        <WriteLinesToFile File="$(_DependencyFile)" Lines="@(_RefAssemblyPath)" Overwrite="true" />
    </Target>
</Project>
'@
    Set-Content -Path $GetDependenciesTargetPath -Value $GetDependenciesTargetValue -Force -Encoding Ascii

    Push-Location "$PSScriptRoot/src/Microsoft.PowerShell.SDK"
    try {
        $ps_inc_file = "$PSScriptRoot/src/TypeCatalogGen/$IncFileName"
        dotnet msbuild .\Microsoft.PowerShell.SDK.csproj /t:_GetDependencies "/property:DesignTimeBuild=true;_DependencyFile=$ps_inc_file" /nologo
    } finally {
        Pop-Location
    }

    Push-Location "$PSScriptRoot/src/TypeCatalogGen"
    try {
        dotnet run ../System.Management.Automation/CoreCLR/CorePsTypeCatalog.cs $IncFileName
    } finally {
        Pop-Location
    }
}
