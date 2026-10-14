# Funciones comunes del ciclo de vida; compatibles con Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$Profile = 'surf-school-lab'
$Region = 'sa-east-1'
$AccountId = '636487155373'
$ExpectedArn = 'arn:aws:iam::636487155373:user/surf-school-admin'
$Cluster = 'surf-school-cluster'
$Service = 'surf-school-api-service'
$Database = 'surf-school-db'
$VpcId = 'vpc-06210c3c1ffff6868'
$TerraformDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../terraform'))
$AllowedAddresses = @('aws_lb.surf_school[0]', 'aws_lb_listener.http[0]',
    'aws_vpc_endpoint.interface["ecr_api"]', 'aws_vpc_endpoint.interface["ecr_dkr"]',
    'aws_vpc_endpoint.interface["logs"]', 'aws_vpc_endpoint.interface["secretsmanager"]')

function Invoke-Aws {
    param([string[]]$Arguments)
    $raw = & aws @Arguments --profile $Profile --region $Region --output json --no-cli-pager --cli-connect-timeout 10 --cli-read-timeout 30
    if ($LASTEXITCODE -ne 0) { throw "AWS fallo: $($Arguments -join ' ') (codigo $LASTEXITCODE)." }
    ($raw -join "`n") | ConvertFrom-Json
}
function Invoke-Terraform {
    param([string[]]$Arguments)
    $raw = & terraform "-chdir=$TerraformDir" @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Terraform fallo: $($Arguments[0]) (codigo $LASTEXITCODE)." }
    $raw
}
function Get-Ecs {
    $result = Invoke-Aws -Arguments @('ecs', 'describe-services', '--cluster', $Cluster, '--services', $Service)
    if (@($result.failures).Count -gt 0 -or @($result.services).Count -ne 1 -or $result.services[0].status -ne 'ACTIVE') {
        throw 'Servicio ECS ausente o inactivo.'
    }
    $result.services[0]
}
function Get-Db {
    (Invoke-Aws -Arguments @('rds', 'describe-db-instances', '--db-instance-identifier', $Database)).DBInstances[0]
}
function Get-Alb {
    @((Invoke-Aws -Arguments @('elbv2', 'describe-load-balancers')).LoadBalancers | Where-Object { $_.LoadBalancerName -eq 'surf-school-alb' })
}
function Get-Endpoints {
    @((Invoke-Aws -Arguments @('ec2', 'describe-vpc-endpoints', '--filters', "Name=vpc-id,Values=$VpcId", 'Name=vpc-endpoint-type,Values=Interface')).VpcEndpoints |
        Where-Object { $_.ServiceName -in @('com.amazonaws.sa-east-1.ecr.api', 'com.amazonaws.sa-east-1.ecr.dkr', 'com.amazonaws.sa-east-1.logs', 'com.amazonaws.sa-east-1.secretsmanager') })
}
function Wait-Lab {
    param([string]$Description, [scriptblock]$Condition, [int]$Seconds = $TimeoutSeconds)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        if ($timer.Elapsed.TotalSeconds -ge $Seconds) { break }
        Start-Sleep -Seconds ([Math]::Min(10, [Math]::Max(1, $Seconds - [int]$timer.Elapsed.TotalSeconds)))
    } while ($timer.Elapsed.TotalSeconds -lt $Seconds)
    throw "Timeout ($Seconds segundos): $Description."
}
function Initialize-Lab {
    foreach ($tool in @('aws', 'terraform')) { Get-Command $tool -CommandType Application -ErrorAction Stop | Out-Null }
    $profiles = & aws configure list-profiles
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron consultar perfiles AWS.' }
    if ($Profile -notin $profiles) { throw "Falta el perfil $Profile." }
    $identity = Invoke-Aws -Arguments @('sts', 'get-caller-identity')
    if ($identity.Account -ne $AccountId -or $identity.Arn -cne $ExpectedArn) { throw "Identidad no autorizada: $($identity.Arn)." }
    $version = (Invoke-Terraform -Arguments @('version', '-json') | Out-String | ConvertFrom-Json).terraform_version
    if ([version]($version.Split('-')[0]) -lt [version]'1.16.0') { throw 'providers.tf exige Terraform >= 1.16.0.' }
    $ecs = Get-Ecs
    if ($ecs.deploymentController.type -ne 'ECS' -or $ecs.schedulingStrategy -ne 'REPLICA') { throw 'Se requiere ECS rolling deployment y REPLICA.' }
    $tg = (Invoke-Aws -Arguments @('elbv2', 'describe-target-groups', '--names', 'surf-school-api-tg')).TargetGroups[0]
    if ($tg.VpcId -ne $VpcId -or $tg.TargetType -ne 'ip') { throw 'Target Group fuera de la VPC o de tipo inesperado.' }
    $script:TargetGroupArn = $tg.TargetGroupArn
    foreach ($lb in @($ecs.loadBalancers)) {
        if ($lb.targetGroupArn -ne $TargetGroupArn -or $lb.containerName -ne 'surf-school-api' -or $lb.containerPort -ne 3000) {
            throw 'ECS tiene una asociacion no autorizada; no se reemplazara.'
        }
    }
    Write-LabStatus
}
function Write-LabStatus {
    # Consultas independientes: una falla no debe ocultar los otros recursos activos.
    foreach ($item in @('ECS', 'RDS', 'ALB', 'Endpoints')) {
        try {
            switch ($item) {
                ECS { $e = Get-Ecs; Write-Host "ECS: desired=$($e.desiredCount), running=$($e.runningCount), pending=$($e.pendingCount), asociaciones=$(@($e.loadBalancers).Count)" }
                RDS { Write-Host "RDS: $((Get-Db).DBInstanceStatus)" }
                ALB { foreach ($a in @(Get-Alb)) { Write-Host "ALB: $($a.State.Code), $($a.DNSName)" }; if (@(Get-Alb).Count -eq 0) { Write-Host 'ALB: ausente' } }
                Endpoints { $eps = @(Get-Endpoints); Write-Host "Interface endpoints presentes: $($eps.Count)"; foreach ($ep in $eps) { Write-Host "  $($ep.VpcEndpointId): $($ep.State)" } }
            }
        } catch { Write-Warning "$item estado DESCONOCIDO: $($_.Exception.Message)" }
    }
}
function Set-DbState {
    param([bool]$Enabled)
    $target = if ($Enabled) { 'available' } else { 'stopped' }
    Wait-Lab "RDS $target" {
        $status = (Get-Db).DBInstanceStatus
        if ($status -eq $target) { return $true }
        if ($Enabled -and $status -eq 'stopped') {
            Invoke-Aws -Arguments @('rds', 'start-db-instance', '--db-instance-identifier', $Database) | Out-Null
        } elseif (!$Enabled -and $status -eq 'available') {
            Invoke-Aws -Arguments @('rds', 'stop-db-instance', '--db-instance-identifier', $Database) | Out-Null
        } elseif ($status -notin @('starting', 'stopping', 'modifying', 'backing-up', 'rebooting', 'available', 'stopped')) {
            throw "Estado RDS no soportado: $status."
        }
        return $false
    }
}
function Assert-LabPlan {
    param($Plan, [bool]$Enabled)
    if ($null -eq $Plan -or $null -eq $Plan.PSObject.Properties['resource_changes'] -or
        $Plan.errored -eq $true -or $Plan.complete -eq $false -or @($Plan.deferred_changes | Where-Object { $null -ne $_ }).Count -gt 0) {
        throw 'Plan ausente, incompleto o no aplicable.'
    }
    foreach ($change in @($Plan.resource_changes)) {
        $actions = @($change.change.actions)
        if ($actions.Count -ne 1) { throw 'Lista de operaciones inesperada.' }
        if ($change.mode -eq 'data' -and ($actions -join ',') -in @('read', 'no-op')) { continue }
        if ($change.mode -ne 'managed') { throw "Modo inesperado: $($change.address)." }
        # Incluso los no-op deben pertenecer al alcance conocido.
        if ($change.address -cnotin $AllowedAddresses) { throw "Direccion no autorizada: $($change.address)." }
        $expected = if ($Enabled) { 'create' } else { 'delete' }
        if (($actions -join ',') -cnotin @('no-op', $expected)) { throw "Operacion no autorizada: $($change.address) [$($actions -join ',')]." }
        if ($change.importing -or $change.change.importing) { throw 'Importaciones no autorizadas.' }
        if ($change.previous_address -and !(($change.address -eq 'aws_lb.surf_school[0]' -and $change.previous_address -eq 'aws_lb.surf_school') -or
            ($change.address -eq 'aws_lb_listener.http[0]' -and $change.previous_address -eq 'aws_lb_listener.http'))) { throw 'Movimiento no autorizado.' }
    }
}
function Apply-LabPlan {
    param([bool]$Enabled)
    # Directorio temporal privado del usuario. El plan puede contener datos sensibles.
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('surf-lab-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary | Out-Null
    $planPath = Join-Path $temporary 'lifecycle.tfplan'
    try {
        # Nunca inicializar/reconfigurar automaticamente el backend.
        $backendPath = Join-Path $TerraformDir '.terraform/terraform.tfstate'
        if (!(Test-Path -LiteralPath $backendPath)) { throw 'Inicializa antes el backend remoto con terraform init.' }
        $backend = (Get-Content -LiteralPath $backendPath -Raw | ConvertFrom-Json).backend
        if ($backend.type -ne 's3' -or $backend.config.bucket -ne 'surf-school-terraform-state-636487155373' -or
            $backend.config.key -ne 'lab/terraform.tfstate' -or $backend.config.region -ne $Region -or
            $backend.config.profile -ne $Profile -or $backend.config.use_lockfile -ne $true) { throw 'Backend inicializado inesperado o sin bloqueo.' }
        $workspace = (Invoke-Terraform -Arguments @('workspace', 'show') | Out-String).Trim()
        if ($workspace -ne 'default') { throw 'Solo se permite workspace default.' }
        $value = if ($Enabled) { 'true' } else { 'false' }
        Invoke-Terraform -Arguments @('plan', '-input=false', '-lock=true', '-lock-timeout=60s', "-var=lab_enabled=$value", "-out=$planPath") | Out-Host
        $plan = Invoke-Terraform -Arguments @('show', '-json', $planPath) | Out-String | ConvertFrom-Json
        Assert-LabPlan $plan $Enabled
        Write-Host 'Plan guardado validado: solo create/delete esperados o no-op en las seis direcciones autorizadas.'
        Invoke-Terraform -Arguments @('apply', '-input=false', '-lock=true', '-lock-timeout=60s', $planPath) | Out-Host
    } finally {
        # Solo estos archivos propios; no se elimina recursivamente ningun directorio.
        if (Test-Path -LiteralPath $planPath) { Remove-Item -LiteralPath $planPath -Force }
        Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue
    }
}



function Test-EcsStopped {
    param($Ecs)
    # La desasociacion inicia un deployment: cero tareas no implica que haya terminado.
    if (@($Ecs.deployments | Where-Object { $_.rolloutState -eq 'FAILED' }).Count -gt 0) {
        throw 'Deployment ECS fallido al apagar.'
    }
    return ($Ecs.desiredCount -eq 0 -and $Ecs.runningCount -eq 0 -and $Ecs.pendingCount -eq 0 -and
        @($Ecs.loadBalancers).Count -eq 0 -and @($Ecs.deployments).Count -eq 1 -and
        $Ecs.deployments[0].status -eq 'PRIMARY' -and $Ecs.deployments[0].rolloutState -eq 'COMPLETED')
}

