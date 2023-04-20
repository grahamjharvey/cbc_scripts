# Author: Graham Harvey - grahamh@vmware.com

# Check if PowerCLI is installed, if not break.
if (Get-Module -ListAvailable -Name VMware.PowerCLI) {
    Write-Host "PowerCLI is installed"
	Write-Host ""
	Write-Host "Checking if the PowerCLI Configuration allows for self-signed certs..."
	# Check if PowerCLI is set to prompt for invalid certs.
	$InvalidCertificateAction = (Get-PowerCLIConfiguration -Scope User).InvalidCertificateAction
	if ($InvalidCertificateAction -ne "Prompt") {
		# Enable invalid cert prompt for those using self-signed certificates on their vCenter.
		Write-Host "The following enables PowerCLI to prompt for invalid certifcates rather than just fail."
		Write-Host "This is required if you are using self-signed certifcates."
		Write-Host "Please select Yes (Y) or Yes for all (A)."
		Set-PowerCLIConfiguration -InvalidCertificateAction prompt
	}
	else {
		Write-Host ""
		Write-Host "PowerCLI will prompt if an Invalid/Self-Signed Certificate is used on vCenter"
		Write-Host ""
	}	
} 
else {
    Write-Host "!!!!! WARNING !!!!!"
	Write-Host "Please install PowerCLI prior to running this script."
	Write-Host "https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.esxi.install.doc/GUID-F02D0C2D-B226-4908-9E5C-2E783D41FE2D.html"
	Write-Host "!!!!! WARNING !!!!!"
	break
}

# Get the CBC environment info.
$validSelection = $false
while (-not $validSelection) {
	Write-Host "Please select the URL of your CBC environment:"
	Write-Host "1. https://defense.conferdeploy.net"
	Write-Host "2. https://defense-prod05.conferdeploy.net"
	Write-Host "3. https://defense-prodeu.conferdeploy.net"
	Write-Host "4. https://defense-prodnrt.conferdeploy.net"
	Write-Host "5. https://defense-prodsyd.conferdeploy.net"
	Write-Host ""
	Write-Host "This script has not been tested with the GovCloud or UK backends."
	Write-Host ""

	$cbcSelection = Read-Host "Enter the number of your choice"

	switch ($cbcSelection) {
		"1" { $cbc_backend = "https://defense.conferdeploy.net"; $validSelection = $true}
		"2" { $cbc_backend = "https://defense-prod05.conferdeploy.net"; $validSelection = $true}
		"3" { $cbc_backend = "https://defense-prodeu.conferdeploy.net"; $validSelection = $true}
		"4" { $cbc_backend = "https://defense-prodnrt.conferdeploy.net"; $validSelection = $true}
		"5" { $cbc_backend = "https://defense-prodsyd.conferdeploy.net"; $validSelection = $true}
		"cancel" {Write-Host "Exiting..."; exit }
		default {
			Write-Host ""
			Write-Host "-----------------------"
			Write-Host "Invalid selection. Please enter a number between 1 and 5 or type 'cancel' to exit."
			}
	}
}

if ($cbc_backend) {
    Write-Host "You have selected"$cbc_backend
}

# Get the CBC API creds.
$cbc_creds = Read-Host "Enter your API Token in the format of API_SECRET_KEY/API_KEY"
$cbc_orgKey = Read-Host "Enter your Orgkey (shown on the API page)"

# Set the X-Auth-Token.
$headers = @{
    "X-Auth-Token" = $cbc_creds
    "Content-Type" = "application/json"
}

# Set the request parameters.
$params = @{
    Method = "POST"
    Headers = $headers
}

# Set the initial offset and page size.
$offset = 0
$pageSize = 10000

# Set the values to count and use as variables.
$endpointCount = 0
$AWSWorkloadCount = 0
$VMWorkloadCount = 0
$VDICount = 0

# Iterate over the API response using POST requests.
do {
    # Set the request body with the page size parameter.
    $requestBody = @{
        criteria = @{
            last_contact_time = @{
                range = "-30d"
            }
        }
        rows = $pageSize
        start = $offset
        sort = @(
            @{
                field = "name"
                order = "ASC"
            }
        )
    } | ConvertTo-Json

    # Add the request body to the parameters.
    $params.Add("Body", $requestBody)
    
    # Make the API request and get the response.
    $response = Invoke-RestMethod $cbc_backend"/appservices/v6/orgs/"$cbc_orgKey"/devices/_search" @params
    
    # Count the number of instances of the value in the response data.
    foreach ($data in $response.results) {
        if ($data.deployment_type -eq "ENDPOINT") {
            $endpointCount++
        }
        elseif ($data.deployment_type -eq "AWS") {
            $AWSWorkloadCount++
        }
        elseif ($data.deployment_type -eq "VDI") {
            $VDICount++
        }
        elseif ($data.deployment_type -eq "WORKLOAD") {
            $VMWorkloadCount++ 
			# Get the relevant ESXi hostnames.
            $esx_host_name = $response.results | Select-Object -ExpandProperty esx_host_name
			# Extract only unique ESXi hostnames.
            $unique_esx_hosts = $esx_host_name | Select-Object -Unique
            $vCenter = $response.results | Select-Object -ExpandProperty vcenter_host_url
            $unique_vCenter = $vCenter | Select-Object -Unique
        }
    }
    
    # Increment the offset.
    $offset += $pageSize

} while ($null -ne $response.next)

# List the unique ESXi hosts and the unique vCenter servers that will be used to get CPU/Core information.
Write-Host ""
Write-Host "-------------------------"
Write-Host "The unique ESXi hosts are "$unique_esx_hosts". The script will pull CPU info from these ESXi hosts."
Write-Host ""
Write-Host "The script will attempt to connect with these vCenter servers:" $unique_vCenter
Write-Host ""
Write-Host "---- Required vCenter privileges... ----"
Write-Host ""
Write-Host "These are required to get CPU information:"
Write-Host "Host"
Write-Host "    - Configuration"
Write-Host "        - System Resources"
Write-Host ""
Write-Host "---- Only the above privileges are required. ----"
Write-Host ""

# Ask the use if the above submission looks correct to the and wait for a Y before continuing.
Write-Host "Does the above look correct and do you have credentials with sufficient privileges?"
$continue = Read-Host -Prompt "Y/N"
Write-Host ""
Write-Host "-------------------------"
Write-Host ""
# If N is entered ask the user to correct their CSV file and try again.
if ($continue -eq "N") {Write-Host ""
    Write-Host "Those are the vCenter servers the CBC sensors are reporting.  If this is incorrect,"
    Write-Host "please ensure that the CBC Workload Appliance is connected to vCenter and the CBC."
}
else {
    # This function collects the ESXi Host's CPU information from the vSphere API.
    Function Get-HostCPUInfo {
        Param(
            [Parameter(Position=0, ValueFromPipeline=$true, Mandatory=$true)][String]$vmHost
        )
        
        $server = get-VMHost $vmHost
    
        $object = New-Object -TypeName PSObject
        $object | Add-Member -type NoteProperty -name HostName -value $server.Name
        $object| Add-Member -type NoteProperty -name CpuSockets -value $server.ExtensionData.summary.hardware.NumCpuPkgs
        $object| Add-Member -type NoteProperty -name CpuCores -value $server.ExtensionData.summary.hardware.NumCpuCores
        
        Return ($object)
    }
    
	# Connect to vCenter server
	# !!!! NOTE !!!!
	# This needs to be updated to connect to multiple vCenter servers if required!!
	# This script only connects to a single vCenter server.
	# !!!! NOTE !!!!
	Connect-VIServer -Server $unique_vCenter
	Write-Host ""
	Write-Host "Unique ESXi hosts:"
	$unique_esx_hosts
	Write-Host "------------------"
	$totalCpuSockets = 0
	$totalCpuCores = 0
	foreach ($vmHost in $unique_esx_hosts) {
		$output = Get-HostCPUInfo -vmHost $vmHost | Select-Object hostname, CpuSockets, CpuCores
		Write-Host "Output CPU Sockets:"
		$sockets = $output.CpuSockets[0]
		$sockets
		$totalCpuSockets += $sockets
		Write-Host "-------"
		Write-Host "Output CPU Cores:"
		$cores = $output.CpuCores[0]
		$cores
		$totalCpuCores += $cores
		Write-Host "-------"
	}
	# Get the ServiceInstance object.
	$serviceInstance = Get-View ServiceInstance

	# Retrieve the aboutInfo property of the ServiceInstance object.
	$aboutInfo = $serviceInstance.Content.About

	# Check if the vCenter Server is running in VMware Cloud on AWS.
	if ($aboutInfo.ApiType -eq "vcloud" -and $aboutInfo.ProductLineId -eq "vmware_cloud_on_aws") {
	    Write-Host ""
		Write-Host "vCenter Server is running in VMware Cloud on AWS"
		$VMC = $true
	}
	else {
	    Write-Host ""
		Write-Host "vCenter Server is running on-premises vSphere"
		$VMC = $false
	}

	# Disconnect from the vCenter Server.
	Disconnect-VIServer -Server $unique_vCenter -Confirm:$false
	Write-Host ""
	
	# Let the user know how many licenses they are using.
	# List number of ENDPOINT licenses used.
	if ($endpointCount -ne 0) {	
		Write-Host "You are using" $endpointCount "Carbon Black Cloud Endpoint licenses."
	}
	else {
		Write-Host "You are not using any Endpoint licneses."
	}
	# List the number of CPU/Core based VM Workload licenses used.
	if ($VMWorkloadCount -ne 0) {
		Write-Host ""
		# If they're not using VMC on AWS then provide the number of CPU licenses.
		if ($VMC -eq $false) {
			Write-Host "You are using" $totalCpuSockets "Carbon Black Cloud Workload CPU licenses."
			Write-Host ""
			# Since VMware has a limit of 56 cores per CPU from a licnesing perspective, calculate the CPU sockets based on this licensing metric.
			if ($totalCpuCores/$totalCpuSockets -gt 56) {
				$VMwareSocketCount = $totalCpuCores/56
				$VmwareCPUlicense = [math]::ceiling($VMwareSocketCount)
				Write-Host "In your environment, on average, each CPU Socket has more than 56 cores."
				Write-Host "According to VMware licensing this means that on average, you're using more than 1 license per Socket"
				Write-Host "Therefore you are using"$VmwareCPUlicense "Workload CPU licenses"
			}
		}
		# If they're using VMC on AWS then display the number of CORE licenses used.
		else {
			Write-Host "You are using" $totalCpuCores "Carbon Black Cloud Workload CORE licenses."
			Write-Host ""
		}

	}
	else {
		Write-Host "You are not using any VM Workload licenses."
	}
	if ($AWSWorkloadCount -ne 0) {
		Write-Host "You are using" $AWSWorkloadCount "Carbon Black Public Cloud Workload licenses."
	}
	else {
		Write-Host "You are not using any Public Cloud Workload licneses."
	}
}