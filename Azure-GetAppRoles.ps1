# Get all the app role assignments, 
# Resolving the app role ID to it's display name. 
# Output everything to a sql table.

#Import required modules
Import-Module AzureAD
Import-Module SqlServer

$User = "YOURAUTOMATIONACCOUNT"

[string][ValidateNotNullOrEmpty()] $userPassword = Get-AutomationVariable -Name 'AUTOMATIONACCOUNTPWD'
[string][ValidateNotNullOrEmpty()] $sqlPassword = Get-AutomationVariable -Name 'AZUSQLPWD'


$Password = ConvertTo-SecureString -String $userPassword -AsPlainText -Force
$Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $User, $Password

Connect-AzureAD -Credential $Credential

$app_name = "AZUREAPPNAME"
$ItemCollection = @()

$roleAssignment = Get-AzureADServicePrincipal -Filter "displayName eq '$app_name'" | % {

  $appRoles = @{ "$([Guid]::Empty.ToString())" = "(default)" }
  $_.AppRoles | % { $appRoles[$_.Id] = $_.DisplayName }

  # Get the app role assignments for this app, and add a field for the app role name


  Get-AzureADServiceAppRoleAssignment -ObjectId ($_.ObjectId) | % {
    $_ | Add-Member "AppRoleDisplayName" $appRoles[$_.Id] -Passthru
  }
} | Select-Object PrincipalDisplayName, PrincipalType, AppRoleDisplayName, PrincipalId

  Write-Output "Getting the app role assignments for: " $app_name

$roleAssignment | ForEach-Object {

    $role = $_.AppRoleDisplayName
    $group = $_.PrincipalDisplayName
    $userID = $_.PrincipalId
    
    if($_.PrincipalType -eq "Group") {

            $members = Get-AzureADGroupMember -ObjectId (Get-AzureADGroup -Filter "DisplayName eq '$($_.PrincipalDisplayName)'" -Top 1).ObjectId
            $members | ForEach-Object {
            $ExportItem = New-Object PSObject 
            $ExportItem | Add-Member -MemberType NoteProperty -name "GroupName" -value $group
            $ExportItem | Add-Member -MemberType NoteProperty -Name "RoleAssigned" -value $role
            $ExportItem | Add-Member -MemberType NoteProperty -name "DisplayName" -value $_.DisplayName
            $ExportItem | Add-Member -MemberType NoteProperty -Name "Department" -value $_.Department
            $ExportItem | Add-Member -MemberType NoteProperty -Name "Title" -value $_.JobTitle
            $ExportItem | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -value $_.UserPrincipalName            
            $ItemCollection += $ExportItem
        }      
    }
    else {

        $members = Get-AzureADUser -ObjectId $userID | Select-Object DisplayName, UserPrincipalName, Department, JobTitle
        $members | ForEach-Object {
          $ExportItem = New-Object PSObject
          $ExportItem | Add-Member -MemberType NoteProperty -name "GroupName" -value $group
          $ExportItem | Add-Member -MemberType NoteProperty -Name "RoleAssigned" -value $role
          $ExportItem | Add-Member -MemberType NoteProperty -name "DisplayName" -value $_.DisplayName
          $ExportItem | Add-Member -MemberType NoteProperty -Name "Department" -value $_.Department
          $ExportItem | Add-Member -MemberType NoteProperty -Name "Title" -value $_.JobTitle
          $ExportItem | Add-Member -MemberType NoteProperty -Name "UserPrincipalName" -value $_.UserPrincipalName
          $ItemCollection += $ExportItem
        }
   }
}

 Write-Output "Export roles complete."

 #truncate data in the created table
 Write-Output "Truncating table before inserting data."
 $TruncateTableData = "TRUNCATE TABLE [DATABASENAME].[dbo].[TABLENAME]"
 Try {
   Invoke-Sqlcmd -Database 'DATABASENAME' -ServerInstance 'azuresqlserver.database.secure.windows.net' -Username 'SQLADMINACCOUNT' -Password $sqlPassword -OutputSqlErrors $True -Query $TruncateTableData
 }
 Catch {
  $ErrorMessage = $_.Exception.Message
  $ErrorMessage
 }

foreach($item in $ItemCollection )
{
  $GroupName = $item.GroupName
  $RoleAssigned = $item.RoleAssigned
  $DisplayName = $item.DisplayName
  $Department = $item.Department
  $Title = $item.Title
  $UserPrincipalName = $item.UserPrincipalName

  $TableData = "
  INSERT INTO [DATABASENAME].[dbo].[TABLENAME]
    ([GroupName]
    ,[RoleAssigned]
    ,[DisplayName]
    ,[Department]
    ,[Title]
    ,[UserPrincipalName]) 
  VALUES ('$GroupName', '$RoleAssigned', '$DisplayName', '$Department', '$Title', '$UserPrincipalName')
  GO
  "
 #insert data into the table
Write-Output "Inserting data: $GroupName, $RoleAssigned, $DisplayName, $Department, $Title, $UserPrincipalName"
  
  Try {
    Invoke-Sqlcmd -Database 'DATABASENAME' -ServerInstance 'azuresqlserver.database.secure.windows.net' -Username 'SQLADMINACCOUNT' -Password $sqlPassword -OutputSqlErrors $True -Query $TableData
  }
  Catch {
    $ErrorMessage = $_.Exception.Message
    $ErrorMessage
  }
}