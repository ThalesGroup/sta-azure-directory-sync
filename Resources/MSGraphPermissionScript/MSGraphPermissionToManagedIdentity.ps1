$ObjectId = Read-Host -Prompt "Please provide Object ID from Automation Account's Identity management "

$ServicePrincipalID = $ObjectId

$GraphAppId = "00000003-0000-0000-c000-000000000000"
$PermissionName = "User.ReadWrite.All"

$GraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"
$AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}

Try {
    $MSI = (Get-AzureADServicePrincipal -ObjectId $ServicePrincipalID)
    $GraphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$GraphAppId'"
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    if ($null -eq $AppRole) { 
        Write-Error "Unable to get scope $scope";
        exit 
    }
    New-AzureAdServiceAppRoleAssignment -ObjectId $MSI.ObjectId -PrincipalId $MSI.ObjectId -ResourceId $GraphServicePrincipal.ObjectId -Id $AppRole.Id
    Write-Host "Assined Scope $scope"
} Catch {
    Write-Error $_.Exception.Message
}