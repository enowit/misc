###############################################################################
# Parameters
###############################################################################

param(
    [Parameter(Mandatory = $true, HelpMessage = "Project name that you want to deploy")]
    [ValidateNotNullOrEmpty()]
    [string]$ProjName,

    [Parameter(Mandatory = $true, HelpMessage = "Enviroment that you want to deploy the services to")]
    [ValidateNotNullOrEmpty()]
    [string]$DeployEnv,

    [Parameter(Mandatory = $true, HelpMessage = "Resume Point")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('DeployToStagingSlot', 'VipSwap', 'Rollback', 'DeployToStagingAndSwap')]
    [string]$ResumePoint,

    [Parameter(Mandatory = $true, HelpMessage = "Path to deployment data folder")]
    [ValidateNotNullOrEmpty()]
    [string]$DataFolder,

    [Parameter(Mandatory = $false, HelpMessage = "GUID for this deployment, usually this is generated automatically")]
    [string]$Guid = $null,

    [Parameter(Mandatory = $false, HelpMessage = "Email Address for receiving deployment log")]
    [string]$EmailTo = $null,

    [Parameter(Mandatory = $false, HelpMessage = "Deployment tools selection: wadi, local")]
    [ValidateSet('wadi', 'local', 'remote')]
    [string]$DeployMethod = 'wadi'
)

###############################################################################
# Functions
###############################################################################

    Function Write-StepSeperator
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$str
        )

        Write-Host -ForegroundColor Green $str;
    }

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

    Function Create-ShareFolder
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$rootPath,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$subFolder
        )

        New-Item -path $rootPath -type directory -Force
    
        $toolsPath = [System.IO.Path]::Combine($rootPath, $subFolder);
        New-Item -path $toolsPath -type directory -Force
    }

    Function Set-ShareFolderAcl
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$targetPath,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$shareUser,

            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            [System.Security.AccessControl.FileSystemRights]$rights
        )

        $inheFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit;
        $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None;
        $accessControlType = [System.Security.AccessControl.AccessControlType]::Allow;

        $acl = Get-Acl $targetPath
    
        $accessRule = New-Object -typename System.Security.AccessControl.FileSystemAccessRule -ArgumentList $shareUser, $rights, $inheFlags, $propagationFlags, $accessControlType

        $acl.SetAccessRule($accessRule)

        $acl | Set-Acl $targetPath
    }

    Function Copy-DeployItem
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$source, 
    
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$dest
        )

        Copy-Item $source $dest -Force -Recurse
    }

    Function Copy-LibFiles
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$source,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$dest
        )

        $libFiles = Get-ChildItem -Path $source

        foreach($libFile in $libFiles)
        {
            $fileFullName = [System.IO.Path]::Combine($source, $libFile.ToString());
            Copy-Item -Path $fileFullName -Destination $dest -Force -Recurse
        }
    }

    Function Generate-ConfigFileName
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$projName,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$deployEnv,
        
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$name,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$postfix
        )

        $fileName = [System.String]::Concat($projName, "_", $deployEnv, "_", $name, ".", $postfix);
        return $fileName;
    }

    Function Generate-DeploymentName
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$projName,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$deployEnv,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$deployGuid
        )
        return [System.String]::Concat($projName, '_', $deployEnv, '_', $deployGuid);
    }

    Function Select-DeployEngine
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [xml]$deployConfigsXml,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$deployEnv
        )
        $endpoinsts = $deployConfigsXml.SelectNodes("/DeployConfig/DEEndPointList/DEEndPoint")
        foreach($endpoint in $endpoinsts)
        {
            $endenv = $endpoint.SelectSingleNode("Env").InnerText
            if($endenv -ieq $deployEnv)
            {
                $deendpoint = $endpoint.SelectSingleNode("DEURL").InnerText
                return $deendpoint
            }
        }

    
        if($endpoinsts.Count -ge 0)
        {
            Write-Host "For $deployEnv, there is no DEURL in DeployConfigs.xml, just use the first one"
            return $endpoinsts[0].SelectSingleNode("DEURL").InnerText;
        }

        return $null;
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

    Function Xml-GetNodeValue
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            [xml]$xmlDoc,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$nodePath
        )

        $node = $xmlDoc.SelectSingleNode($nodePath)
        if($null -eq $node)
        {
            Write-ErrorExit "can't find node path: $nodePath"
            return $null
        }

        return $node.InnerText
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
            $keyTemp = [System.String]::Concat("`$(", $key, ")")
            Xml-NodeValueReplace $xml.DocumentElement  $keyTemp $kvMap[$key]
        }

        $xml.Save($destPath);

        return 1;
    }

    Function Get-RDToolsVersion
    {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$rootpath
        )

        if(![System.IO.Directory]::Exists($rootpath))
        {
            return $null
        }

        $childs = Get-ChildItem $rootpath
        foreach($child in $childs)
        {
            if($child -like "rd_*")
            {
                return $child.ToString()
            }
        }

        return $null
    }

    Function Check-RDTools
    {

        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$localPath,
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$remotePath
        )
        $localVersion = Get-RDToolsVersion $localPath
        $remoteVersion = Get-RDToolsVersion $remotePath
    
        Write-Host "Local Version: $localVersion"
        Write-Host "Remote Version: $remoteVersion"

        if($localVersion -ne $remoteVersion)
        {
            if($null -ne $remoteVersion)
            {
                Write-Host "Installing Rdtools..."
            

                [int]$retriedTimes = 0;
                while([System.IO.Directory]::Exists($localPath) -and ($retriedTimes -lt 3))
                {
                   try
                   {
                        Remove-Item -Path $localPath -Force -Recurse
                   }
                   catch
                   {

                   }

                   $retriedTimes ++;
    
                   sleep 1
                }

                if([System.IO.Directory]::Exists($localPath))
                {
                    Write-ErrorExit "Old RDTools $localPath cannot be deleted. Please remove it manually."
                    return $null
                }

                try
                {
                    Copy-Item $remotePath $localPath -Force -Recurse
                }
                catch
                {
                    Write-ErrorExit "Failed to copy RDTools to $localPath. Please check if you have access right."
                }
            }
            else
            {
                Write-ErrorExit "Remote RDTools $remotePath is invalid."
            }
        }
        else
        {
            Write-Host "RDTools is up to date."
        }

        return Get-RDToolsVersion $localPath
    }

###############################################################################
# Main Entry
#
# COPY:     Workflow file + Lib + User Data Folder ==> Staging/Tools
# GENERATE: Wadi Deployment Task and Settings File
# CHECK:    C:\RDTools
###############################################################################
    $ErrorActionPreference = "Stop";

    $DTBuildDropBase = "\\bpddfs\TFS\DataTransfer\Main Nightly\"
    $WadiStagingBase = "\\csitrmtdev35\DmDeployShare\Staging"

    #$WadiStagingBase = "C:\DmDeplRoot\localshare\"
    
    $RemoteRDToolsBase = "\\csitrmtdev35\DmDeployShare\RdTools\"
    $LocalRDToolsBase = "C:\RdTools\"

    $LocalDeplRootBase = "C:\DmDeplRoot\"

    # My directory structure
    $LibFolderName = 'Lib'
    $AdnsFolderName = 'ADNS'
    $WorkflowInvoker = 'WorkflowInvoker.cmd'

    $WorkflowFolderName = "Workflow"
    $WorkflowFileName = "DMDeployWorkflow.xaml"

    $WadiConfigFolderName = "WadiConfig"
    $WadiConfig_DeployOptions = "DeployOptions.xml";
    $WadiConfig_SettingsTemplate = "WadiSettingsTemplate.xml";
    $WadiConfig_DeployTaskTemplate = "WadiDeployTaskTemplate.xml";
    [xml]$WadiConfig_DeployOptionsXml = $null;

    # Target "Tools" Folder Name
    $ToolsFolderName = 'Tools'

    # Wadi Settings, Workflow Argument
    $ISConfigFolderName = 'Tools\Config'

    # rdauto Account to kick off Wadi Client
    $DEDomain = 'redmond'
    $DEUsername = 'rdauto'
    $DEPassword = 'FCTest#$%'

    # Deployment Instance GUID
    if([string]::IsNullOrEmpty($Guid))
    {
        $Guid = [System.Guid]::NewGuid().ToString()
    }

    # Deployment Tool, default is "local"
    if([string]::IsNullOrEmpty($DeployMethod))
    {
        $DeployMethod = "local"
    }
    
    if([string]::IsNullOrEmpty($ResumePoint))
    {
        Write-ErrorExit "Argument 'ResumePoint' is not specified."
    }

    # Get script folder and cd
    $Cmd = $MyInvocation.MyCommand.Definition
    $CurPath = Split-Path -Parent $Cmd
    Write-Host "Script Directory is : $CurPath"
    cd $CurPath

    # Get current user
    $CurUser = $env:username
    Write-Host "Current User is : $CurUser"

    Write-StepSeperator '--- Creating the Deployment Shared Folder for WADI DE'

    # Load options xml
    [xml]$WadiConfig_DeployOptionsXml = [xml](get-content "..\$WadiConfigFolderName\$WadiConfig_DeployOptions")
    if($null -eq $WadiConfig_DeployOptionsXml)
    {
        Write-ErrorExit "Failed to load deploy options xml: $WadiConfig_DeployOptions in folder $WadiConfigFolderName"
    }

    # Validate the data folder
    $dataFolderPath = [System.IO.Path]::GetFullPath($DataFolder)

    if(![System.IO.Directory]::Exists($dataFolderPath))
    {
        Write-ErrorExit "The deployment data folder: $dataFolderPath does not exist."
    }

    # Create shared folder in staging
    $DeployInstanceName = [System.String]::Concat("deploy_", $Guid)
    Write-Host "Deployment Instance is : $DeployInstanceName"

    $deployInstancePath = [System.IO.Path]::Combine($WadiStagingBase, $DeployEnv, $DeployInstanceName)

    Write-Host "Deployment Instance folder: $deployInstancePath."

    Create-ShareFolder $deployInstancePath $ToolsFolderName | Out-Null
    if(![System.IO.Directory]::Exists($deployInstancePath))
    {
        Write-ErrorExit "Failed to create staging folder: $deployInstancePath. Please check whether you have access right."
    }

    # Copy workflow file
    $workflowDestPath = [System.IO.Path]::Combine($deployInstancePath, $ToolsFolderName);
    if(![System.IO.Directory]::Exists($workflowDestPath))
    {
        New-Item -path $WorkflowDestPath -type directory -Force | Out-Null
    }

    Write-Host 'Copying Workflow File...'

    $workflowDestFileRelPath = [System.IO.Path]::Combine($ToolsFolderName, $WorkflowFileName);
    $workflowSourceFileRelPath = [System.IO.Path]::Combine($CurPath, "..\", $WorkflowFolderName, $WorkflowFileName);
    $workflowDestFilePath = [System.IO.Path]::Combine($deployInstancePath, $workflowDestFileRelPath);

    try
    {
        Copy-DeployItem $workflowSourceFileRelPath $workflowDestFilePath
    }
    catch [System.Exception]
    {
        Write-ErrorExit "Failed to copy the workflow file to staging: $workflowSourceFileRelPath ==> $workflowDestFilePath. "
    }

    # Copy "Lib" Folder
    Write-Host 'Copying Lib Files...'
    $libSource = [System.IO.Path]::Combine($CurPath, "..\", $LibFolderName);
    $libDest = [System.IO.Path]::Combine($deployInstancePath, $ToolsFolderName);
    
    try
    {
        Copy-LibFiles $libSource $libDest
    }
    catch [System.Exception]
    {
        Write-ErrorExit "Failed to copy the lib files to staging: $libSource ==> $libDest. "
    }

    # Copy "ADNS" Folder
    Write-Host 'Copying ADNS Command Tool...'
    $adnsSource = [System.IO.Path]::Combine($CurPath, "..\", $AdnsFolderName);
    $adnsDest = [System.IO.Path]::Combine($deployInstancePath, $ToolsFolderName + "\" + $AdnsFolderName);

    if(![System.IO.Directory]::Exists($adnsDest))
    {
        New-Item -path $adnsDest -type directory -Force | Out-Null
    }
    
    try
    {
        Copy-LibFiles $adnsSource $adnsDest
    }
    catch [System.Exception]
    {
        Write-ErrorExit "Failed to copy the lib files to staging: $libSource ==> $libDest. "
    }
    
    # Generate Wadi settings file, and copy
    Write-Host 'Assemble and Copy WADI Settings File...'
    $wadiConfig_SettingsFile = Generate-ConfigFileName $ProjName $DeployEnv "Settings" "xml"
    $wadiConfig_SettingsFilePath = [System.IO.Path]::Combine($deployInstancePath, $wadiConfig_SettingsFile)

    $localSettingsFile = [System.IO.Path]::Combine($CurPath, "..\$WadiConfigFolderName", $WadiConfig_SettingsTemplate);

    if(![System.IO.File]::Exists($localSettingsFile))
    {
        Write-ErrorExit "Wadi Settings File $localSettingsFile does not exist."
    }

    if([string]::IsNullOrEmpty($EmailTo))
    {
        $EmailTo = $CurUser;
    }

    $kvMapSettings = @{}
    $kvMapSettings["EmailTo"] = $EmailTo
    $kvMapSettings["DeployEnv"] = $DeployEnv
    $kvMapSettings["ConfigFolder"] = $ISConfigFolderName
    $kvMapSettings["ResumePoint"] = $ResumePoint
    $updateResult = Update-XmlFile $localSettingsFile $kvMapSettings $wadiConfig_SettingsFilePath

    if(-1 -eq $updateResult)
    {    
        Write-ErrorExit "Failed to assemble WADI Settings File: $WadiConfig_SettingsFileName"
        exit;
    }

    # Generate Wadi task description file
    Write-Host 'Assemble and Copy WADI Task Description File...'
    $wadiConfig_DeployTaskFile = Generate-ConfigFileName $ProjName $DeployEnv "DeploymentTask" "xml"
    $wadiConfig_DeployTaskFilePath = [System.IO.Path]::Combine($deployInstancePath, $wadiConfig_DeployTaskFile)

    $kvMapTaskDesc = @{}
    $kvMapTaskDesc["DeployGuid"] = $Guid
    $kvMapTaskDesc["BuildPath"] = $deployInstancePath
    $kvMapTaskDesc["ToolsetPath"] = $deployInstancePath                      # For DE to upload module
    $kvMapTaskDesc["SettingsFileFullPath"] = $wadiConfig_SettingsFilePath    # Could be remote (DE perspective)
    $kvMapTaskDesc["DeployFlowPath"] = "$ToolsFolderName\$WorkFlowFileName"  # Must be relative path
    $kvMapTaskDesc["DeploymentName"] = Generate-DeploymentName $ProjName $DeployEnv $Guid
    $kvMapTaskDesc["ProjName"] = $ProjName

    $wadibranch = Xml-GetNodeValue $WadiConfig_DeployOptionsXml "/DeployConfig/WadiConfigs/WadiBranch"
    if($null -eq $wadibranch)
    {
        Write-ErrorExit "WadiBranch is null in $WadiConfig_DeployOptions. Please check the file."
    }
    $kvMapTaskDesc["WadiBranch"] = $wadibranch

    $wadibuild = Xml-GetNodeValue $WadiConfig_DeployOptionsXml "/DeployConfig/WadiConfigs/WadiBuild"
    if($null -eq $wadibuild)
    {
        Write-ErrorExit "WadiBuild is null in $WadiConfig_DeployOptions. Please check the file."
    }
    $kvMapTaskDesc["WadiBuild"] = $wadibuild

    $deendpoint = Select-DeployEngine $WadiConfig_DeployOptionsXml $DeployEnv
    
    if($null -eq $deendpoint)
    {
        Write-ErrorExit "There is no DEEndPoint for $DeployEnv in $WadiConfig_DeployOptions, please check the file."
        return -1;
    }

    $kvMapTaskDesc["DEEndPoint"] = $deendpoint

    $updateResult = Update-XmlFile "..\$WadiConfigFolderName\$WadiConfig_DeployTaskTemplate" $kvMapTaskDesc $WadiConfig_DeployTaskFilePath
    
    if(-1 -eq $updateResult)
    {
        Write-ErrorExit "Failed to assemble WADI Task Description File: $WadiConfig_DeployTaskFile"
    }

    Write-Host 'Copy Deployment Data...'
    $dstDataPath = [System.IO.Path]::Combine($deployInstancePath, $ToolsFolderName);
    if(![System.IO.Directory]::Exists($dstDataPath))
    {
        New-Item -path $dstDataPath -type directory -Force | Out-Null
    }

    try
    {
        Copy-LibFiles $dataFolderPath $dstDataPath
    }
    catch [System.Exception]
    {
        Write-ErrorExit "Failed to copy deployment data files to staging: $dataFolderPath ==> $dstDataPath. "
    }

    
    # Check (and update if needed) RDTools
    Write-StepSeperator '--- Updating WADI Client: RDTools'

    $rdVersion = Check-RDTools $LocalRDToolsBase $RemoteRDToolsBase 

    if($rdVersion -eq $null)
    {
        Write-ErrorExit "Failed to install or update WADI Client tool failed. Please delete $LocalRDToolsBase manually and retry."
    }

    if($DeployMethod -ieq 'wadi')
    {
        # WADI Client should run as redmond\rdauto
        $fullUserName = [System.String]::Concat($DEDomain, "`\", $DEUsername)

        # $deployInstancePath inherits ACL from the root shared folder. No need to set ACL.
        #$rights = [System.Security.AccessControl.FileSystemRights]::Read
        #Set-ShareFolderAcl $deployInstancePath $fullUserName $rights

        # Set ACL for local RDTools, and scripts
        $rights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
        Set-ShareFolderAcl $LocalRDToolsBase $fullUserName $rights
        Set-ShareFolderAcl $CurPath $fullUserName $rights

        # Kick off WADI Client
        $setupFile = "$LocalRDToolsBase\$rdVersion\wadi\Scripts\SetupDeployment.ps1";
        Write-Host "WADI Client Script is $setupFile"
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList @($fullUserName,(ConvertTo-SecureString -String $DEPassword -AsPlainText -Force))
        
        Write-StepSeperator '--- kick off the deployment'
        $SetupCmd = [System.IO.Path]::Combine($CurPath, "WadiDeploy.cmd");
        if(![System.IO.File]::Exists($SetupCmd))
        {
            Write-ErrorExit "WadiDeploy.cmd ($SetupCmd) is missing."
        }

        Write-Host "Starting $SetupCmd ..."
        Start-Process -FilePath "`"$SetupCmd`"" -ArgumentList @($setupFile, $wadiConfig_DeployTaskFilePath) -Credential $cred -NoNewWindow
    }
    elseif($DeployMethod -ieq 'local')
    {
        # Create LocalDeplRoot if not existing
        if(![System.IO.Directory]::Exists($LocalDeplRootBase))
        {
            New-Item -path $LocalDeplRootBase -type directory -Force | Out-Null
        }
        if(![System.IO.Directory]::Exists($LocalDeplRootBase))
        {
            Write-ErrorExit "Failed to create local deployment root folder $LocalDeplRootBase."
        }

        # Copy deployment instance to LocalDeplRoot
        Write-Host 'Copying deployment instance to local... and initiate Workflow Invoker'
        try
        {
            Copy-DeployItem $deployInstancePath $LocalDeplRootBase
        }
        catch [System.Exception]
        {
            Write-ErrorExit "Failed to copy deployment instance files to staging: $deployInstancePath ==> $LocalDeplRootBase. "
        }
        # Invoke
        $InvokeLocation = [System.IO.Path]::Combine($LocalDeplRootBase, $DeployInstanceName)
        $InvokerExe = [System.IO.Path]::Combine($InvokeLocation, "$ToolsFolderName\$WorkflowInvoker")
        Set-Location -Path $InvokeLocation
        Start-Process -FilePath "`"$InvokerExe`"" -ArgumentList @("$ToolsFolderName\$WorkflowFileName", $wadiConfig_SettingsFile)  -Wait -NoNewWindow
		#&$InvokerExe "$ToolsFolderName\$WorkflowFileName", $wadiConfig_SettingsFile | Out-Host
    }
    elseif($DeployMethod -ieq 'remote')
    {
        $requestCmd = [System.IO.Path]::Combine($CurPath, "InvokeDeployWorkflowRequest.cmd");

        if(![System.IO.File]::Exists($requestCmd))
        {
            Write-ErrorExit "InvokeDeployWorkflowRequest.cmd ($requestCmd) is missing."
        }

        Write-Host "Starting $requestCmd ..."

        Start-Process -FilePath "`"$requestCmd`"" -ArgumentList @($workflowDestFilePath, $wadiConfig_SettingsFilePath, $EmailTo, $ProjName, $DeployEnv) -Wait -NoNewWindow
		#&$requestCmd $workflowDestFilePath, $wadiConfig_SettingsFilePath, $EmailTo, $ProjName, $DeployEnv  | Out-Host
    }

    exit;

