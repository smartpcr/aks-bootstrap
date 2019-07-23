$domainName = "dev.xiaodong.world"
$tempFolder = Join-Path $yamlsFolder "tls-poc"
Set-Location $tempFolder

openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout tls.key -out tls.crt -subj "/CN=*.$($domainName)" -days 365
kubectl create secret generic example-com-tls --cert=tls.crt --key=tls.key

Write-Host "update ingress and use this cert: 'example-com-tls'"
curl --capath ./ https://tls-poc-space-westus2.dev.xiaodong.world/api/values

