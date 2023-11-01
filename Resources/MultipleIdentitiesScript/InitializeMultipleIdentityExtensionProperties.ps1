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

param
(
#    [Parameter (Mandatory = $false)]
#    [object]
#    $webhookData
    
    [Parameter (Mandatory = $false)]
    [object]
    $configFile
)

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


Write-Host 'Thales Group - User Extension Properties Initialization'

##entry point
#if (-not ($webhookData)) {
#    Write-Error "Webhook request received with missing RequestBody"
#    Exit
#}
#
#Grant-AccessToWebhookRequest $webhookData

Connect-AzureActiveDirectory

Initialize-ExtensionProperties
