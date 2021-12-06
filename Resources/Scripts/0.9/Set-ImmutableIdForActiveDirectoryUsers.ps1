<#-----------------------------------------------------------------------
MIT License

Copyright (c) 2021 Thales Group

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
    [Parameter (Mandatory = $false)]
    [object]
    $webhookData
)

function Set-ImmutableIdForActiveDirectoryUsers {  
    <#
    .SYNOPSIS
    Set ImmutableId to Azure Active Directory users when missing.

    .DESCRIPTION
    Set-ImmutableIdForActiveDirectoryUsers gets all the AD users with a missing ImmutableId.
    For each user, it generates a unique ImmutableId and sets it to the user object in AD.

    .INPUTS
    None
    #>   
    Write-Verbose "Starting execution to set immutableId at $(Get-Date)"

    Connect-AzureActiveDirectory

    $usersBatchSize = 5 #35000 for testing only
    $userIdsWithMissingImmutableId = Read-UsersBatchWithMissingImmutableId $usersBatchSize

    if ($userIdsWithMissingImmutableId) {
        Write-Output "Updating Immutable Id for $($userIdsWithMissingImmutableId.count) AzureAD users"
        
        Set-UserImmutableId $userIdsWithMissingImmutableId
    }
    else {
        Write-Output "No Azure AD user found with missing ImmutableId"
    }

    Stop-ScriptExecution
}

function Connect-AzureActiveDirectory {
    Try {
        $requiredAzureModule = "AzureAD"
        if (-not (Get-Module -ListAvailable -Name $requiredAzureModule)) {
            Write-Error "Missing required Azure module '$requiredAzureModule'"
            Stop-ScriptExecution
        }

        Import-Module AzureAD

        # default connection name
        $connectionName = "AzureRunAsConnection"

        $servicePrincipalConnection = Get-AutomationConnection –Name $connectionName  

        write-output "Logging in to Azure AD"
        Connect-AzureAD –TenantId $servicePrincipalConnection.TenantId `
            –ApplicationId $servicePrincipalConnection.ApplicationId `
            –CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
    }
    Catch {
        Write-Error "Failed to establish connection with Azure AD"
        Write-Error $_.Exception.Message

        Stop-ScriptExecution
    }   
}

function Read-UsersBatchWithMissingImmutableId($acceptedBatchSize) {
    $usersWithMissingImmutableId = $null
    $acceptedUpnChars = 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
        'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '-', '_', '!', '#', '^', '~', ''''''

    for ($i=0; $i -lt $($acceptedUpnChars.count); $i++) {
        $searchElementChar = $acceptedUpnChars[$i]
        $usersBatchFromAD = @(Get-AzureADUser -Filter "startswith(userPrincipalName, '$searchElementChar')" | Where-Object {$null -eq $_.ImmutableId} | Select-Object ObjectId)

        if($usersBatchFromAD) {
            Write-Debug "$($usersBatchFromAD.count) users found with missing ImmutableId where UPN starts with '$searchElementChar'"
            
            if (-not($usersWithMissingImmutableId)) {
                $usersWithMissingImmutableId = $usersBatchFromAD
            }
            else {
                $usersWithMissingImmutableId = $usersWithMissingImmutableId + $usersBatchFromAD            
            }

            if ($usersWithMissingImmutableId.count -ge $acceptedBatchSize) {
                Write-Output "Updating $($usersWithMissingImmutableId.count) users with missing ImmutableId, remaining users will be processed in the next iteration(s)"
                break
            }
        }
        else {
            Write-Debug "No user found with missing ImmutableId where UPN starts with '$searchElementChar'"
        }

        $usersBatchFromAD = $null
    }

    return $usersWithMissingImmutableId
}

function Set-UserImmutableId($userIdsWithMissingImmutableId) {
    if ($userIdsWithMissingImmutableId) {
        foreach ($user in $userIdsWithMissingImmutableId)
        {
            Try {
                $bytes=[System.Text.Encoding]::ASCII.GetBytes($user.ObjectId)
                $immutableId =[Convert]::ToBase64String($bytes)
                Set-AzureADUser -ObjectId $user.ObjectId -ImmutableId $immutableId
                
                Compare-UserImmutableIdWithAD $user.ObjectId $immutableId
            }
            Catch {
                Write-Error "Exception occured while setting ImmutableId for Azure User $($user.ObjectId)"
                
                $ImmutableIdConflictMessage = "Same value for property immutableId already exists"
                if ($_.Exception.Message | Select-String -Pattern $ImmutableIdConflictMessage -SimpleMatch) {
                    Write-Warning "$ImmutableIdConflictMessage, trying to set different value"

                    Set-UserImmutableIdEnrichedValue $user
                }
                else {
                    Write-Error $_.Exception.Message
                }
            }
        }     
    }
    else {
        Write-Error "Invalid request to set ImmutableId for empty list of users"
    }

    Write-Verbose "Adding ImmutableId to AD users completed"
}

function Compare-UserImmutableIdWithAD($userObjectId, $userImmutableId) {
    $userToValidate = Get-AzureADUser -ObjectId $userObjectId

    if ($userToValidate.ImmutableId.equals($userImmutableId)) {
        Write-Verbose "Successfully assigned ImmutableId to user $userObjectId"
    }
    else {
        Write-Error "Failed to assign ImmutableId to user $userObjectId"
    }
}

function Set-UserImmutableIdEnrichedValue($userObjectId) {
    Try {
        $enrichedObjectId = $userObjectId.ObjectId + (Get-Random -Minimum 1 -Maximum 9)
        $bytes=[System.Text.Encoding]::ASCII.GetBytes($enrichedObjectId)
        $ImmutableId =[Convert]::ToBase64String($bytes)

        Set-AzureADUser -ObjectId $userObjectId.ObjectId -ImmutableId $ImmutableId
                
        Compare-UserImmutableIdWithAD $userObjectId.ObjectId $ImmutableId
    }
    Catch {
        Write-Error "Exception occured while setting enriched ImmutableId for Azure User $($userObjectId.ObjectId)"
        Write-Error $_.Exception.Message
    }
}

function Grant-AccessToWebhookRequest($webhookRequestData, $internalWebhookSecret) {
    if($webhookRequestData.RequestBody) {
        Write-Verbose "Webhook request received with body: $($webhookRequestData.RequestBody)"
        
        try {
            $webhookBodyObject = ConvertFrom-JSON -InputObject $webhookRequestData.RequestBody
        }
        catch {
            Write-Error "Failed to parse Webhook RequestBody information"
            Write-Error $_.Exception.Message
            Exit
        }

        $webhookRequestId = $webhookBodyObject.Id
        $webhookRequestSecret = $webhookBodyObject.Secret
        $webhookRequestCallBackUrl = $webhookBodyObject.CallBackUrl
        
        if (-not($webhookRequestId -and $webhookRequestSecret -and $webhookRequestCallBackUrl)) {
            Write-Error "Webhook request received with missing information"
            Exit
        }

        $webhookRequestUniqueId = "SetImmutableIdForAzureADUsers"
        $global:globalCallBackUrl = $webhookRequestCallBackUrl
     
        if (-not($internalWebhookSecret)) {
            Write-Error "Missing internally saved secret value for Webhook request"
            Stop-ScriptExecution
        }

        $decodedSecret = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($webhookRequestSecret))

        if (-not($webhookRequestId -eq $webhookRequestUniqueId -and $decodedSecret -eq $internalWebhookSecret)) {
            Write-Error "Webhook request unauthorized"
            Stop-ScriptExecution
        }

        Write-Verbose "Webhook request data validated and authenticated"
    }
    else {
        Write-Error "Webhook request received with invalid RequestBody"
        Exit
    }
}

function Stop-ScriptExecution() {
    if ($globalCallBackUrl) {
        Invoke-RestMethod -Method post -Uri $globalCallBackUrl
        write-output "Posted Webhook request to unsubscribe"
    }
    else {
        Write-Warning "Missing call back URL for the webhook"
    }
    
    Write-Verbose "Completed script execution to set immutableId at $(Get-Date)"
    Exit
}

#entry point
$webhookRequestSecret = "26eeb1b8-c9ff-4f36-a198-2b0729b6a252"

if(-not ($webhookData)) {
    Write-Error "Webhook request received with missing RequestBody"
    Exit
}

Grant-AccessToWebhookRequest $webhookData $webhookRequestSecret

Set-ImmutableIdForActiveDirectoryUsers
