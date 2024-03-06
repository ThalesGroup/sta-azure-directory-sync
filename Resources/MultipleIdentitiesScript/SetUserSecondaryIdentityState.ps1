<#-----------------------------------------------------------------------
MIT License

Copyright (c) 2023 Thales Group

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-----------------------------------------------------------------------#>

<#-----------------------------------------------------------------------
This script is only provided as an example on extension properties update. 
You must create and verify your scripts based on the specific requirements of 
your configuration.
-----------------------------------------------------------------------#>

param
(
    [Parameter (Mandatory = $false)]
    [object]
    $configFile,

    [Parameter (Mandatory = $false)]
    [object]
    $sourceFile
)

function Set-UserSecondaryIdentityState {
    <#
    .SYNOPSIS
    Set provided list of users Secondary Identity state.

    .DESCRIPTION
    Set-UserSecondaryIdentityState gets the provided list of users and sets their Secondary Identity state.
    For each user, it sets the IsSecondary property to the state indicated (true/false) and sets the PrimaryObjectId accordingly.

    .INPUTS
    A list of users in csv file format with the following columns: Object Id (Guid), IsSecondary (Boolean), PrimaryObjectId (Guid)
    #>

    # Load users source file
    $file = ".\source.csv"
    if ($sourceFile) {
        $file = $sourceFile
    }
    
    if (-not(Test-Path -Path $file -PathType Leaf)) {
        Write-Host "The source file '$file' was not found."
        Exit
    }

    # reads cvs with following header: 'ObjectId', 'IsSecondary', "PrimaryObjectId"
    Import-Csv -Path $file | ForEach-Object {
        $user = Get-AzureADUser -ObjectId $_.ObjectId

        if ($user) {
            Write-Host "Processing user " $user.UserPrincipalName

            Update-ExtensionProperty $user $script:isSecondaryPropertyName $_.IsSecondary

            Update-ExtensionProperty $user $script:primaryObjectIdPropertyName $_.PrimaryObjectId
            
            Write-Host
        }
        else{
            Write-Host "user '" $_.ObjectId "' not found."
        }
    }     
}

function Update-ExtensionProperty {
    param(
        [Parameter(Mandatory=$true)]
        [object] $user,

        [Parameter(Mandatory=$true)]
        [string] $extensionName,

        [Parameter(Mandatory=$true)]
        [string] $value
    )
    process {
        # Reading current value for IsSecondary extension property
        $property = ($user | Select-Object -ExpandProperty ExtensionProperty).GetEnumerator() | ?{$_.Key -eq $extensionName}
        Write-Host "  " $extensionName "(value found): " $property.Value

        #Setting new value for IsSecondary extension property
        Set-AzureADUserExtension -ObjectId $user.ObjectId -ExtensionName $extensionName -ExtensionValue $value

        Write-Host "  " $extensionName "(new value): " $value
    }
}

function Connect-AzureActiveDirectory {
    Try {
        # Get settings param  if provided
        $file = ".\settings.json"
        if ($configFile) {
            $file = $configFile
        }
        
        # Load config file
        if (Test-Path -Path $file -PathType Leaf) {
            $settings = Get-Content './settings.json' -ErrorAction Stop | Out-String | ConvertFrom-Json
            $script:ApplicationId = $settings.applicationId
        }
        else {
            Write-Host "The config file '$file' was not found."
            exit
        }
     }
    Catch {
        Write-Error "Failed to load config file"
        Write-Error $_.Exception.Message
        exit
    }   
       
    try {
        $TestAzureADConnection = Get-AzureADCurrentSessionInfo -ErrorAction SilentlyContinue
    }
    catch { }

    try {
        # Connect to Azure AD
        If (!$TestAzureADConnection) {
            Write-Host "Connecting to AzureAD..."
            $azContext = Connect-AzureAD #Connect-AzAccount
            if (!$azContext){
                exit
            }
        }

        Write-Host $result
    }
    catch {
        Write-Error "Failed to connect to Azure AD"
        Write-Error $_.Exception.Message
        exit
    }

    Write-Host "Connected to AzureAD"
}

function Initialize-ExtensionProperties {
    $extensionProperties = Get-AzureADExtensionProperty

    $isSecondaryProp = $extensionProperties | ?{$_.Name -Match "_isSecondary$"}
    if (!$isSecondaryProp -or $isSecondaryProp.TargetObjects -ne "User") {
        $isSecondaryProp = Add-ExtensionProperty "isSecondary"
        $script:isSecondaryPropertyName = $isSecondaryProp.Name
        write-host $script:isSecondaryPropertyName " extension property created."
    }
    else {
        $script:isSecondaryPropertyName = $isSecondaryProp.Name
        write-host $script:isSecondaryPropertyName " extension property found."
    }
        
    $primaryObjectIdProp = $extensionProperties | ?{$_.Name -Match "_primaryObjectID$"}
    if (!$primaryObjectIdProp -or $primaryObjectIdProp.TargetObjects -ne "User") {
        $primaryObjectIdProp = Add-ExtensionProperty "primaryObjectId"
        $script:primaryObjectIdPropertyName = $primaryObjectIdProp.Name
        write-host $script:primaryObjectIdPropertyName  " extension property created."
    }
    else {
        $script:primaryObjectIdPropertyName = $primaryObjectIdProp.Name
        write-host $script:primaryObjectIdPropertyName  " extension property found."
    }

    write-host
}

function Add-ExtensionProperty {
    param(
        [Parameter(Mandatory=$true)]
        [string] $extensionName
      )
      process {
        write-host "Creating " $extensionName "..."
        #reate an extension variable
        return New-AzureADApplicationExtensionProperty -ObjectId $script:ApplicationId -Name $extensionName -DataType "String" -TargetObjects "User"
      }
}


Write-Host 'Thales Group - User Extension Properties Update'

##entry point
#if (-not ($webhookData)) {
#    Write-Error "Webhook request received with missing RequestBody"
#    Exit
#}
#
#Grant-AccessToWebhookRequest $webhookData

Connect-AzureActiveDirectory

Initialize-ExtensionProperties

Set-UserSecondaryIdentityState