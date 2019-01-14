param (
    # Also import the associated OSUpgrade package
    [switch]
    $ImportOSUpgrade = $false,
    # Import OSMedia instead of OSBuild
    [switch]
    $ImportOSMedia = $false,
    # Upgrade an existing Image and (optionally) Upgrade Package
    [switch]
    $UseExistingPackages = $false
)

<#	
	.NOTES
	===========================================================================
	 Created on:   	1/10/2019
	 Author:		Andrew Jimenez (asjimene) - https://github.com/asjimene/
	 Filename:     	Import-OSBuild.ps1
	===========================================================================
	.DESCRIPTION
        ## OSBuilder Import Tool
        The purpose of this tool is to import OSBuilds and OSMedia created using David Segura's OSBuilder module into SCCM. It's primary functions are as follows:
        1. Copy the OSBuild/OSMedia into the correct content shares (wim file and optionally OS Upgrade Packages)
        2. Import the OSBuild/OSMedia into SCCM Operating System Images (Optionally import OS Upgrade Package)
        3. Distribute Content to a specified Distribution Point Group

        # Import an OSBuild wim file only
        `.\Import-OSBuild.ps1`

        # Import an OSBuild wim file and the cooresponding OS Upgrade Package
        `.\Import-OSBuild.ps1 -ImportOSUpgrade`

        # Import an OSMedia wim file and the cooresponding OS Upgrade Package
        `.\Import-OSBuild -Import-OSMedia -ImportOSUpgrade`

        # Import an OSBuild, but do not create a new wim on the content share, instead update an exising wim
        `.\Import-OSBuild -UseExistingPackages`

        # Import an OSBuild wim file, and the cooresponding OS Upgrade Package but use an exising wim and Upgrade Package
        `.\Import-OSBuild -UseExistingPackages -ImportOSUpgrade`
#>

## Global Variables

# OSBuilder Variables
$Global:OSBuildPath = "C:\OSBuilder"

# SCCM Variables
$Global:ContentShare = "\\Path\to\Content\share"
$Global:OSUpgradeContentShare = "\\Path\to\OSUpgrades\share"
$Global:SCCMSite = "SITE:"
$Global:PreferredDistributionLoc = "PreferredGroupName" #Must be a distribution point group at this time

# Logging Variables
$Global:LogPath = "$PSScriptRoot\OSBuilder-Import.log"
$Global:MaxLogSize = 1000kb


## Functions

function Add-LogContent {
	param
	(
		[parameter(Mandatory = $false)]
		[switch]$Load,
		[parameter(Mandatory = $true)]
		$Content
	)
	if ($Load) {
		if ((Get-Item $LogPath -ErrorAction SilentlyContinue).length -gt $MaxLogSize) {
			Write-Output "$(Get-Date -Format G) - $Content" > $LogPath
		}
		else {
			Write-Output "$(Get-Date -Format G) - $Content" >> $LogPath
		}
	}
	else {
		Write-Output "$(Get-Date -Format G) - $Content" >> $LogPath
	}
}

function copy-OSBuilderObject {
    param (
        [ValidateSet('Image','UpgradePackage')][string]$Type,
        [string]$name,
        [string]$source,
        [string]$destination
    )
    If ($Type -eq "Image"){
        # Copy the selected install.wim to the ContentShare using the build name
        Add-LogContent "Attempting to Copy $source to $destination"
        try {
            Copy-Item -Path $source -Destination $destination -Force
            Add-LogContent "Copy Completed Successfully"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Add-LogContent "ERROR: Copying $source to $destination failed! Skipping import for $name"
            Add-LogContent "ERROR: $ErrorMessage"
        }
    } 
    Else {
            # Copy the selected install.wim to the ContentShare using the build name
            Add-LogContent "Attempting to Copy OS Upgrade Files from $($Build.FullName)\OS to $osUpgradePath"
            try {
                Copy-Item -Path "$($Build.FullName)\OS" -Destination "$osUpgradePath" -Recurse -Force
                Add-LogContent "Copy Completed Successfully"
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                Add-LogContent "ERROR: Copying $($Build.FullName) to $osUpgradePath failed! Skipping import for $($Build.Name)"
                Add-LogContent "ERROR: $ErrorMessage"
            }
    }
}

function import-OSBuilderObject {
    param (
        [ValidateSet('Image','UpgradePackage')][string]$Type,
        [string]$Name,
        [string]$Path,
        [string]$version,
        [string]$Description
    )

    # Import the Copied wim into SCCM
    Add-LogContent "Importing $Name"
    Push-Location
    Set-Location $Global:SCCMSite
    try {
        if ($Type -eq "Image"){
            New-CMOperatingSystemImage -Name "$Name" -Path "$Path" -Version "$version" -Description "$Description"
            Add-LogContent "Successfully Imported the Operating System as $Name"
        }
        Else {
            New-CMOperatingSystemInstaller -Name "$Name" -Path "$Path" -Version "$version" -Description "$Description"
            Add-LogContent "Successfully Imported the Operating System as $Name"
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Add-LogContent "ERROR: Importing wim into SCCM from $Path failed! Skipping import for $Name"
        Add-LogContent "ERROR: $ErrorMessage"
    }
    Pop-Location
}

function Update-OSContent {
    param (
        [ValidateSet('Image','UpgradePackage')][string]$Type,
        [string]$Name
    )

    # Distribute the new OSImage to the Specified Distribution Point Group
    Add-LogContent "Distributing $Name to $($Global:PreferredDistributionLoc)"
    Push-Location
    Set-Location $Global:SCCMSite
    if ($updateExistingImage){
        try {
            if ($Type -eq "Image"){
                Invoke-CMContentRedistribution -InputObject $(Get-CMOperatingSystemImage -Name "$Name") -DistributionPointGroupName $Global:PreferredDistributionLoc
                Add-LogContent "Successfully Completed Copy, and Re-Distribution of OSBuild: $Name"
            }
            else {
                Invoke-CMContentRedistribution -InputObject $(Get-CMOperatingSystemInstaller -Name "$Name") -DistributionPointGroupName $Global:PreferredDistributionLoc
                Add-LogContent "Successfully Completed Copy, and Re-Distribution of OSUpgrade: $Name"
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Add-LogContent "ERROR: Distributing OSImage $Name Failed!"
            Add-LogContent "ERROR: $ErrorMessage"
        }
    } 
    else {
        try {
            if ($Type -eq "Image"){
                Start-CMContentDistribution -OperatingSystemImageName "$Name" -DistributionPointGroupName $Global:PreferredDistributionLoc
                Add-LogContent "Successfully Completed Copy, Import, and Distribution of OSBuild: $Name"
            }
            else {
                Start-CMContentDistribution -OperatingSystemInstallerName "$Name" -DistributionPointGroupName $Global:PreferredDistributionLoc
                Add-LogContent "Successfully Completed Copy, Import, and Distribution of OSUpgrade: $Name"
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Add-LogContent "ERROR: Distributing OSImage $Name Failed!"
            Add-LogContent "ERROR: $ErrorMessage"
        }
    }
    Pop-Location
}

## Main

Add-LogContent -Content "Starting Import-OSBuild" -Load

# Import ConfigurationManager Cmdlets
if (-not (Get-Module ConfigurationManager)) {
    try {
        Add-LogContent "Importing ConfigurationManager Module"
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1) -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    } 
    catch {
        $ErrorMessage = $_.Exception.Message
		Add-LogContent "ERROR: Importing ConfigurationManager Module Failed! Exiting!"
        Add-LogContent "ERROR: $ErrorMessage"
        Exit
    }
}

# Import OSBuilder Module Cmdlets
if (-not (Get-Module OSBuilder)) {
    try {
        Add-LogContent "Importing ConfigurationManager Module"
        Import-Module OSBuilder
    } 
    catch {
        $ErrorMessage = $_.Exception.Message
		Add-LogContent "ERROR: Importing OSBuilder Module Failed! Exiting!"
        Add-LogContent "ERROR: $ErrorMessage"
        Exit
    }
}

# Check OSBuilder Version
if ((Get-Module OSBuilder).Version -lt "19.1.11.0") { 
    Write-Host "OSBuilder Version is out-of-date, please upgrade to the latest version"
    Add-LogContent "OSBuilder Version is out-of-date, please upgrade to the latest version"
    Exit
}

# Search the OSBuilder Path for new Wim Files to import, loop if none are selected
$selectedBuilds = $null
while ([System.String]::IsNullOrEmpty($selectedBuilds)) {
    if ($ImportOSMedia){
        $selectedBuilds = Get-OSMedia -GridView
        Add-LogContent "Selected the Following Media to import: $($SelectedBuilds.Name -join " ; ")"
    } 
    Else {
        $selectedBuilds = Get-OSBuilds -GridView
        Add-LogContent "Selected the Following Builds to import: $($SelectedBuilds.Name -join " ; ")"
    }
}

if ($UseExistingPackages){
    # Get the OSImage name and the OSUpgradePackage name from SCCM
    Push-Location
    Set-Location $Global:SCCMSite
    $OSImageSelection = Get-CMOperatingSystemImage | Select-Object Name,ImageOSVersion,SourceDate,PkgSourcePath | Out-GridView -Title "Select the OS Image to Upgrade" -OutputMode Single
    $Global:ContentShare = $OSImageSelection.PkgSourcePath
    $OSUpgradeSelection = Get-CMOperatingSystemInstaller | Select-Object Name,ImageOSVersion,SourceDate,PkgSourcePath | Out-Gridview -Title "Select the Upgrade Package to Update" -OutputMode Single
    $Global:OSUpgradeContentShare = $OSUpgradeSelection.PkgSourcePath
    Pop-Location
}

ForEach ($Build in $SelectedBuilds){
    # Set Build Variables
    $BuildName = $Build.Name
    $BuildVersion = $Build.UBR
    $BuildDescription = $Build.Imagename + " Version $BuildVersion - Imported from OSBuilder on: $(Get-Date -Format G)"
    $wimLocation = Join-Path -Path $Build.FullName -ChildPath "OS\sources\install.wim"
    $OSLocation = Join-Path -Path $Build.FullName -ChildPath "OS"

    if ($Global:ContentShare -like "*.wim"){
        Add-LogContent "Specified content location is a wim, will update existing wim, and use existing Upgrade Content Share"
        $updateExistingImage = $true

        $BuildName = $OSImageSelection.Name
        $destinationPath = "$Global:ContentShare"
        $osUpgradePath = "$Global:OSUpgradeContentShare"

        # Backup the Existing image File (as long as it exists)
        try {
            Move-Item -path "$destinationPath" -Destination $destinationPath.Replace(".wim","-$((Get-Date).ToString(`"yyyyMMdd`")).wim")
            Add-LogContent "Backed up: $destinationPath to: $($destinationPath.Replace(".wim","-$((Get-Date).ToString(`"yyyyMMdd`")).wim"))"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Add-LogContent "ERROR: Unable to backup $destinationPath"
            Add-LogContent "ERROR: $ErrorMessage"
        }

        # Backup the Existing Upgrade Content Path
        try {
            Move-Item -path "$OSUpgradePath" -Destination "$OSUpgradePath-$((Get-Date).ToString(`"yyyyMMdd`"))"
            Add-LogContent "Backed Up $OSUpgradePath to: $OSUpgradePath-$((Get-Date).ToString(`"yyyyMMdd`"))"
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Add-LogContent "ERROR: Unable to backup $destinationPath"
            Add-LogContent "ERROR: $ErrorMessage"
        }
    } else {
        $destinationPath = "$Global:ContentShare\$($Build.Name).wim"
        $osUpgradePath = "$Global:OSUpgradeContentShare\$($Build.Name)"
    }

    if ((Test-Path $wimLocation) -and (-not (Test-Path $destinationPath)) -and (-not $updateExistingImage)){
        Add-LogContent "Pre-Check Complete - Import can continue"
        
        # Copy the selected install.wim to the ContentShare using the build name
        copy-OSBuilderObject -Type Image -name $BuildName -source $wimLocation -destination $destinationPath

        # Import the newly Copied wim
        import-OSBuilderObject -Type Image -Name $BuildName -Path $destinationPath -version $BuildVersion -Description $BuildDescription
        
        # Distribute the new OSImage to the Specified Distribution Point Group
        Update-OSContent -Type Image -Name $BuildName

    }
    elseif ((Test-Path $OSLocation) -and $updateExistingImage) {
        Add-LogContent "Pre-Check Complete - Updating Existing OSUpgrade Item - Import can continue"

        # Copy the install.wim to the same location as the original
        copy-OSBuilderObject -Type UpgradePackage -name $BuildName -source $OSLocation -destination $osUpgradePath

        # Redistribute the Content
        Update-OSContent -Type UpgradePackage -Name $BuildName
    } 
    else {
        if (-not (Test-Path $wimLocation)){
            Add-LogContent "ERROR: install.wim not found at $wimLocation - Skipping import for $($Build.Name)"
        }
        if (Test-Path $destinationPath){
            Add-LogContent "ERROR: $destinationPath already exists! Skipping import for $($Build.Name)"
        }
    }

    # Import OSUpgradePackage
    if ($ImportOSUpgrade) {
        if ((Test-Path $OSLocation) -and (-not (Test-Path $osUpgradePath)) -and (-not $updateExistingImage)){
            Add-LogContent "Pre-Check Complete - Creating New OSUpgrade Item - Import can continue"

            # Copy the Upgrade package to the Content Share
            copy-OSBuilderObject -Type UpgradePackage -name $BuildName -source $OSLocation -destination $osUpgradePath

            # Import the OS Upgrade Package
            import-OSBuilderObject -Type UpgradePackage -Name $BuildName -Path $osUpgradePath -version $BuildVersion -Description $BuildDescription

            # Distribute the Content
            Start-Sleep 10 ## Should help with failed content distribution
            Update-OSContent -Type UpgradePackage -Name $BuildName

        }
        elseif ((Test-Path $OSLocation) -and $updateExistingImage) {
            Add-LogContent "Pre-Check Complete - Updating Existing OSUpgrade Item - Import can continue"

            # Copy the Upgrade package to the Content Share
            $OSUpgradeName =$OSUpgradeSelection.Name
            copy-OSBuilderObject -Type UpgradePackage -name $OSUpgradeName -source $OSLocation -destination $osUpgradePath

            # Distribute the Content
            Start-Sleep 10 ## Should help with failed content distribution
            Update-OSContent -Type UpgradePackage -Name $OSUpgradeName
        } 
        Else {
            if (-not (Test-Path $wimLocation)){
                Add-LogContent "ERROR: install.wim not found at $wimLocation - Skipping import for $($Build.Name)"
            }
            if (Test-Path $destinationPath){
                Add-LogContent "ERROR: $osUpgradePath already exists! Skipping import for $($Build.Name)"
            }
        }
    }
}

Add-LogContent "Import-OSBuild has Completed!"