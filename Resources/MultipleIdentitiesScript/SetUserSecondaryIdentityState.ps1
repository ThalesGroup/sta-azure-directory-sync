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
        $user = Get-MgUser -UserId $_.ObjectId -Property "id,displayName,extensions"

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
        # Prepare the update payload
        $updatePayload = @{
            "$extensionName" = $value
        }
		
        # Setting new value for the specified extension property
		Update-MgUser -UserId $user.Id -AdditionalProperties $updatePayload
		Write-Host "  " $extensionName "(new value): " $value
    }
}

function Connect-MSGraph {
    Try {
        # Get settings param  if provided
        $file = ".\settings.json"
        if ($configFile) {
            $file = $configFile
        }
        
        # Load config file
        if (Test-Path -Path $file -PathType Leaf) {
            $settings = Get-Content $file -ErrorAction Stop | Out-String | ConvertFrom-Json
            $script:AppRegistrationObjectId = $settings.appRegistrationObjectId
			write-host "App Registration Object Id: " $script:AppRegistrationObjectId
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
        $TestMgConnection = Get-MgContext
        # Connect to MSGraph
        if (!$TestMgConnection) {
            Write-Host "Connecting to MgGraph..."
            $mgContext = Connect-MgGraph -Scopes "User.Read.All", "Application.ReadWrite.All"
            if (!$mgContext){
                exit
            }
        } else {
            Write-Host "You are logged in as: " $TestMgConnection.Account
            $AskForConnection = Read-Host -Prompt "Do you want to use the above account (Y/N): "
            if ($AskForConnection.ToLower() -eq "n"){
                Disconnect-MgGraph
                Write-Host "Connecting to MgGraph..."
                $mgContext = Connect-MgGraph -Scopes "User.Read.All", "Application.ReadWrite.All"
                if (!$mgContext){
                    exit
                }
            }
        }
    }
    catch {
        Write-Error "Failed to connect to MgGraph"
        Write-Error $_.Exception.Message
        exit
    }

    Write-Host "Connected to MgGraph"
}


function Initialize-ExtensionProperties {
    $appRegistrationId = $script:AppRegistrationObjectId

    # Retrieve all extension properties for a specific application
    $extensionProperties = Get-MgApplicationExtensionProperty -ApplicationId $appRegistrationId

    # Check for an extension property that matches "_isSecondary"
    $isSecondaryProp = $extensionProperties | Where-Object { $_.Name -match "_isSecondary$" -and $_.TargetObjects -contains "User" }

    # Create or utilize the "isSecondary" property
    if (-not $isSecondaryProp) {
        # Create a new extension property
        $isSecondaryProp = Add-ExtensionProperty "isSecondary"

        $script:isSecondaryPropertyName = $isSecondaryProp.Name
        Write-Host $script:isSecondaryPropertyName " extension property created."
    } else {
        $script:isSecondaryPropertyName = $isSecondaryProp.Name
        Write-Host $script:isSecondaryPropertyName " extension property found."
    }

    # Check for an extension property that matches "_primaryObjectID"
    $primaryObjectIdProp = $extensionProperties | Where-Object { $_.Name -match "_primaryObjectId$" -and $_.TargetObjects -contains "User" }

    # Create or utilize the "isSecondary" property
    if (-not $primaryObjectIdProp) {
        # Create a new extension property
        $primaryObjectIdProp = Add-ExtensionProperty "primaryObjectId"

        $script:primaryObjectIdPropertyName = $primaryObjectIdProp.Name
        Write-Host $script:primaryObjectIdPropertyName " extension property created."
    } else {
        $script:primaryObjectIdPropertyName = $primaryObjectIdProp.Name
        Write-Host $script:primaryObjectIdPropertyName " extension property found."
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
        #create an extension variable
        return New-MgApplicationExtensionProperty -ApplicationId $appRegistrationId -BodyParameter @{"name"=$extensionName; "dataType"="String"; "targetObjects"=@("User")}
      }
}


Write-Host 'Thales Group - User Extension Properties Update'

Connect-MSGraph

Initialize-ExtensionProperties

Set-UserSecondaryIdentityState