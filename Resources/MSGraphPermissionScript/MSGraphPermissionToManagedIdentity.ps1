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

try {
    $TestMgConnection = Get-MgContext
} catch {
    Write-Error $_.Exception.Message
}

try {
    if (!$TestMgConnection) {
        Write-Host "Connecting to MgGraph..."
        $mgContext = Connect-MgGraph -Scopes "Application.Read.All, Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All"
        if (!$mgContext){
            exit
        }
    } else {
        Write-Host "You are logged in as: " $TestMgConnection.Account
        $AskForConnection = Read-Host -Prompt "Do you want to use the above account to assign permission (Y/N): "
        if ($AskForConnection.ToLower() -eq "n"){
            Disconnect-MgGraph
            Write-Host "Connecting to MgGraph..."
            $mgContext = Connect-MgGraph -Scopes "Application.Read.All, Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All"
            if (!$mgContext){
                exit
            }
        }
    }
    Write-Host "Connected to MgGraph"
    $ServicePrincipalIdFromUser = Read-Host -Prompt "Please provide Object ID from Automation Account's Identity management "
    $GraphAppId = "00000003-0000-0000-c000-000000000000"
    $PermissionName = "User.ReadWrite.All"
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    $MSI = (Get-MgServicePrincipal -ServicePrincipalId $ServicePrincipalIdFromUser)
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object {$_.Value -eq $PermissionName -and $_.AllowedMemberTypes -contains "Application"}
    if ($null -eq $AppRole) {
        Write-Error "Unable to assign permission";
        exit
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MSI.Id -PrincipalId $MSI.Id -ResourceId $GraphServicePrincipal.Id -AppRoleId $AppRole.Id
    Write-Host "Assined permission"
} Catch {
    Write-Error $_.Exception.Message
}