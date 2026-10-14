
$ErrorActionPreference = "Stop"

$Region = "sa-east-1"
$VpcId = "vpc-06210c3c1ffff6868"
$Cluster = "surf-school-cluster"
$Service = "surf-school-api-service"
$Database = "surf-school-db"
$LoadBalancer = "surf-school-alb"

$InventoryDir = Join-Path $PSScriptRoot "../inventory"
New-Item -ItemType Directory -Force -Path $InventoryDir | Out-Null

function Export-AwsInventory {
    param(
        [string]$Name,
        [string[]]$AwsArgs
    )

    Write-Host "Exporting $Name..." -ForegroundColor Cyan

    $File = Join-Path $InventoryDir "$Name.json"

    $Result = & aws @AwsArgs --region $Region --output json

    if ($LASTEXITCODE -ne 0) {
        throw "AWS command failed: $Name"
    }

    $Result | Out-File -FilePath $File -Encoding utf8

    Write-Host "Saved: $File" -ForegroundColor Green
}

# 1. VPC
Export-AwsInventory "vpc" @(
    "ec2", "describe-vpcs",
    "--vpc-ids", $VpcId
)

# 2. Subnets
Export-AwsInventory "subnets" @(
    "ec2", "describe-subnets",
    "--filters", "Name=vpc-id,Values=$VpcId"
)

# 3. Security Groups
Export-AwsInventory "security-groups" @(
    "ec2", "describe-security-groups",
    "--filters", "Name=vpc-id,Values=$VpcId"
)

# 4. Route Tables
Export-AwsInventory "route-tables" @(
    "ec2", "describe-route-tables",
    "--filters", "Name=vpc-id,Values=$VpcId"
)

# 5. VPC Endpoints
Export-AwsInventory "vpc-endpoints" @(
    "ec2", "describe-vpc-endpoints",
    "--filters", "Name=vpc-id,Values=$VpcId"
)

# 6. ECS Service
Export-AwsInventory "ecs-service" @(
    "ecs", "describe-services",
    "--cluster", $Cluster,
    "--services", $Service
)

# 7. ECS Task Definitions (ARNs)
Export-AwsInventory "ecs-task-definitions" @(
    "ecs", "list-task-definitions",
    "--family-prefix", "surf-school-api"
)

# 8. RDS Configuration
Export-AwsInventory "rds" @(
    "rds", "describe-db-instances",
    "--db-instance-identifier", $Database
)

# 9. ALB
Export-AwsInventory "alb" @(
    "elbv2", "describe-load-balancers",
    "--names", $LoadBalancer
)

# 10. Target Groups
Export-AwsInventory "target-groups" @(
    "elbv2", "describe-target-groups",
    "--names", "surf-school-api-tg"
)

Write-Host "`nInventory completed successfully." -ForegroundColor Green
