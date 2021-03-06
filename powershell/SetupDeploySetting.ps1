###############################################################################
# ChangeLog
#
# v2013-12-09
#     - Remove the deployment spec file creation
#
# v2013-12-04
#     - First Version, modify from the jumpbox setup ps
#
###############################################################################

###############################################################################
# Parameters
###############################################################################

param(
    # Mandatory ones:
    [Parameter(Mandatory = $true, HelpMessage = "Service Name")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceName,
    
    [Parameter(Mandatory = $true, HelpMessage = "List of Wadi environments seperated by comma.")]
    [ValidateNotNullOrEmpty()]
    [string]$WadiEnvironmentList,

    [Parameter(Mandatory = $true, HelpMessage = "List of service environments (config) seperated by comma. Should match WadiEnvironmentList.")]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceEnvironmentList,

    [Parameter(Mandatory = $true, HelpMessage = "Path to build drop folder")]
    [ValidateNotNullOrEmpty()]
    [string]$DropFolderPath,

    # Not mandatory ones:
    [Parameter(Mandatory = $false, HelpMessage = "Resume Point")]
    [ValidateSet('DeployToStagingSlot', 'VipSwap', 'Rollback', 'DeployToStagingAndSwap')]
    [string]$ResumePoint = 'DeployToStagingSlot',

    [Parameter(Mandatory = $false, HelpMessage = "Equal to your vector name")]
    [ValidateSet('DataTransfer')] # We only work on DataTransfer so far.
    [string]$WadiComponent = 'DataTransfer',

    [Parameter(Mandatory = $false, HelpMessage = "The one to be notified when problem arises")]
    [ValidateNotNullOrEmpty()]
    [string]$WadiIncidentOwner = 'FAREAST\jiewa',

    [Parameter(Mandatory = $false, HelpMessage = "Email Address for receiving deployment log")]
    [string]$EmailTo = $null
)

###############################################################################
# Functions
###############################################################################

Function Write-ErrorExit
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$str
    )

    Write-Host -ForegroundColor Red $str;
        
    exit -1;
}

Function Write-StepSeperator
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$str
    )

    Write-Host -ForegroundColor Green $str;
}

Function Write-StepOK
{
    Write-Host -ForegroundColor Cyan "OK!";
}

Function Generate-SettingsFileName
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$compName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$svcEnv
    )

    $fileName = [System.String]::Concat("Settings_", $compName, "_", $svcEnv, ".xml");
    return $fileName;
}

Function String-Replace
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$str,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$key,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$value
    )

    return $str.Replace($key, $value);
}

Function Xml-NodeValueReplace
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Xml.XmlNode]$node,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$key,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$value
    )
    
    if([System.Xml.XmlNodeType]::Text -eq $node.NodeType){
        $node.Value = String-Replace $node.Value $key $value
    }else{
        
    }

    if($null -ne $node.Attributes){
        foreach ($attr in $node.Attributes)
        {
            $attr.value = String-Replace $attr.value $key $value 
        }
    }

    if($null -ne $node.ChildNodes){
        foreach($child in $node.ChildNodes)
        {
            Xml-NodeValueReplace $child $key $value
        }
    }
}

Function Update-XmlFile
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$xmlFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $kvMap,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$destPath
    )

    $xml = [xml](get-content $xmlFile)
    if($null -eq $xml)
    {
        Write-ErrorExit "can't find the xml file: $xmlFile"
        return -1;
    }

    foreach($key in $kvMap.Keys)
    {
        $keyTemp = [System.String]::Concat("##", $key, "##")
        Xml-NodeValueReplace $xml.DocumentElement  $keyTemp $kvMap[$key]
    }

    $xml.Save($destPath);

    return 1;
}

Function Generate-SettingsFile
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$ServiceEnvironment
    )

    $settingsFile = Generate-SettingsFileName $WadiComponent $ServiceEnvironment
    $settingsFilePath = [System.IO.Path]::Combine($DropFolderPath, $RDToolsFolderName, $RDToolsDeployFolderName, $settingsFile)
    Write-Host "Settings File $Index = $settingsFilePath"

    $settingsTemplateFilePath = [System.IO.Path]::Combine($scriptFolder, $SettingsTemplateFileName)

    if(![System.IO.File]::Exists($settingsTemplateFilePath))
    {
        Write-ErrorExit "Settings Template File $settingsTemplateFilePath does not exist."
    }

    $kvMapSettings = @{}

    # EmailTo
    $kvMapSettings["EmailTo"] = $EmailTo

    # IncidentOwner
    $kvMapSettings["IncidentOwner"] = $WadiIncidentOwner

    # Environment
    $kvMapSettings["ServiceEnvironment"] = $ServiceEnvironment

    # ResumePoint
    $kvMapSettings["ResumePoint"] = $ResumePoint

    $updateResult = Update-XmlFile $SettingsTemplateFilePath $kvMapSettings $settingsFilePath

    if(-1 -eq $updateResult)
    {    
        Write-ErrorExit "Failed to assemble Settings File: $settingsTemplateFilePath"
        exit;
    }
}

###############################################################################
# Main Entry
###############################################################################

Write-StepSeperator '###################################################################################################'
Write-StepSeperator '#'
Write-StepSeperator '# 1. Preparing some script variables'
Write-StepSeperator '#'
Write-StepSeperator '###################################################################################################'

$scriptFolder = Split-Path ($MyInvocation.MyCommand.Definition) -Parent
Write-Host "Current script folder = $scriptFolder"

$DeploymentSpecTemplateFileName = "DeploymentSpecTemplate.xml"
$SettingsTemplateFileName = "SettingsTemplate.xml"

# RDTools Folder Tree
$RDToolsFolderName = "RDTools"
$RDToolsDeployFolderName = "Deploy"
$RDToolsToolsFolderName = "Tools"
$RDToolsDeployTemplatesFolderName = "Templates"
$WorkFlowFileName = "DMDeployWorkflow.xaml"

# Get current user
$CurUser = $env:username
Write-Host "Current User = $CurUser"

Write-StepOK

Write-StepSeperator '###################################################################################################'
Write-StepSeperator '#'
Write-StepSeperator '# 2. Validating the script inputs'
Write-StepSeperator '#'
Write-StepSeperator '###################################################################################################'

# Wadi Environments, Service Environments, Resume Points
$WadiEnvironments = $WadiEnvironmentList.Split(",")
$ServiceEnvironments = $ServiceEnvironmentList.Split(",")

if ($WadiEnvironments.Length -ne $ServiceEnvironments.Length)
{
    Write-ErrorExit "WadiEnvironmentList and ServiceEnvironmentList are not match."
}

for ($i = 0; $i -lt $WadiEnvironments.Length; $i++)
{
    $WadiEnvironment = $WadiEnvironments[$i]

    # Check if WadiEnvironment is within a validation set
    if ($WadiEnvironment -ne "Test" -and $WadiEnvironment -ne "Stage" -and $WadiEnvironment -ne "Production")
    {
        Write-ErrorExit "WadiEnvironment must be one of Test, Stage and Production."
    }

    Write-Host "Wadi Environment $i = $WadiEnvironment"

    $ServiceEnvironment = $ServiceEnvironments[$i]
    Write-Host "Service Environment $i = $ServiceEnvironment"
}

Write-Host "WadiComponent = $WadiComponent"
Write-Host "WadiIncidentOwner = $WadiIncidentOwner"
Write-Host "Resume Point = $ResumePoint"

# EmailTo
if([string]::IsNullOrEmpty($EmailTo))
{
    $EmailTo = "fareast\jiewa";
}

Write-Host "EmailTo = $EmailTo"

Write-Host "Generating the Settings files"
for ($i = 0; $i -lt $WadiEnvironments.Length; $i++) {
    $ServiceEnvironment = $ServiceEnvironments[$i]
    Generate-SettingsFile $i $ServiceEnvironment
}

exit;