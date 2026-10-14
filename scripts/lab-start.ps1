# Encendido seguro del laboratorio. Sin -Execute solo se consulta AWS.
param([switch]$Execute, [ValidateRange(30,7200)][int]$TimeoutSeconds = 1800,
    [ValidateRange(30,1800)][int]$HealthTimeoutSeconds = 300)
. (Join-Path $PSScriptRoot 'lab-common.ps1')
try {
    Initialize-Lab
    if (!$Execute) {
        Write-Host 'DRY RUN: crear ALB/listener y cuatro endpoints mediante plan validado; iniciar RDS; asociar ECS al Target Group; desired=1; verificar /health. Sin cambios ni plan Terraform.'
        return
    }
    if ((Read-Host 'Escribe START para encender el laboratorio') -cne 'START') { Write-Host 'Operacion cancelada.'; return }
    Apply-LabPlan $true
    Wait-Lab 'ALB y cuatro endpoints disponibles' {
        $alb = @(Get-Alb); $eps = @(Get-Endpoints)
        return ($alb.Count -eq 1 -and $alb[0].VpcId -eq $VpcId -and $alb[0].State.Code -eq 'active' -and
            $eps.Count -eq 4 -and @($eps | Where-Object { $_.State -ne 'available' }).Count -eq 0)
    }
    Set-DbState $true
    $ecs = Get-Ecs
    if (@($ecs.loadBalancers).Count -ne 1 -or $ecs.desiredCount -ne 1) {
        $association = "targetGroupArn=$TargetGroupArn,containerName=surf-school-api,containerPort=3000"
        Invoke-Aws -Arguments @('ecs', 'update-service', '--cluster', $Cluster, '--service', $Service,
            '--load-balancers', $association, '--desired-count', '1') | Out-Null
    }
    Wait-Lab 'ECS estable con una tarea' {
        $e = Get-Ecs
        if (@($e.deployments | Where-Object { $_.rolloutState -eq 'FAILED' }).Count -gt 0) { throw 'Deployment ECS fallido.' }
        return ($e.desiredCount -eq 1 -and $e.runningCount -eq 1 -and $e.pendingCount -eq 0 -and
            @($e.deployments).Count -eq 1 -and $e.deployments[0].rolloutState -eq 'COMPLETED' -and
            @($e.loadBalancers).Count -eq 1 -and $e.loadBalancers[0].targetGroupArn -eq $TargetGroupArn)
    }
    $url = 'http://' + (Get-Alb).DNSName + '/health'
    Wait-Lab 'HTTP 200 y status=ok' {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
            return ($response.StatusCode -eq 200 -and ($response.Content | ConvertFrom-Json).status -ceq 'ok')
        } catch { return $false }
    } $HealthTimeoutSeconds
    if ((Get-Db).DBInstanceStatus -ne 'available') { throw 'RDS no permanece disponible.' }
    Write-LabStatus
    Write-Host "LAB START COMPLETADO. URL: $url" -ForegroundColor Green
} catch {
    Write-Warning "ENCENDIDO INCOMPLETO: $($_.Exception.Message). No se realiza rollback automatico."
    Write-LabStatus
    throw
}

