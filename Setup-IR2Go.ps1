<#
.SYNOPSIS
Setup script for the ACSC IR2Go environment. 

.DESCRIPTION
From within a new Windows installation on a USB drive, download and run this script.
The script downloads commonly used Incident Response tools and configures the Windows environment ready.
Further setup is required for tool locations, etc

.INPUTS
<None>

.OUTPUTS
<None> - Script output is sent to window

.EXAMPLE
Run the script
./Setup-IR2Go.ps1

.NOTES
Author: Dean B <dean.bird@cert.gov.au>
Version: 1.5
Modified Date: 16th July 2018

.LINK
https://github.com/certau/ir2go

#>
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

##Variables - all directories have no trailing slash
#Sizes are in bytes please
$win_part_size = 30000000000                            ## 30GB
$tools_drive_letter = "C"                               ## Drive letter for tools partition
$linux_part_size = 20000000000                          ## 20GB
$linux_drive_letter = "L"                               ## Drive letter for linux partition
$working_dir = "C:\IR2Go" 								## Working directory for files and scripts
$script_check_file = "$working_dir\acscrocks.txt"       ## Check file to see if script has run previously.
$tools_dir = "$tools_drive_letter:\Tools\Acquisition\Windows"				## Tools location 
$general_dir = "$tools_drive_letter:\Tools\General"						## General items location
$wallpaperURL = "General/background.png"				## URL of wallpaper
$pdfviewerURL = "General/SumatraPDF.exe"				##SumatraPDF installer

##Menu Selections (X = selected)
$setup_tdrive = "X" 
$setup_ldrive = " " 
$setup_tools = "X" 
$setup_wallpaper = "X" 
$setup_removeapps = "X" 
$setup_enablebitlocker = "X" 

## Remove Script Locations - Arrays of URL of Script, Script description
$reclaimWindows = @("https://gist.githubusercontent.com/alirobe/7f3b34ad89a159e6daa1/raw/2e5e6f244af9189b81f01873c94b350ee906f8bb/reclaimWindows10.ps1", "Reclaim Windows from GITHUB")

## Tools to be downloaded
$acquisitionTools = @("Acquisition/Windows/Belkasoft Acquisition Tool.zip", 
					"Acquisition/Windows/Belkasoft RAM Capture.zip",
					"Acquisition/Windows/Comae Toolkit 3.0.zip",
					"Acquisition/Windows/FTK Imager Lite 3.1.1.zip",
					"Acquisition/Windows/Redline.zip",
					"Acquisition/Windows/WiresharkPortable.zip",
					"Acquisition/Windows/Guides.zip",
                    "Investigation/Windows/xways.zip")

#additional Tools 
$menuEXE = "Menu/PStart.exe"
#$menuConfig = "Configs/PStart.xml" ##S3 Location
$menuConfig = "https://raw.githubusercontent.com/certau/ir2go/master/Config/PStart.xml"

$linuxURL = "http://mirror.exetel.com.au/pub/ubuntu/xubuntu-releases/16.04/release/xubuntu-16.04.1-desktop-amd64.iso"

### Currently Unused Variables
#$awstoolsURL = "http://sdk-for-net.amazonwebservices.com/latest/AWSToolsAndSDKForNet.msi" ##AWS Tools for Powershell 

## Menu (pStart)

###############################################
## FUNCTIONS
###############################################

## File Name Extractor
###########
Function getFileName($url){
	$fileName = $url.substring($url.LastIndexOf("/")+1).Replace("%20", " ")

	return $fileName
}

## Download a file to the working directory.
###########
Function downloadFile {
	param([string]$surl, [string]$dest)
	#Work out the filename
	$tmpFile = getFileName($surl)	

	Write-Host ""
	Write-Host ("Downloading " + $tmpFile)
	#$WebClient = New-Object System.net.WebClient
	#$WebClient.DownloadFile($surl, "$working_dir\$tmpFile")
	Invoke-WebRequest -Uri $surl -OutFile "$dest\$tmpFile"
}

## Download a file to the working directory.
###########
Function downloadFileS3 {
	param([string]$s3url, [string]$dest)
	#Work out the filename
	$tmpFile = getFileName($s3url)	

	Write-Host ""
	Write-Host ("Downloading " + $tmpFile)
	Read-S3Object -BucketName "$aws_bucket_name" -Key "$s3url" -File "$dest\$tmpFile"
}

## Unzip function from https://stackoverflow.com/questions/27768303/how-to-unzip-a-file-in-powershell
###########
function Unzip {
    param([string]$zipfile, [string]$outpath)

    Write-Host ""
	Write-Host ("Unzipping " + $zipfile)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

## Download and run a script from the internet
###########
Function remoteScript($surl, $sdesc) {
	#Work out the filename
	$tmpFile = getFileName($surl)	
	
	#Download the file
	downloadFile $surl $working_dir
	
	Write-Host ""
	Write-Host "Running Script..."
	Invoke-Expression $working_dir/$tmpFile

	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Script $tmpFile has been downloaded and run. It has a description of $sdesc" 
}

## General Maintenance
###########
Function GeneralSetup() {
	Write-Host ""
	Write-Host "General Setup"
	
	Write-Host ""
	Write-Host "Setting system sound profile"
	Set-ItemProperty -path 'HKCU:\AppEvents\Schemes\' -name "(Default)" -value ".None"
	
	Write-Host ""
	Write-Host "Disabling Auto Mount"
	New-Item -path 'HKLM:\SYSTEM\CurrentControlSet\Servies\MountMgr\' -name "NoAutoMount" -value "1" -FORCE

	Write-Host ""
	Write-Host "Setting the timezone to UTC"
	Set-TimeZone "Coordinated Universal Time"
	
	Write-Host ""
	Write-Host "Setting the Power Plan"
	$p = gwmi -NS root\cimv2\power -Class win32_PowerPlan -Filter "ElementName = 'High performance'"
	$p.Activate()
	
	#Make the directory for the scripts if required.
	New-Item -ItemType directory -Path $working_dir
	
	#Disable Pagefile - From https://stackoverflow.com/questions/37813441/powershell-script-to-set-the-size-of-pagefile-sys 
	$computersys = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges;
	$computersys.AutomaticManagedPagefile = $False;
	$computersys.Put();
	$pagefile = Get-WmiObject -Query "Select * From Win32_PageFileSetting Where Name like '%pagefile.sys'";
	$pagefile.InitialSize = 0;
	$pagefile.MaximumSize = 0;
	$pagefile.Put();
	$pagefile.Delete();

	#Add us as a Source in the application Event Log
	New-EventLog -LogName Application -Source "CERTAU"
	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "General setup script - General setup complete" 
}

## AWS Setup
###########
Function SetupAWS {
	#Import the AWS Powershell module
	if(!(Get-InstalledModule | Where-Object Name -eq AWSPowerShell)){
		Write-Host "Importing AWS Powershell module"
		Install-Package -Name AWSPowerShell -force
	}	

	Write-Host ""
	Write-Host "Setting up AWS Profile"
	Set-AWSCredential -AccessKey $aws_bucket_key -SecretKey $aws_bucket_secret -StoreAs CertAUIR2Go
	Initialize-AWSDefaultConfiguration -ProfileName CertAUIR2Go -Region ap-southeast-2
} ## Setup AWS

## Remove Windows 10 Apps which serve no purpose
###########
Function RemoveWin10Apps {
	Write-Host ""
	Write-Host "Removing Windows 10 Apps..."
	Write-Host "Removing 3D Builder"
	Get-AppxPackage -allusers *3dbuilder* | Remove-AppxPackage
	
	Write-Host "Removing Windows Alarm"
	Get-AppxPackage -allusers *windowsalarms* | Remove-AppxPackage
	
	Write-Host "Removing Windows Calculator"
	Get-AppxPackage -allusers *windowscalculator* | Remove-AppxPackage
	
	Write-Host "Removing Communications Apps"
	Get-AppxPackage -allusers *windowscommunicationsapps* | Remove-AppxPackage
	
	Write-Host "Removing Windows Camera"
	Get-AppxPackage -allusers *windowscamera* | Remove-AppxPackage
	
	Write-Host "Removing Office Hub"
	Get-AppxPackage -allusers *officehub* | Remove-AppxPackage
	
	Write-Host "Removing Skype App"
	Get-AppxPackage -allusers *skypeapp* | Remove-AppxPackage
	
	Write-Host "Removing Get Started"
	Get-AppxPackage -allusers *getstarted* | Remove-AppxPackage
	
	Write-Host "Removing Zune - I mean really, did anyone actually use this?"
	Get-AppxPackage -allusers *zunemusic* | Remove-AppxPackage
	
	Write-Host "Removing Windows Maps"
	Get-AppxPackage -allusers *windowsmaps* | Remove-AppxPackage
	
	Write-Host "Removing Solitare"
	Get-AppxPackage -allusers *solitairecollection* | Remove-AppxPackage
	
	Write-Host "Removing Bing Finance"
	Get-AppxPackage -allusers *bingfinance* | Remove-AppxPackage
	
	Write-Host "Removing Zune Video"
	Get-AppxPackage -allusers *zunevideo* | Remove-AppxPackage
	
	Write-Host "Removing Bing #Fake news"
	Get-AppxPackage -allusers *bingnews* | Remove-AppxPackage
	
	Write-Host "Removing OneNote"
	Get-AppxPackage -allusers *onenote* | Remove-AppxPackage
	
	Write-Host "Removing People"
	Get-AppxPackage -allusers *people* | Remove-AppxPackage
	
	Write-Host "Removing Windows Phone"
	Get-AppxPackage -allusers *windowsphone* | Remove-AppxPackage
	
	Write-Host "Removing Photos"
	Get-AppxPackage -allusers *photos* | Remove-AppxPackage
	
#	Write-Host "Removing Store"
#	Get-AppxPackage -allusers *windowsstore* | Remove-AppxPackage
	
	Write-Host "Removing Bing Sports"
	Get-AppxPackage -allusers *bingsports* | Remove-AppxPackage
	
	Write-Host "Removing Sound Recorder"
	Get-AppxPackage -allusers *soundrecorder* | Remove-AppxPackage
	
	Write-Host "Removing Bing Weather"
	Get-AppxPackage -allusers *bingweather* | Remove-AppxPackage
	
	Write-Host "Removing Xbox App"
	Get-AppxPackage -allusers *xboxapp* | Remove-AppxPackage
	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Removed the default Windows 10 Apps that are not needed" 
}

## Partition Setup
###########
Function SetupPartitions() {
	Write-Host "Partition Setup."

	if(($setup_tdrive -eq "X") -and ($setup_ldrive -eq "X")) {
		Write-Host "Resizing Windows 10 (Current) Partition"
		Resize-Partition -DriveLetter C -Size $win_part_size
	}
	
	if($setup_ldrive -eq "X") {
		Write-Host "Creating space for the Linux Disk"
		$driveNum = (Get-Partition -DriveLetter c).DiskNumber
		New-Partition -DiskNumber $driveNum -Size $linux_part_size -DriveLetter $linux_drive_letter -MbrType FAT32
		Format-Volume -DriveLetter $linux_drive_letter -FileSystem FAT32
	}
	
	if($setup_tdrive -eq "X") {
		Write-Host "Creating the tools partition"
		$driveNum = (Get-Partition -DriveLetter c).DiskNumber
		New-Partition -DiskNumber $driveNum -UseMaximumSize -DriveLetter $tools_drive_letter -MbrType FAT32
		Format-Volume -DriveLetter $tools_drive_letter -FileSystem NTFS
	}
	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Paritions configured" 
}

## Enable Bitlocker
###########
Function EnableBitlocker() {
	Write-Host "Turning on Bitlocker"

	Write-Host ""
	Write-Host "Configuring BitLocker settings"
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "EnableBDEWithNoTPM" -value "1" -FORCE
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "UseAdvancedStartup" -value "1" -FORCE
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "UseTPM" -value "2" -FORCE
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "UseTPMKey" -value "2" -FORCE
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "UseTPMKeyPIN" -value "2" -FORCE
	New-Item -path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE\' -name "UseTPMPIN" -value "2" -FORCE

	if($setup_tdrive -eq "X") {
		Write-Host "Enabling Bitlocker on T Drive"
		##Code here
	}
	
	Write-Host ""
	Write-Host "Enabling Bitlocker on OS Drive"
	
	##OS Drive
	##Request a password
	$os_bl_key = Read-Host -AsSecureString -Prompt 'BitLocker Password (OS Drive)'               ##OS Bitlocker Password

	##Enable BitLocker on drive
	Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes128 Add-BitLockerKeyProtector -Password $os_bl_key -RecoveryKeyPath "$working_dir" -RecoveryKeyProtector


	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Paritions configured" 
}


## Set wallpaper
###########
Function SetWallPaper() {
	Write-Host "Setting wallpaper..."
	
	$tmpName = getFileName($wallpaperURL)
	$wallpaperFile = "$working_dir\$tmpName"
	echo $wallpaperFile
	downloadFileS3 "$wallpaperURL" "$working_dir"

	Set-ItemProperty -path 'HKCU:\Control Panel\Desktop\' -name wallpaper -value $wallpaperFile
	cmd.exe /c "C:\Windows\System32\rundll32.exe user32.dll, UpdatePerUserSystemParameters 1, True"
	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Wallpaper set" 
}

## Get Tools
###########
Function GetTools() {
	#Remove the existing folder if it exists
	if(Test-Path $tools_dir){
		Write-Host "Removing existing tools folder"
		Remove-Item -path "$tools_dir\" -recurse -foreach
	}
	
	#Loop through the tools
	foreach($tool IN $acquisitionTools) {
		downloadFileS3 "$tool" "$working_dir"
		$tmpFile = getFileName($tool)
		
		Unzip "$working_dir\$tmpFile" "$tools_dir"
		
		#Remove the zip file
		Write-Host "Removing $working_dir\$tmpFile"
		Remove-Item -path "$working_dir\$tmpFile" -force
		Write-Host "+-------+-------+-------+-------+-------+"
		Write-Host ""
	} 
	
	#Make the directory for the General files.
	##Run the components
    if(-Not (Test-Path $general_dir){
		New-Item -ItemType directory -Path $general_dir
	}

	#Install Sumartra PDF Viewer
	Write-Host "Installing Samartra PDF Viewer"
	downloadFileS3 "$pdfviewerURL" "$general_dir"
	
	##Install the menu
	downloadFileS3 "$menuEXE" "$general_dir"
	downloadFile "$menuConfig" "$general_dir"
	#Start the menu
	$menuName = getFileName($menuEXE)
	Write-Host "Starting menu...."
	Start-Process -FilePath "$general_dir\$menuName"
	
	#Creating a link to start up the menu on start up
	cmd /c mklink "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\ir2go-menu" "$general_dir\$menuName"
	#Creating a link on the desktop
	cmd /c mklink "%USERPROFILE%\Desktop\IR2Go Menu" "$general_dir\$menuName"
	#Creating a link in the root of T Drive
	#cmd /c mklink "T:\IR2Go Menu" "$general_dir\$menuName"
	
	#write entry in event log
	Write-EventLog -LogName "Application" -Source "CERTAU" -EventID 10 -EntryType Information -Message "Tools downloaded and installed to T Drive" 
}

###################################################################################################
### Start Here
###################################################################################################

Function DisplayMenu() {
	##Introductions
	Clear-Host
	
	Write-Host "-"
	Write-Host "-                 _cc??CCCCCCCCC6c/"
	Write-Host "-               )'        ?CCCCCCCCCcc"
	Write-Host "-           _C'          cCCCCCCCCCCCCC"
	Write-Host "-                        CCCCCCCCCCCCCC?"
	Write-Host "-         c            cCCCCCCCCCCCCC?"
	Write-Host "-       c             cCCCCCCCCCCCC?"
	Write-Host "-      c             C???    )?4CCf                        ]CCf"
	Write-Host "-                  _?                                      ]CCf"
	Write-Host "-     c                           _CCCCCCCCCCf  _jCCCCCCC  ]CCCCCC"
	Write-Host "-                )'              ]CCC?    ]CCf  ]CC?       ]CCf"
	Write-Host "-                                ]CC    ccJ??' ]CCC        ]CCf"
	Write-Host "-               ]f               ]CC    CC[    ]CCC        ]CCf"
	Write-Host "-              ]Cf               ]CCc          ]CCC        ]CCC/"
	Write-Host "-     c       ]CCCf              )4CCCCCCCWCCf ]CCC        ]CCCCCC"
	Write-Host "-     ?      ]CCCCC6               ??????????' )???          )????"
	Write-Host "-      c    ]CCCCCCCCc         _cjc"
	Write-Host "-       cCCCCCCCCCCCCCCCCccccjCCCCCCc            _       ______ __  _       _"
	Write-Host "-        ?CCCCCCCCCCCCCCCWCWCCCCCCCCCCc         /_| /  /(   /  /__)/_| /  //_|"
	Write-Host "-         ?CCCCCCCCCCCCCCCCCCCCCCCCCCCCCc      (  |(__/__) (  / ( (  |(__((  |"
	Write-Host "-           4CCCCCCCCCCCCCCCCCCCCCCCCCCCC?"
	Write-Host "-            )?4CCCCCCCCCCCCCCCCCCCCCC??"
	Write-Host "-               )?4CCCCCCCCCCCCCCCP?"
	Write-Host "-                    ???????????'"
	Write-Host "-"
	Write-Host "################################################"
	Write-Host "## Welcome to the ACSC IR2Go setup Script.    ##"
	Write-Host "################################################"
	Write-Host ""
	Write-Host "There are a few questions to get you started."

	Write-Host "+--------------------------------+-----------------------------------------+"
	Write-Host "1. [$setup_tdrive] Setup T Drive (Tools) and install Tools to T:\ "
	Write-Host "2. [$setup_ldrive] Setup L Drive (Linux) "
	Write-Host "3. [$setup_tools] Install / Update Tools "
	Write-Host "4. [$setup_wallpaper] Install Wallpaper "
	Write-Host "5. [$setup_removeapps] Remove Windows 10 Apps "
	Write-Host ""
	Write-Host "6. [$setup_enablebitlocker] Enable Bitlocker on OS and Tools partition."
	Write-Host ""
	Write-Host "10. Toggle All On"
	Write-Host "11. Toggle All Off"
	Write-Host "Q. Quit"
	Write-Host ""
	Write-Host "Enter. Run Script"
	Write-Host "+--------------------------------+-----------------------------------------+"
} ##DisplayMenu

##Check if running as Admin - If not. Dislay error and exit.
& {
  $wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
  $prp=new-object System.Security.Principal.WindowsPrincipal($wid)
  $adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
  $IsAdmin=$prp.IsInRole($adm)
  if ($IsAdmin -eq $false)
  {
	(get-host).UI.RawUI.Backgroundcolor="DarkRed"
	clear-host
	write-host ""
	write-host ""
	write-host "             _                                      _"
	write-host "        ~0  (_|  . - ' - . _ . - ' - . _ . - ' - . |_)  O"
	write-host "       |(_~|^~~|                                  |~~^|~_)|"
	write-host "       TT/_ T'T                                    T'T _\HH"
	write-host "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
	write-host "Script needs to be run as admin. "
	write-host "Please close this box and re-open as administrator!"
    Read-Host -Prompt "Press enter to exit"
	exit
  }
}

while(($todo -ne "q") -and ($todo -ne "")) {
	DisplayMenu
	$todo = Read-Host -Prompt "Please make a selection"
	switch ($todo) {
		1 {			
			if($setup_tdrive -eq "X") {
				$setup_tdrive = " "	
                $tools_drive_letter = "C" 	
			} else {
				$setup_tdrive = "X"
				$setup_partitions = "X"
                $tools_drive_letter = "T" 
			}
		}
		2 {			
			if($setup_ldrive -eq "X") {
				$setup_ldrive = " "		
			} else {
				$setup_ldrive = "X"
				$setup_partitions = "X"
			}
		}
		3 {			
			if($setup_tools -eq "X") {
				$setup_tools = " "		
			} else {
				$setup_tools = "X"
			}
		}
		4 {			
			if($setup_wallpaper -eq "X") {
				$setup_wallpaper = " "		
			} else {
				$setup_wallpaper = "X"
			}
		}
		5 {			
			if($setup_removeapps -eq "X") {
				$setup_removeapps = " "		
			} else {
				$setup_removeapps = "X"
			}
		}
		6 {			
			if($setup_enablebitlocker -eq "X") {
				$setup_enablebitlocker = " "		
			} else {
				$setup_enablebitlocker = "X"
			}
		}
		10 {			
			$setup_partitions = "X" 
			$setup_tdrive = "X" 
			$setup_ldrive = "X" 
			$setup_tools = "X" 
			$setup_wallpaper = "X" 
			$setup_removeapps = "X" 
			$setup_enablebitlocker = "X"
		}
		11 {			
			$setup_partitions = " " 
			$setup_tdrive = " " 
			$setup_ldrive = " " 
			$setup_tools = " " 
			$setup_wallpaper = " " 
			$setup_removeapps = " " 
			$setup_enablebitlocker = " "
		}
	} ##Switch Todo
}

if($todo -ne "q") {

	### Get the AWS Details
	$aws_bucket_name = Read-Host -Prompt 'AWS Bucket Name'      ##AWS Bucket Name
	$aws_bucket_keyt = Read-Host -AsSecureString -Prompt 'AWS Key'               ##AWS Bucket Key
	$aws_bucket_key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($aws_bucket_keyt))
	$aws_bucket_secrett = Read-Host -AsSecureString -Prompt 'AWS Secret Key' ##AWS Bucket Secret Key
	$aws_bucket_secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($aws_bucket_secrett))
	##### END S3 DETAILS ############

	##Setup AWS
	SetupAWS

	##Run the components
    if(Test-Path $script_check_file){
    	GeneralSetup ##Everyone gets the general setup first time around
    	remoteScript $reclaimWindows[0] $reclaimWindows[1]
        Get-Date | Out-File $script_check_file
    }

	##Partitions
	if(($setup_tdrive -eq "X") -or ($setup_ldrive -eq "X")) {
		SetupPartitions
	} ##if partitions

	##Bitlocker
	if($setup_enablebitlocker -eq "X") {
		EnableBitlocker
	} ##if partitions

	##Wallpaper
	if($setup_wallpaper -eq "X") {
		SetWallPaper
	} ##if partitions

	##Clean up Win10's act
	if($setup_removeapps -eq "X") {
		RemoveWin10Apps
	} ##if partitions

	##Install Tools
	if($setup_tools -eq "X") {
		getTools
	} ##if partitions
}## todo