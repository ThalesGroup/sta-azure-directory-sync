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

    $usersBatchSize = 25000
    $userIdsWithMissingImmutableId = Read-UsersBatchWithMissingImmutableId $usersBatchSize

    if ($userIdsWithMissingImmutableId) {
        Write-Output "Updating Immutable Id for $($userIdsWithMissingImmutableId.count) AzureAD users"

        $processingBatchSize = 100
        if ($userIdsWithMissingImmutableId.count -gt $processingBatchSize) {
            while($userIdsWithMissingImmutableId) {
                $processingSlice = $userIdsWithMissingImmutableId | Select-Object -First $processingBatchSize

                Set-UserImmutableId $processingSlice

                $userIdsWithMissingImmutableId = $userIdsWithMissingImmutableId | Select-Object -Skip $processingBatchSize

                # Time for network sockets to close, since runbooks limits the number of open network sockets at given time
                Start-Sleep -Seconds 10
            }
        }
        else {
            Set-UserImmutableId $userIdsWithMissingImmutableId
        }

        Write-Output "Successfully assigned Immutable Id to $($userIdsWithMissingImmutableId.count) AzureAD user(s)"
    }
    else {
        Write-Output "No Azure AD user found with missing ImmutableId"
    }

    Stop-ScriptExecution
}

function Connect-AzureActiveDirectory {
    Try {
        $requiredAzureModule = "Microsoft.Graph.Users"
        if (-not (Get-Module -ListAvailable -Name $requiredAzureModule)) {
            Write-Error "Missing required Azure module '$requiredAzureModule'"
            Stop-ScriptExecution
        }

        # default connection name
        $connectionName = "AzureRunAsConnection"

        $servicePrincipalConnection = Get-AutomationConnection –Name $connectionName  

        write-output "Logging in to Azure AD"
        Connect-MgGraph -ClientID $servicePrincipalConnection.ApplicationId `
                -TenantId $servicePrincipalConnection.TenantId `
                -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
    }
    Catch {
        Write-Error "Failed to establish connection with Azure AD"
        Write-Error $_.Exception.Message

        Stop-ScriptExecution
    }   
}

function Read-UsersBatchWithMissingImmutableId($acceptedBatchSize) {
    $usersWithMissingImmutableId = @()
    $acceptedUpnChars = 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
        'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '-', '_', '!', '#', '^', '~', ''''''

	$serviceAccount = "On-Premises Directory Synchronization Service Account"

    for ($i=0; $i -lt $($acceptedUpnChars.count); $i++) {
        $searchElementChar = $acceptedUpnChars[$i]
        $usersBatchFromAD = @(Get-MgUser  -All -Property "Id,OnPremisesImmutableId,DisplayName" -Filter "startswith(userPrincipalName, '$searchElementChar')" | Where-Object {$null -eq $_.OnPremisesImmutableId} | Where-Object {$serviceAccount -ne $_.DisplayName} | Select-Object -ExpandProperty Id)
        
        if($usersBatchFromAD) {
            Write-Debug "$($usersBatchFromAD.count) users found with missing ImmutableId and when UPN starts with '$searchElementChar'"
            
            $usersWithMissingImmutableId = $usersWithMissingImmutableId + $usersBatchFromAD          

            if (($usersWithMissingImmutableId) -and ($usersWithMissingImmutableId.count -ge $acceptedBatchSize)) {
                Write-Warning "Updating $($usersWithMissingImmutableId.count) users with missing ImmutableId, remaining users will be processed in the next iteration(s)"
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
        foreach ($userId in $userIdsWithMissingImmutableId)
        {
            if ($userId) {
                Try {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes($userId)
                    $immutableId = [Convert]::ToBase64String($bytes)

                    $updateUserAction = Update-MgUser -PassThru -UserId $userId -OnPremisesImmutableId $immutableId
                    
                    if ($updateUserAction -ne $true) {
                        Write-Error "Failed to assign ImmutableId to AD user with Id: $userId"
                    }
                }
                Catch {
                    Write-Error "Exception occured while setting ImmutableId for Azure user: $($userId)"
                    
                    $ImmutableIdConflictMessage = "Same value for property immutableId already exists"
                    if ($_.Exception.Message | Select-String -Pattern $ImmutableIdConflictMessage -SimpleMatch) {
                        Write-Warning "$ImmutableIdConflictMessage, trying to set different value"
    
                        Set-UserImmutableIdEnrichedValue $userId
                    }
                    else {
                        Write-Error $_.Exception.Message
                    }
                }
            }
        }
    }
    else {
        Write-Error "Invalid request to set ImmutableId for empty list of users"
    }
}

function Set-UserImmutableIdEnrichedValue($userObjectId) {
    Try {
        $enrichedObjectId = $userObjectId + (Get-Random -Minimum 1 -Maximum 9)
        $bytes=[System.Text.Encoding]::ASCII.GetBytes($enrichedObjectId)
        $ImmutableId =[Convert]::ToBase64String($bytes)

        $updateUserAction = Update-MgUser -PassThru  -UserId $userObjectId -OnPremisesImmutable

        if ($updateUserAction -eq $false) {
            Write-Error "Failed to assign enriched ImmutableId to AD user with Id: $userId"
        }
    }
    Catch {
        Write-Error "Exception occured while setting enriched ImmutableId for Azure User $($userObjectId)"
        Write-Error $_.Exception.Message
    }
}

function Grant-AccessToWebhookRequest($webhookRequestData) {
    if($webhookRequestData.RequestBody) {
        Write-Verbose "Webhook request received with body: $($webhookRequestData.RequestBody)"
        
        try {
            $webhookBodyObject = ConvertFrom-JSON -InputObject $webhookRequestData.RequestBody

            if (-not($webhookBodyObject.CallBackUrl)) {
                Write-Error "Webhook request received with missing information"
                Exit
            }
    
            $global:globalCallBackUrl = $webhookBodyObject.CallBackUrl
    
            $expectedWebhookId = Get-AutomationVariable -Name 'WebhookId'
            $expectedWebhookSecret = Get-AutomationVariable -Name 'WebhookSecret'

            if (-not($webhookBodyObject.Id -eq $expectedWebhookId -and $webhookBodyObject.Secret -eq $expectedWebhookSecret)) {
                Write-Error "Webhook request unauthorized"
                Stop-ScriptExecution
            }
    
            Write-Verbose "Webhook request data validated and authenticated"
        }
        catch {
            Write-Error "Failed to parse Webhook RequestBody information"
            Write-Error $_.Exception.Message
            Exit
        }
    }
    else {
        Write-Error "Webhook request received with empty RequestBody"
        Exit
    }
}

function Stop-ScriptExecution() {
    if ($globalCallBackUrl) {
        Invoke-RestMethod -Method post -Uri $globalCallBackUrl
        Write-Debug "Webhook unsubscribed"
    }
    else {
        Write-Warning "Missing call back URL for the webhook"
    }
    
    Disconnect-MgGraph
    Write-Verbose "Completed script execution to set immutableId at $(Get-Date)"
    Exit
}

#entry point
if(-not ($webhookData)) {
    Write-Error "Webhook request received with missing RequestBody"
    Exit
}

Grant-AccessToWebhookRequest $webhookData

Set-ImmutableIdForActiveDirectoryUsers
