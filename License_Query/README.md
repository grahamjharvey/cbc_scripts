This PowerShell script can be used to determine your current License usage in the Carbon Black Cloud.

Pre-requisites include:
- A Carbon Black Cloud API credentail with the Device > General Information > device, allow permission to READ.
- A vCenter Account with Host - Configuration - System Resources privileges.
- PowerShell with the VMware PowerCLI module installed.

The current script has not been tested with multiple vCenter servers and will likely require modification to support querying multiple vCenter servers.

The script has been tested in Windows 10 and Ubuntu 22.04.
