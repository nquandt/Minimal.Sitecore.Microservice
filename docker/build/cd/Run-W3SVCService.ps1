function Create-EnvVariableConfigNode {
    param(
        [string]$Key,
        [string]$Value,
        [bool]$Addition
    )

    if ($Addition) {
        return "/+`"[name='$($defaultAppPool)'].environmentVariables.[name='$($Key)',value='$($Value)']`""
    }

    return "/-`"[name='$($defaultAppPool)'].environmentVariables.[name='$($Key)']`""
}

function Handle-ValuesWithQuotes {
    param(
        [string]$Value
    )
    $value = $Value -replace "'", "''"
    $value = $value -replace '"', """"
    
    return $value 
}

# List of env variables which are computer specific and should be excluded from transferred env variables
$exclusionList = @{
    "TMP" = @("C:\Users\ContainerAdministrator\AppData\Local\Temp");
    "TEMP" = @("C:\Users\ContainerAdministrator\AppData\Local\Temp");
    "USERNAME" = @("ContainerAdministrator");
    "USERPROFILE" = @("C:\Users\ContainerAdministrator");
    "APPDATA" = @("C:\Users\ContainerAdministrator\AppData\Roaming");
    "LOCALAPPDATA" = @("C:\Users\ContainerAdministrator\AppData\Local");
    "PROGRAMDATA" = @("C:\ProgramData");
    "PSMODULEPATH" = @("C:\Program Files\WindowsPowerShell\Modules", "C:\Windows\system32\WindowsPowerShell\v1.0\Modules");
    "PUBLIC" = @("C:\Users\Public");
    "USERDOMAIN" = @("User Manager");
    "ALLUSERSPROFILE" = @("C:\ProgramData");
    "PATHEXT" = @(".COM", ".EXE", ".BAT" , ".CMD" , ".VBS" , ".VBE" , ".JS" , ".JSE" , ".WSF" , ".WSH" , ".MSC");
    "PATH" = @();
    "COMPUTERNAME" = @();
    "COMSPEC" = @();
    "OS" = @();
    "PROCESSOR_IDENTIFIER" = @();
    "PROCESSOR_LEVEL" = @();
    "PROCESSOR_REVISION" = @();
    "PROGRAMFILES" = @();
    "PROGRAMFILES(X86)" = @();
    "PROGRAMW6432" = @();
    "SYSTEMDRIVE" = @();
    "WINDIR" = @();
    "NUMBER_OF_PROCESSORS" = @();
    "PROCESSOR_ARCHITECTURE" = @();
    "SYSTEMROOT" = @();
    "COMMONPROGRAMFILES" = @();
    "COMMONPROGRAMFILES(X86)" = @();
    "COMMONPROGRAMW6432" = @();
    "DRIVERDATA" = @();
}
$listWithExclusions = @{}

$allEnvVariablesList = @{}
Get-ChildItem env:* | ForEach-Object {
    $key = Handle-ValuesWithQuotes($_.name)
    $value = Handle-ValuesWithQuotes($_.value)

    $allEnvVariablesList.Add($key, @())
    $allEnvVariablesList[$key] += $value.Split(";")
}

# Exclude computer specific env variables from full list of variables
$allEnvVariablesList.Keys | ForEach-Object {
    $envVariableName = $_
    if ($exclusionList.Keys -notcontains $envVariableName) {
        $listWithExclusions.Add($envVariableName, $allEnvVariablesList[$envVariableName])
        return
    }

    if (-not ($exclusionList[$envVariableName].Count -eq 0)) {
        $valuesToInclude = @()
        $allEnvVariablesList[$envVariableName] | ForEach-Object {
            $envVariableValue = $_
            if ($exclusionList[$envVariableName] -notcontains $envVariableValue) {
                $valuesToInclude += $envVariableValue
            }
        }

        if (-not ($valuesToInclude.Count -eq 0)) {
            $listWithExclusions.Add($envVariableName, $valuesToInclude)
        }
    }
}

$formattedVariables = @{}
$listWithExclusions.Keys | ForEach-Object {
    $envVariableName = $_
    $formattedVariables.Add($envVariableName, [string]::Join(";", $listWithExclusions[$envVariableName]))
}

$appCmd = 'C:/windows/system32/inetsrv/appcmd'
$appPoolsSection = '-section:system.applicationHost/applicationPools'
$enableEditConfig = '/commit:apphost'
$defaultAppPool = 'DefaultAppPool'

# Remove existing env variables from IIS config file
Write-Output "Remove duplicating environment variables for Default Web App..."
$envVariablesFromIISConfig = @{}
[XML]$appPoolsXmlSection = $(& $appCmd @('list', 'config', $appPoolsSection, '/xml'))

$appPoolsXmlSection.SelectNodes("//add[@name='$($defaultAppPool)']/environmentVariables/add[@name]") | ForEach-Object {
    $envVariablesFromIISConfig.Add($_.name, $_.value);
}
$envVarsToRemove = $($envVariablesFromIISConfig.Keys | Where-Object { $_ -in $formattedVariables.Keys }) | ForEach-Object { Create-EnvVariableConfigNode -Key $_ -Addition $False }

& $appCmd 'set' 'config' $appPoolsSection $envVarsToRemove $enableEditConfig

# Write new env variables to iis config file
Write-Output "Setting environment variables for Default Web App..."

$setArg = "set"
$configArg = "config"

$appCmdLengthLimit = 30000
$appCmdLength = $appCmd.Length + $setArg.Length + $configArg.Length + $appPoolsSection.Length + $enableEditConfig.Length
$addArgChunkLengthLimit = $appCmdLengthLimit - $appCmdLength

$addArgChunk = @()
$addArgChunkLength = 0

$formattedVariables.Keys | ForEach-Object {
    $envVariableName = $_

    $addArg = Create-EnvVariableConfigNode -Key $envVariableName -Value $formattedVariables[$envVariableName] -Addition $True
    if ($addArg.Length -gt $addArgChunkLengthLimit) {
        throw "Environment variable '$envVariableName' can not be applied to Default Web App. appcmd command length exceeds $appCmdLengthLimit limit."
    }

    $addArgChunkLength += $addArg.Length
    if ($addArgChunkLength -gt $addArgChunkLengthLimit) {
        & $appCmd $setArg $configArg $appPoolsSection $addArgChunk $enableEditConfig

        $addArgChunk = @()
        $addArgChunk += $addArg
        $addArgChunkLength = $addArg.Length
    } else {
        $addArgChunk += $addArg
    }
}
& $appCmd $setArg $configArg $appPoolsSection $addArgChunk $enableEditConfig

Write-Output "Starting Service Monitor..."
Start-Service w3svc
& $PSScriptRoot\Wait-Service.ps1 -ServiceName W3SVC