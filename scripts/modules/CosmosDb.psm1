# helper functions for using the DocumentDB REST API.

function GetCosmosDbAccountKey() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName
    )

    $dbAcctKeys = az cosmosdb list-keys --name $AccountName --resource-group $ResourceGroupName | ConvertFrom-Json
    return $dbAcctKeys.primaryMasterKey
}

function EnsureCosmosDbAccount() {
    param(
        [string]$AccountName,
        [ValidateSet("SQL", "Gremlin", "Mongo", "Cassandra", "Table")]
        [string]$API,
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$ConsistencyLevel = "Session"
    )

    $dbAcct = az cosmosdb list --query "[?name=='$AccountName']" | ConvertFrom-Json
    if (!$dbAcct) {
        if ($API -eq "Gremlin") {
            LogInfo "`tCreating cosmosDB account $AccountName with gremlin api..." -ForegroundColor White
            az cosmosdb create `
                --resource-group $ResourceGroupName `
                --name $AccountName `
                --capabilities EnableGremlin `
                --locations $Location=0 `
                --default-consistency-level $ConsistencyLevel
        }
        elseif ($API -eq "Mongo") {
            LogInfo "`tCreating cosmosDB account $AccountName with mongodb api..." -ForegroundColor White
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --default-consistency-level ConsistentPrefix --kind MongoDB --locations "$Location=0" | Out-Null
        }
        elseif ($API -eq "Cassandra") {
            LogInfo "`tCreating cosmosDB account $AccountName with cassandra api..." -ForegroundColor White
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --kind MongoDB --locations $Location=0 --capabilities EnableCassandra | Out-Null
        }
        elseif ($API -eq "Table") {
            LogInfo "`tCreating cosmosDB account $AccountName with table api..." -ForegroundColor White
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --kind MongoDB --locations $Location=0 --capabilities EnableTable | Out-Null
        }
        else {
            LogInfo "`tCreating cosmosDB account $AccountName with sql api..." -ForegroundColor White
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --default-consistency-level Session --kind GlobalDocumentDB --locations "$Location=0" | Out-Null
        }
    }
    else {
        LogInfo "`tCosmosDB account $AccountName is already created." -ForegroundColor Yellow
    }
}

function IsCollectionExist() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName,
        [string]$DbName,
        [string]$CollectionName
    )

    $collections = az cosmosdb collection list `
        --db-name $DbName `
        --name $AccountName `
        --resource-group $ResourceGroupName | ConvertFrom-Json
    $found = $collections | Where-Object { $_.id -eq $CollectionName }
    return $null -ne $found;
}

function EnsureCollectionExists() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName,
        [string]$DbName,
        [string]$CollectionName,
        [string]$CosmosDbKey,
        [string]$PartitionKeyPath,
        [int]$Throughput = 1000
    )

    $collectionExists = IsCollectionExist `
        -AccountName $AccountName `
        -ResourceGroupName $ResourceGroupName `
        -DbName $DbName `
        -CollectionName $CollectionName

    if (!$collectionExists) {
        if ($null -ne $PartitionKeyPath -and $PartitionKeyPath -ne "") {
            LogInfo "Creating collection '$CollectionName'...throughput=$Throughput, partition=$PartitionKeyPath" -ForegroundColor White

            az cosmosdb collection create `
                --collection-name $CollectionName `
                --db-name $DbName `
                --resource-group $ResourceGroupName `
                --name $AccountName `
                --throughput $Throughput `
                --partition-key-path $PartitionKeyPath | Out-Null
        }
        else {
            LogInfo "Creating collection '$CollectionName' without partition...throughput=$Throughput" -ForegroundColor White

            CreateCollection `
                -Endpoint "https://$($AccountName).documents.azure.com:443" `
                -MasterKey $CosmosDbKey `
                -DatabaseName $DbName `
                -CollectionName $CollectionName `
                -PartitionKey $PartitionKeyPath `
                -Throughput $Throughput | Out-Null
        }
    }
    else {
        LogInfo "Collection '$CollectionName' is already created." -ForegroundColor White
    }
}

function DeleteCollection() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName,
        [string]$DbName,
        [string]$CollectionName,
        [string]$CosmosDbKey
    )

    $collectionExists = IsCollectionExist `
        -AccountName $AccountName `
        -ResourceGroupName $ResourceGroupName `
        -DbName $DbName `
        -CollectionName $CollectionName
    if ($collectionExists) {
        LogInfo -Message "Deleting collection '$CollectionName'..."
        az cosmosdb collection delete `
            --name $AccountName `
            --resource-group-name $ResourceGroupName `
            --key $docdbPrimaryMasterKey `
            --db-name $bootstrapValues.cosmosdb.docDb.db `
            --collection-name $CollectionName | Out-Null
    }
    else {
        LogInfo -Message "Collection '$CollectionName' already deleted"
    }
}

function EnsureDatabaseExists($Endpoint, $MasterKey, $DatabaseName) {
    $uri = CombineUris $Endpoint "/dbs"
    $headers = BuildHeaders -verb POST -resType dbs -masterkey $MasterKey
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body (@{id = $DatabaseName } | ConvertTo-Json)
    }
    catch {
        if ($_.Exception.Response.StatusCode -ne 409) {
            throw
        }
        # else already created
    }
}

function CreateCollection($Endpoint, $MasterKey, $DatabaseName, $CollectionName, $PartitionKey, $Throughput = 1000) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls"
    $headers = BuildHeaders -verb POST -resType colls -resourceId "dbs/$DatabaseName" -masterkey $MasterKey -throughput $Throughput

    $collectionJson = BuildDefaultCollection -CollectionName $CollectionName -PartitionKey $PartitionKey
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $collectionJson
}

function RemoveCollection($Endpoint, $MasterKey, $DatabaseName, $CollectionName) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls/$CollectionName"
    $headers = BuildHeaders -verb DELETE -resType colls -resourceId "dbs/$DatabaseName/colls/$CollectionName" -masterkey $MasterKey

    try {
        Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers
    }
    catch {
        if ($_.Exception.Response.StatusCode -ne 404) {
            Write-Warning "`tUnable to delete collection $CollectionName" -ForegroundColor Yellow
            throw
        }
    }
}

function EnsureDocumentExists($Endpoint, $MasterKey, $DatabaseName, $CollectionName, $Document) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls/$CollectionName/docs"
    $resourceId = "dbs/$DatabaseName/colls/$CollectionName"
    $headers = BuildHeaders -verb POST -resType docs -resourceId $resourceId -masterkey $MasterKey
    $headers.Add("x-ms-documentdb-is-upsert", "true")
    $response = Invoke-RestMethod $uri -Method Post -Body $Document -ContentType "application/json" -Headers $headers
    return $response
}

function GetKey($Verb, $ResourceId, $ResourceType, $Date, $masterKey) {
    $keyBytes = [System.Convert]::FromBase64String($masterKey)
    $text = "$($Verb.ToLowerInvariant())`n$($ResourceType.ToLowerInvariant())`n$($ResourceId)`n$($Date.ToLowerInvariant())`n`n"
    $body = [Text.Encoding]::UTF8.GetBytes($text)
    $hmacsha = new-object -TypeName System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keyBytes)
    $hash = $hmacsha.ComputeHash($body)
    $signature = [System.Convert]::ToBase64String($hash)
    [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$signature")
}

function BuildHeaders($verb = "get", $resType, $resourceId, $masterKey, $throughput) {
    $apiDate = GetUTCDate
    $authz = GetKey -Verb $verb -ResourceType $resType -ResourceId $resourceId -Date $apiDate -masterKey $masterKey

    if ($throughput -and $throughput -ge 400 -and $throughput -le 250000) {
        return @{
            Authorization           = $authz;
            "x-ms-version"          = "2015-12-16";
            "x-ms-date"             = $apiDate;
            "x-ms-offer-throughput" = $throughput
        };
    }
    return @{
        Authorization  = $authz;
        "x-ms-version" = "2015-12-16";
        "x-ms-date"    = $apiDate
    }
}

function GetUTCDate() {
    $date = [System.DateTime]::UtcNow
    return $date.ToString("r", [System.Globalization.CultureInfo]::InvariantCulture);
}

function CombineUris($base, $relative) {
    return New-Object System.Uri -ArgumentList (New-Object System.Uri -ArgumentList $base), $relative
}

function BuildDefaultCollection($CollectionName, $PartitionKey) {
    if ($PartitionKey) {
        $collectionJson = @"
        {
            "id": "$($CollectionName)",
            "indexingPolicy": {
              "indexingMode": "consistent",
              "automatic": true,
              "includedPaths": [
                {
                  "path": "/*",
                  "indexes": [
                    {
                      "kind": "Hash",
                      "dataType": "String",
                      "precision": 3
                    },
                    {
                      "kind": "Range",
                      "dataType": "Number",
                      "precision": -1
                    }
                  ]
                }
              ],
              "excludedPaths": []
            },
            "partitionKey": {
              "paths": [
                "/$($PartitionKey)"
              ],
              "kind": "Hash"
            }
          }
"@
        return $collectionJson
    }
    else {
        return (@{id = $CollectionName } | ConvertTo-Json)
    }
}
