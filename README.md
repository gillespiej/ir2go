# CERT Australia - IR2Go

IR2Go is an Incident Response tool kit designed to help in the acquisition of forensic artifacts such as disk, memory and network.
The tool can be installed onto any USB drive that is over 64GB and includes primary and secondary tools, plus guides on how to perform the capture. The IR2Go tool is deployable from any computer with a internet connection and is easy to deploy.

## Getting Started

1. Install windows onto USB drive. 
2. Run script
3. Coffee
4. Respond to incident.

### Prerequisites

#### Download Tools

The tools are a vital part of the IR2Go environment. 
The tools listed below are an example of the tools you can use. This list is not an endorsement and you should assess each tool against your requirements. 

**Acquisition Files**
* FTK Imager - https://accessdata.com/product-download
* Comae Toolkit - https://www.comae.io
* Belkasoft Acquisition Tool - https://www.belkasoft.com
* Wireshark - https://www.wireshark.com

**Other Utilities**
* PStart Menu - http://www.pegtop.net/start/
* SumatraPDF - https://www.sumatrapdfreader.org/free-pdf-reader.html

Each tool should run without needing to be installed and will need to be zipped ready for deployment.  
There is one tool per zip file and the structure of the zip file should reflect. (An example is provided aswell)

```
Root of ZIP/ 
├── Tool Name (FTK Imager Lite X.X.X)
│   ├── Tool files (FTK Imager.exe)
│   ├── Tool files (adefs.dll)
etc. etc.
 ```

#### AWS S3 Setup

The following components of AWS need to be configured as for each item below

* S3 Bucket

Setup a S3 Bucket with the following directory strucutre:

```
IR2Go /
├── Acquisition
│   ├── Windows
│   │   ├── _ZIP Files as prepared in the section above_
├── General
│   ├── _General Files such as background images, PDF Viewer_
├── Menu
│   ├── _Menu Application (PStart)_

```

* S3 IAM Account

A user account created with only Read Only access to the S3 bucket created above, and Key access.

#### WIM Prep

The install.wim file can be mounted and both the shortcut file and unattended install file can be pre-loaded into the correct locations. This allows users to skip step 5 below.

For information on managing WIM files see https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/mount-and-modify-a-windows-image-using-dism

### Installing

_The following steps need to be completed on a windows machine_

1. A install.wim file needs to be obtained from the installation media of a Windows 10 Environment. A Windows 10 installation disk can be created using the Windows 10 Media Creation Tool. (You may need to extract the WIM from a ESD File)

2. Partition the USB Drive -(In the example below, Disk 1 is the USB drive)_
```
#Start Diskpart
diskpart

#List disks
LIST DISK

#Select the correct disk
SELECT DISK 1

#CLEAN the drive - ***WARNING!!! All data will be lost in this process***
CLEAN

#Create a boot partition, format it etc
CREATE PARTITION PRIMARY SIZE=350
FORMAT FS=FAT32 QUICK
ACTIVE
ASSIGN LETTER=Y

#Repeat to create the primary partition
SELECT DISK 1
CREATE PARTITION PRIMARY
FORMAT FS=NTFS QUICK
ASSIGN LETTER=X
```

3. Apply the WIM file to the newly created partition
```
#Using DISM from the same directory as the install.wim file
DISM /apply-image /imagefile:install.wim /index:1 /ApplyDir:X:\
```

4. Set the device as bootable
```
BCDBOOT.EXE X:\Windows /S Y: /F ALL

#If the command above fails, try 
BCTBOOT.EXE X:\Windows /S Y:
```

5. Install the required files to the USB Drive
```
#Copy the shortcut to the all users desktop
https://github.com/certau/ir2go/blob/master/WIM-Files/Start%20Setup%20of%20IR2Go.lnk --> X:\Users\Public\Desktop\Start Setup of IR2Go.lnk

#Copy the unattended XML file to the Windows Directory (The Panther directory needs to be created.)
https://github.com/certau/ir2go/blob/master/WIM-Files/unattend.xml --> X:\Windows\Panther\unattend.xml
```

6. Boot to the USB device. This may take a few attemps as drivers etc are configured.

7. Connect to Wi-Fi during the setup wizard. 

8. Run the 'Start Setup of IR2Go' icon on the desktop as an administrator (Right Click --> Run As Administrator)
When prompted, enter your AWS S3 bucket details

## Authors

* **Dean B** - *Initial work* - CERT Australia

## Known issues

Feedback is always welcome, however the following issues may occur.

* The script may fail due to being unable to resize the windows partition. The script needs to be able to resize the primary windows partition to 20GB. if it can not do this, the script will continue to run, but will fail. 