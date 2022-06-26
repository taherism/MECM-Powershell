#Connect to CM Site Server
$SiteCode = "XYZ" # Site code 
$ProviderMachineName = "ServerName.TEST.COM" # SMS Provider machine name
$initParams = @{}

if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Set-Location "$($SiteCode):\" @initParams


#Install Dp Server
$readyListForBG=@()
$DPErrorReport=@()
$DPList=Get-Content "C:\SCCMCOPYlist.txt"
$DPList | foreach {
$DistributionPoint = ($_).trim().ToUpper()
$DistributionPointFQDN = ($_).trim().ToUpper()+'.TEST.COM' #You Must Set FQDN Name Server
$Code = $DistributionPointFQDN.Substring("0","3") 
$Description = $DistributionPointFQDN.Substring("3","6")
if((Test-Connection $DistributionPointFQDN -Count 1 -Quiet) -eq $true){
$readyListForBG+=@($DistributionPointFQDN)
Write-Host "$DistributionPointFQDN IS READY" -ForegroundColor Green
#Install Site System Server
New-CMSiteSystemServer -ServerName $DistributionPointFQDN -SiteCode $code
#Install Distribution Point Role
Add-CMDistributionPoint -CertificateExpirationTimeUtc "February 07, 2121 10:10:00 PM" -SiteCode $code -SiteSystemServerName $DistributionPointFQDN -Description "$Code $Description DP" -InstallInternetServer -EnableAnonymous -ClientConnectionType 'Intranet' -PrimaryContentLibraryLocation D -PrimaryPackageShareLocation D -SecondaryContentLibraryLocation C -SecondaryPackageShareLocation C
}else{
$DPErrorReport+=@($DistributionPoint)
Write-Host "$DistributionPointFQDN IS NOT READY" -ForegroundColor Red
}
write-host "---------------------------------"
}
$readyListForBG|Out-File -FilePath "E:\Report\readyListForBG.txt"
$DPErrorReport |Out-File -FilePath "E:\Report\DPErrorReport.txt"


#Create Boundary and BoundaryGroup 
$BGErrorReport=@()
$readyListForBG | foreach {
$servers = ($_).trim()
$ping= Ping $servers -n 1

if($ping -like '*Pinging*' -and $ping -like '*data*'){
#warning: octet1 and 4 must be replaced
$octet = ($ping[1].Split(" "))[2].split("\.")
#$octet1 = $octet[0]
$octet2 = $octet[1]
$octet3 = $octet[2]
#$octet4 = $octet[3]

$BGSiteCode = $servers.Substring("0","3")
$numberBranch = $servers.Substring("3","6")
$boundaryGroupName = "$BGSiteCode-BG-DP-$numberBranch"
$boundaryName = "$BGSiteCode-Branch-$numberBranch"

New-CMBoundaryGroup -Name $boundaryGroupName | Select-Object -Property Name | Format-List
Set-CMBoundaryGroup -Name $boundaryGroupName -AddSiteSystemServerName  "$servers"
Write-Host "$boundaryGroupName Added To Boundary Group" -ForegroundColor Green

New-CMBoundary -DisplayName $boundaryName -BoundaryType IPRange -Value "1.$octet2.$octet3.1-1.$octet2.$octet3.254" | Select-Object -Property DisplayName , Value | Format-List
Write-Host "$boundaryName Added To Boundary" -ForegroundColor Green

Add-CMBoundaryToGroup -BoundaryGroupName $boundaryGroupName -BoundaryName $boundaryName
Write-Host "$boundaryName Assign To $boundaryGroupName" -ForegroundColor Green

}else{

$BGErrorReport+=@($servers)
Write-Host "$servers IS NOT READY for add to Boundary and boundarygroup" -ForegroundColor Red
}
write-host "---------------------------------"
}
$BGErrorReport | Out-File -FilePath "E:\Report\BGErrorReport.txt"



#Set schedule for Distribution Point  
$dpList=$readyListForBG #the server name must be FQDN
$PrimarySiteName = $ProviderMachineName
$SiteCodePrimary = $SiteCode

foreach($name in $dpList){
$DpSiteCode = $name.substring("0","3")

[String]$SiteServerName=$PrimarySiteName
[String]$ServerName=$name


$UsageAsBackup = @($true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true,$true)
# 1 means all Priorities, 2 means all but low, 3 is high only, 4 means none

$HourUsageScheduleFriday =  @(1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1)
$HourUsageSchedule = @(1,1,1,1,1,1,4,4,4,4,4,4,4,4,4,4,4,4,1,1,1,1,1,1)
$SMS_SCI_ADDRESS = "SMS_SCI_ADDRESS"
$class_SMS_SCI_ADDRESS = [wmiclass]""
$class_SMS_SCI_ADDRESS.psbase.Path ="\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):$($SMS_SCI_ADDRESS)"

$SMS_SCI_ADDRESS = $class_SMS_SCI_ADDRESS.CreateInstance()

 # Set the UsageSchedule
 $SMS_SiteControlDaySchedule           = "SMS_SiteControlDaySchedule"
 $SMS_SiteControlDaySchedule_class     = [wmiclass]""
 $SMS_SiteControlDaySchedule_class.psbase.Path = "\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):SMS_SiteControlDaySchedule"
 $SMS_SiteControlDaySchedule          = $SMS_SiteControlDaySchedule_class.createInstance()
 $SMS_SiteControlDaySchedule.Backup    = $UsageAsBackup
 $SMS_SiteControlDaySchedule.HourUsage = $HourUsageSchedule
 $SMS_SiteControlDaySchedule.Update    = $true

 # Set the UsageSchedule For Weekends
 $SMS_SiteControlDayScheduleFriday = "SMS_SiteControlDaySchedule"
 $SMS_SiteControlDayScheduleFriday_class = [wmiclass]""
 $SMS_SiteControlDayScheduleFriday_class.psbase.Path = "\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):SMS_SiteControlDaySchedule"
 $SMS_SiteControlDayScheduleFriday = $SMS_SiteControlDaySchedule_class.createInstance()
 $SMS_SiteControlDayScheduleFriday.Backup = $UsageAsBackup
 $SMS_SiteControlDayScheduleFriday.HourUsage = $HourUsageScheduleFriday
 $SMS_SiteControlDayScheduleFriday.Update = $true

 $SMS_SCI_ADDRESS.UsageSchedule        = @($SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDaySchedule,$SMS_SiteControlDayScheduleFriday,$SMS_SiteControlDaySchedule)



$SMS_SCI_ADDRESS.AddressPriorityOrder = "1"
$SMS_SCI_ADDRESS.AddressType          = "MS_LAN"
$SMS_SCI_ADDRESS.DesSiteCode          = "$($ServerName)"
$SMS_SCI_ADDRESS.DestinationType      = "1"
$SMS_SCI_ADDRESS.SiteCode             = "$($DpSiteCode)"
$SMS_SCI_ADDRESS.UnlimitedRateForAll  = $true

# Set the embedded Properties
$embeddedpropertyList = $null
$embeddedproperty_class = [wmiclass]""
$embeddedproperty_class.psbase.Path = "\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):SMS_EmbeddedPropertyList"
$embeddedpropertyList     = $embeddedproperty_class.createInstance()
$embeddedpropertyList.PropertyListName  = "Pulse Mode"
$embeddedpropertyList.Values  = @(0,3,5) #second value is size of data block in KB, third is delay between data blocks in seconds
$SMS_SCI_ADDRESS.PropLists += $embeddedpropertyList

$embeddedproperty = $null   
$embeddedproperty_class = [wmiclass]""
$embeddedproperty_class.psbase.Path = "\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):SMS_EmbeddedProperty"
$embeddedproperty     = $embeddedproperty_class.createInstance()
$embeddedproperty.PropertyName  = "Connection Point"
$embeddedproperty.Value   = "0"
$embeddedproperty.Value1  = "$($ServerName)"
$embeddedproperty.Value2  = "SMS_DP$"  
$SMS_SCI_ADDRESS.Props += $embeddedproperty

$embeddedproperty = $null
$embeddedproperty_class = [wmiclass]""
$embeddedproperty_class.psbase.Path = "\\$($SiteServerName)\ROOT\SMS\Site_$($SiteCodePrimary):SMS_EmbeddedProperty"
$embeddedproperty     = $embeddedproperty_class.createInstance()
$embeddedproperty.PropertyName  = "LAN Login"
$embeddedproperty.Value   = "0"
$embeddedproperty.Value1  = ""
$embeddedproperty.Value2  = ""  
$SMS_SCI_ADDRESS.Props += $embeddedproperty
$SMS_SCI_ADDRESS.Put() | Out-Null
Write-Host "$name Done" -ForegroundColor Green
write-host "------------------------------------"
}
