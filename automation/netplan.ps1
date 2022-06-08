<#
.SYNOPSIS
Easy way to call the Rancher API

.LINK
http://sre.com/api
#>
function Invoke-RancherApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
        ,
        [Parameter()]
        [ValidateSet('Delete', 'Get', 'Post', 'Put')]
        [string]
        $Method = 'Get'
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [hashtable]
        $headers = @{}
    )

    if (-not $headers.ContainsKey('Accept')) {
        $headers.Add('Accept', 'application/json')
    }

    $rancher = @{Endpoint = psGetEnv "rancherEndpoint" ;AccessKey = psGetEnv "accessKey"; SecretKey = psGetEnv "secretKey"}
    $base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($Rancher.AccessKey):$($Rancher.SecretKey)"))
    $headers.Add('Authorization', "Basic $base64AuthInfo")

    $Next = "$($rancher.Endpoint)/$Path"
    $Data = @()

    while ($Next) {
        # Write-Host "Calling Rancher on url $Next"
        $Response = Invoke-WebRequest -UserAgent "Nona Business" -Uri $Next -Method $Method -Headers $headers

        $Content = $Response.Content.Replace('"HTTP_PROXY="', '"http_proxy_uppercase="').Replace('"HTTPS_PROXY="', '"https_proxy_uppercase="').Replace('"NO_PROXY="', '"no_proxy_uppercase="')
        $Content = $Response.Content.Replace('"HTTP_PROXY"', '"http_proxy_uppercase"').Replace('"HTTPS_PROXY"', '"https_proxy_uppercase"').Replace('"NO_PROXY"', '"no_proxy_uppercase"')
        $Content = $Content -replace '""','"empty"' | ConvertFrom-Json

        if ($Content.baseType -eq "generateKubeConfigOutput") {
            $Data += $Content.config
        } else {
            $Data += $Content.data
        }

        $Next = $Content.pagination.next
    }

    $Data
}

<#
.SYNOPSIS
Uses the Rancher API to download a kubeconfig. Use parameter "Clustername".

.LINK
http://sre.com/api
#>
function Get-RancherKubeconfig
{
	param(
		[string]$clusterName
        )

    $cluster = Get-RancherCluster $clusterName

    $path = "clusters/" + $cluster.id + "?action=generateKubeconfig"
    $config = Invoke-RancherApi -path $path -method "Post"

    $kubeDir = Join-Path $home .kube
    $kubeFile = Join-Path $kubeDir $clusterName
    
    if (!(Test-Path $kubeFile)) { $null = New-Item -Path $kubeFile -ItemType "file"}

    $config | Out-File $kubeFile -Force
}

<#
.SYNOPSIS
Gets all Rancher clusters using the Rancher API

.LINK
http://sre.com/api
#>
function Get-RancherClusters
{
    $clusters = Invoke-RancherApi -path "clusters" -method "Get"
    return $clusters
}

<#
.SYNOPSIS
Gets a specific Rancher cluster using the Rancher API

.LINK
http://sre.com/api
#>
function Get-RancherCluster
{
	param(
		[string]$clusterName
        )

    $clusters = Get-RancherClusters

    if ("" -eq $clusterName) {
        $clusters | Select-Object name,nodeCount | Sort-Object -Property name | Format-Table
        while ($clusters.id -notcontains $clusterID) {
            $clusterName = Read-Host "Type ClusterName"
            $cluster = $clusters | Where-Object { $_.name -eq $clusterName }
            $clusterID = $cluster.id
        }
    } else {
        $cluster = $clusters | Where-Object { $_.name -eq $clusterName }
    }
    return $cluster
}

<#
.SYNOPSIS
Gets Nodes/VMs from a Rancher cluster

.LINK
http://sre.com/api
#>
function Get-RancherClusterNodes
{
	param(
		[string]$clusterName
        )

    $clusters = Get-RancherClusters

    if ("" -eq $clusterName) {
        $clusters | Select-Object name,nodeCount | Sort-Object -Property name | Format-Table
        while ($clusters.id -notcontains $clusterID) {
            $clusterName = Read-Host "Type ClusterName"
            $cluster = $clusters | Where-Object { $_.name -eq $clusterName }
            $clusterID = $cluster.id
        }
    } else {
        $cluster = $clusters | Where-Object { $_.name -eq $clusterName }
    }

    $path = "clusters/" + $clusterID + "/nodes"
    $nodes = Invoke-RancherApi -path $path -method "Get"

    return $nodes
}


<#
.SYNOPSIS
Sets a "secret" value.

.LINK
http://sre.com/common
#>
function psSetEnv
{
	param(
		[string]$name,
		$value,
		[bool]$nofile
        )

		# psSetEnv -name $name -value $value -nofile $false

		Set-Variable -Name $name -Value $value -Scope global
		if (!($nofile)) {
			$value | Export-Clixml -Path (Join-Path (psenvpath) ($name + ".xml"))
		}
		
}


<#
.SYNOPSIS
Gets a "secret" value. Prompts to set a new value, if it doesn't exist.

.LINK
http://sre.com/common
#>
function psGetEnv
{
	param(
		[string]$name
        )

	$fileLocation = ( Join-Path (psenvpath) ($name + ".xml") )
	if ( Test-Path $fileLocation ) {
		return ( Import-Clixml -Path $fileLocation )
	} else {
		Write-Host "$name variable not found, do you want to create it, yes/no"
		$choice = Read-Host
		if ($choice -eq "yes") {
			Write-Host "Enter result"
			$value = Read-Host
			psSetEnv -name $name -value $value -nofile $false
			return $value
		} else {
			return $null
		}
	}
}

function Get-psenvpath
{

    if ($isMacOS) {
        $psenvpath = Join-Path -Path $env:HOME -ChildPath ".secret"
        if (!(Test-Path "$psenvpath")) {New-Item -Path "$psenvpath" -ItemType "directory"}
        return $psenvpath
    } elseif ($isLinux) {
        $psenvpath = Join-Path -Path $env:HOME -ChildPath ".secret"
        if (!(Test-Path "$psenvpath")) {New-Item -Path "$psenvpath" -ItemType "directory"}
        return $psenvpath
    } elseif ($isWindows) {
        $psenvpath = Join-Path -Path $home -ChildPath "AppData/PSEnv"
        if (!(Test-Path "$psenvpath")) {New-Item -Path "$psenvpath" -ItemType "directory"}
        return $psenvpath
    }
}


function Run-Sshpass
{
    param(
		[string]$server,
        [string]$action = "ipInfo"
        )

        
        $user = psGetEnv sshuser
        $pass = psGetEnv sshpass

        if ($action -eq "ipInfo") {
            sshpass -p $pass ssh -o StrictHostKeyChecking=no ($user + '@' + $server ) "ip address show dev ens160"
        }
}


function Calculate-NetworkSettings
{
    param(
		[string]$server
        )

    $ipConfig = Run-Sshpass -server $server -action "ipInfo"
    $mac = ($ipConfig | select-string "link/ether" -NoEmphasis -Raw).split(" ")[5] -replace ":","-"
    $subnetMask = (($ipConfig | select-string "inet " -NoEmphasis -Raw).split(" ") | select-string "/" -NoEmphasis -Raw).split("/")[1]
    $dnsLookup = [System.Net.Dns]::GetHostEntry($server)
    $dnsName = $dnsLookup.HostName
    $ipAddress = $dnsLookup.AddressList.IPAddressToString
    $ipSplit = $ipAddress.split('.')
    $ipSplit[3] = 0
    $scopeId = $ipSplit -join "."
    return "Add-DhcpServerv4Reservation -ComputerName huadhcp-001.corp.lego.com -ScopeId $scopeId -IPAddress $ip -ClientId $mac -Name $dnsName"
}


function Get-DualIPCluster
{
    param(
		[string]$clusterName
        )

    $nodes = Get-RancherClusterNodes $clusterName
    foreach ($node in $nodes) {

    }
}

# Add-DhcpServerv4Reservation -ComputerName "huadhcp-001.corp.lego.com" -ScopeId 10.137.202.0 -IPAddress 10.137.202.98 -ClientId "00-50-56-85-0d-99" -Name huaapp-kw9.corp.lego.com