﻿Function Get-EffectiveAccess {
[CmdletBinding()]
param(
    [Parameter(
        Mandatory,
        ValueFromPipelineByPropertyName
    )]
    [ValidatePattern(
        '(?:(CN=([^,]*)),)?(?:((?:(?:CN|OU)=[^,]+,?)+),)?((?:DC=[^,]+,?)+)$'
    )][string]$DistinguishedName,
    [switch]$IncludeOrphan
)

    begin
    {
        # requires -Modules ActiveDirectory
        $ErrorActionPreference = 'Stop'
        $GUIDMap = @{}
        $result = [system.collections.generic.list[pscustomobject]]::new()
        $domain = Get-ADRootDSE
        $z = '00000000-0000-0000-0000-000000000000'
        $hash = @{
            SearchBase = $domain.schemaNamingContext
            LDAPFilter = '(schemaIDGUID=*)'
            Properties = 'name','schemaIDGUID'
            ErrorAction = 'SilentlyContinue'
        }
        $schemaIDs = Get-ADObject @hash 

        $hash = @{
            SearchBase = "CN=Extended-Rights,$($domain.configurationNamingContext)"
            LDAPFilter = '(objectClass=controlAccessRight)'
            Properties = 'name','rightsGUID'
            ErrorAction = 'SilentlyContinue'
        }
        $extendedRigths = Get-ADObject @hash

        foreach($i in $schemaIDs)
        {
            $GUIDMap.add([System.GUID]$i.schemaIDGUID,$i.name)
        }
        foreach($i in $extendedRigths)
        {
            $GUIDMap.add([System.GUID]$i.rightsGUID,$i.name)
        }
    }

    process
    {
        
        $object = Get-ADObject $DistinguishedName
        $acls = (Get-ACL "AD:$object").Access
        

        foreach($acl in $acls)
        {
            
            $objectType = if($acl.ObjectType -eq $z)
            {
                'All Objects (Full Control)'
            }
            else
            {
                $GUIDMap[$acl.ObjectType]
            }

            $inheritedObjType = ($acl.InheritedObjectType -eq $z)
            {
                'Applied to Any Inherited Object'
            }
            else
            {
                $GUIDMap[$acl.InheritedObjectType]
            }

            $result.Add(
                [PSCustomObject]@{
                    IdentityReference = $acl.IdentityReference
                    AccessControlType = $acl.AccessControlType
                    ActiveDirectoryRights = $acl.ActiveDirectoryRights
                    ObjectType = $objectType
                    InheritedObjectType = $inheritedObjType
                    InheritanceType = $acl.InheritanceType
                    IsInherited = $acl.IsInherited
            })
        }
        
        if(-not $IncludeOrphan.IsPresent)
        {
            $result | Sort-Object IdentityReference |
            Where-Object {$_.IdentityReference -notmatch 'S-1-*'}
            return
        }

        return $result | Sort-Object IdentityReference
    }
}