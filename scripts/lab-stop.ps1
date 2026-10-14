# Apagado seguro del laboratorio. Sin -Execute solo se consulta AWS.
param([switch]$Execute, [ValidateRange(30,7200)][int]$TimeoutSeconds = 1800)
. (Join-Path $PSScriptRoot 'lab-common.ps1')
try {
    Initialize-Lab
    if (!$Execute) {
        Write-Host 'DRY RUN: ECS desired=0; esperar cero tareas; desasociar Target Group; detener RDS; eliminar ALB/listener y cuatro endpoints mediante plan validado. Sin cambios ni plan Terraform.'
        return
    }
    if ((Read-Host 'Escribe STOP para apagar el laboratorio') -cne 'STOP') { Write-Host 'Operacion cancelada.'; return }
    if ((Get-Ecs).desiredCount -ne 0) {
        Invoke-Aws -Arguments @('ecs', 'update-service', '--cluster', $Cluster, '--service', $Service, '--desired-count', '0') | Out-Null
    }
    Wait-Lab 'ECS sin tareas ejecutandose ni pendientes' {
        $e = Get-Ecs
        return ($e.desiredCount -eq 0 -and $e.runningCount -eq 0 -and $e.pendingCount -eq 0)
    }
    if (@((Get-Ecs).loadBalancers).Count -gt 0) {
        Invoke-Aws -Arguments @('ecs', 'update-service', '--cluster', $Cluster, '--service', $Service, '--load-balancers', '[]') | Out-Null
    }
    Wait-Lab 'Deployment ECS completado, desasociado y sin tareas' {
        $e = Get-Ecs
        return (Test-EcsStopped -Ecs $e)
    }
    Set-DbState $false
    Apply-LabPlan $false
    Wait-Lab 'ALB y endpoints eliminados' { return (@(Get-Alb).Count -eq 0 -and @(Get-Endpoints).Count -eq 0) }
    $e = Get-Ecs
    if (!(Test-EcsStopped -Ecs $e) -or (Get-Db).DBInstanceStatus -ne 'stopped') { throw 'Estado final de ECS/RDS inesperado.' }
    Write-LabStatus
    Write-Host 'LAB STOP COMPLETADO.' -ForegroundColor Green
} catch {
    Write-Warning "APAGADO INCOMPLETO: $($_.Exception.Message). Revisar recursos activos; no se continua ni se realiza rollback automatico."
    Write-LabStatus
    throw
}



