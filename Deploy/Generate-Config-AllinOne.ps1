Param (
    [parameter(Mandatory=$true)][string]$resourceGroup,
    [parameter(Mandatory=$true)][string]$sqlPwd,
    [parameter(Mandatory=$false)][string]$servicePrincipalId,
    [parameter(Mandatory=$false)][string]$servicePrincipalSecret,
    [parameter(Mandatory=$false)][string]$tenant,
    [parameter(Mandatory=$false)][string]$outputFile=$null,
    [parameter(Mandatory=$false)][string]$gvaluesTemplate=".\\helm\\gvalues.template",
    [parameter(Mandatory=$false)][bool]$forcePwd=$false
)

function EnsureAndReturnFistItem($arr, $restype) {
    if (-not $arr -or $arr.Length -ne 1) {
        Write-Host "Fatal: No $restype found (or found more than one)" -ForegroundColor Red
        exit 1
    }
    return $arr[0]
}

# az login using service principle
if ($servicePrincipalId){
    az login --tenant $tenant --service-principal --username $servicePrincipalId --password $servicePrincipalSecret
}


# Check the rg
$rg=$(az group show -n $resourceGroup -o json | ConvertFrom-Json)

if (-not $rg) {
    Write-Host "Fatal: Resource group not found" -ForegroundColor Red
    exit 1
}

### Getting Resources

$sqlsrv=$(az sql server list -g $resourceGroup --query "[].{administratorLogin:administratorLogin, name:name, fullyQualifiedDomainName: fullyQualifiedDomainName}" -o json | ConvertFrom-Json)
$sqlsrv=EnsureAndReturnFistItem $sqlsrv "SQL Server"
Write-Host "Sql Server: $($sqlsrv.name)" -ForegroundColor Yellow

### Getting postgreSQL info
$pg=$(az postgres server list -g $resourceGroup --query "[].{administratorLogin:administratorLogin, name:name, fullyQualifiedDomainName: fullyQualifiedDomainName}" -o json | ConvertFrom-Json)
$pg=EnsureAndReturnFistItem $pg "PostgreSQL"
Write-Host "PostgreSQL Server: $($pg.name)" -ForegroundColor Yellow

## Getting storage info
$storage=$(az storage account list -g $resourceGroup --query "[].{name: name, blob: primaryEndpoints.blob}" -o json | ConvertFrom-Json)
$storage=EnsureAndReturnFistItem $storage "Storage Account"
Write-Host "Storage Account: $($storage.name)" -ForegroundColor Yellow

## Getting CosmosDb info
$docdb=$(az cosmosdb list -g $resourceGroup --query "[?kind=='GlobalDocumentDB'].{name: name, kind:kind, documentEndpoint:documentEndpoint}" -o json | ConvertFrom-Json)
$docdb=EnsureAndReturnFistItem $docdb "CosmosDB (Document Db)"
$docdbKey=$(az cosmosdb list-keys -g $resourceGroup -n $docdb.name -o json --query primaryMasterKey | ConvertFrom-Json)
Write-Host "Document Db Account: $($docdb.name)" -ForegroundColor Yellow

$mongodb=$(az cosmosdb list -g $resourceGroup --query "[?kind=='MongoDB'].{name: name, kind:kind}" -o json | ConvertFrom-Json)
$mongodb=EnsureAndReturnFistItem $mongodb "CosmosDB (MongoDb mode)"
$mongodbKey=$(az cosmosdb list-keys -g $resourceGroup -n $mongodb.name -o json --query primaryMasterKey | ConvertFrom-Json)
Write-Host "Mongo Db Account: $($mongodb.name)" -ForegroundColor Yellow

if ($forcePwd) {
    Write-Host "Reseting password to $sqlPwd for SQL server $($sqlsrv.name)" -ForegroundColor Yellow
    az sql server update -n $sqlsrv.name -g $resourceGroup -p $sqlPwd

    Write-Host "Reseting password to $sqlPwd for PostgreSQL server $($pg.name)" -ForegroundColor Yellow
    az postgres server update -n $pg.name -g $resourceGroup -p $sqlPwd
}

## Get AksHost
$aksName = $(az aks list -g $resourceGroup --query "[].{name:name}" -o json | ConvertFrom-Json)
$aksName=EnsureAndReturnFistItem $aksName "aksName"
$aksHost=$(az aks show -n $aksName.name -g $resourceGroup --query addonProfiles.httpapplicationrouting.config.HTTPApplicationRoutingZoneName -o json | ConvertFrom-Json)
if (-not $aksHost) {
    $aksHost=$(az aks show -n $aksName.name -g $resourceGroup --query addonProfiles.httpApplicationRouting.config.HTTPApplicationRoutingZoneName -o json | ConvertFrom-Json)
}
Write-Host "aksHost: $($aksHost)" -ForegroundColor Yellow

## Showing Values that will be used

Write-Host "===========================================================" -ForegroundColor Yellow
Write-Host "gvalues file will be generated with values:"

$tokens=@{}
$tokens.dbhost=$sqlsrv.fullyQualifiedDomainName
$tokens.dbuser=$sqlsrv.administratorLogin
$tokens.dbpwd=$sqlPwd

$tokens.pghost=$pg.fullyQualifiedDomainName
$tokens.pguser="$($pg.administratorLogin)@$($pg.name)"
$tokens.pgpwd=$sqlPwd

$tokens.carthost=$docdb.documentEndpoint
$tokens.cartauth=$docdbKey

$tokens.couponsuser=$mongodb.name
$tokens.couponshost="$($mongodb.name).documents.azure.com"
$tokens.couponspwd=$mongodbKey

$tokens.storage=$storage.blob

$tokens.akshost=$aksHost

# Standard fixed tokens
$tokens.ingressclass="addon-http-application-routing"
$tokens.secissuer="TTFakeLogin"
$tokens.seckey="nEpLzQJGNSCNL5H6DIQCtTdNxf5VgAGcBbtXLms1YDD01KJBAs0WVawaEjn97uwB"

Write-Host ($tokens | ConvertTo-Json) -ForegroundColor Yellow

Write-Host "===========================================================" -ForegroundColor Yellow

$content = Get-Content -Raw $gvaluesTemplate

$tokens.Keys | % ($_) {
  $content = $content -replace "{{$_}}",  $tokens[$_]
}

if ([string]::IsNullOrEmpty($outputFile)) {
    Write-Output $content
}
else {
    Set-Content -Path $outputFile -Value $content
}






