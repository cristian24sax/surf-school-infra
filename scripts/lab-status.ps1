# Estado del laboratorio de infraestructura.

$ErrorActionPreference = "Stop"

$Region = "sa-east-1"
$Cluster = "surf-school-cluster"
$Service = "surf-school-api-service"
$Database = "surf-school-db"
$VpcId = "vpc-06210c3c1ffff6868"

Write-Host "`n=== SURF SCHOOL AWS LAB STATUS ===" -ForegroundColor Cyan

# 1. Verificar identidad AWS
Write-Host "`n[1] AWS Account" -ForegroundColor Yellow
aws sts get-caller-identity --query "{Account:Account,Arn:Arn}" --output table
if ($LASTEXITCODE -ne 0) { throw "AWS authentication failed" }

# 2. Consultar ECS
Write-Host "`n[2] ECS Service" -ForegroundColor Yellow
aws ecs describe-services `
   --cluster $Cluster `
   --services $Service `
   --region $Region `
   --query "services[].{Name:serviceName,Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}" `
   --output table

# 3. Consultar RDS
Write-Host "`n[3] RDS Database" -ForegroundColor Yellow
aws rds describe-db-instances `
   --db-instance-identifier $Database `
   --region $Region `
   --query "DBInstances[].{Name:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" `
   --output table

# 4. Consultar ALB
Write-Host "`n[4] Application Load Balancer" -ForegroundColor Yellow
aws elbv2 describe-load-balancers `
   --region $Region `
   --query "LoadBalancers[?LoadBalancerName=='surf-school-alb'].{Name:LoadBalancerName,Status:State.Code,DNS:DNSName}" `
   --output table

# 5. Consultar VPC Endpoints
Write-Host "`n[5] VPC Endpoints" -ForegroundColor Yellow

$VpcState = aws ec2 describe-vpcs `
   --vpc-ids $VpcId `
   --region $Region `
   --query "Vpcs[0].State" `
   --output text

if ($LASTEXITCODE -ne 0 -or $VpcState -ne "available") {
   throw "Surf School VPC is not available: $VpcId"
}

aws ec2 describe-vpc-endpoints `
   --region $Region `
   --filters "Name=vpc-id,Values=$VpcId" `
   --query "VpcEndpoints[].{Id:VpcEndpointId,Type:VpcEndpointType,Service:ServiceName,State:State,Subnets:length(SubnetIds)}" `
   --output table
if ($LASTEXITCODE -ne 0) {
   throw "Failed to retrieve VPC endpoints"
}
Write-Host "`n=== STATUS CHECK COMPLETED ===" -ForegroundColor Green
