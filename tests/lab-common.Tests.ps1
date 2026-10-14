# Ejecutar con Windows PowerShell 5.1 y Pester 3.4+, sin herramientas reales.
. (Join-Path $PSScriptRoot '../scripts/lab-common.ps1')
# Stubs locales: Pester nunca debe resolver ejecutables nativos.
function aws { throw 'AWS real bloqueado por las pruebas.' }
function terraform { throw 'Terraform real bloqueado por las pruebas.' }
function New-TestPlan {
    param([string]$Address = 'aws_lb.surf_school[0]', [string[]]$Actions = @('create'), [string]$Mode = 'managed')
    [pscustomobject]@{resource_changes=@([pscustomobject]@{address=$Address;mode=$Mode;change=[pscustomobject]@{actions=$Actions}})}
}
function New-TestEcs {
    param([string]$Rollout = 'COMPLETED')
    [pscustomobject]@{status='ACTIVE';desiredCount=0;runningCount=0;pendingCount=0;loadBalancers=@();
        schedulingStrategy='REPLICA';deploymentController=@{type='ECS'};
        deployments=@([pscustomobject]@{status='PRIMARY';rolloutState=$Rollout})}
}
Describe 'Wrappers nativos' {
    Mock aws { $global:LASTEXITCODE=0; $script:CapturedAws=@($args); '{"ok":true}' }
    Mock terraform { $global:LASTEXITCODE=0; $script:CapturedTerraform=@($args); 'resultado' }
    It 'AWS recibe todos los argumentos y opciones fijas' {
        (Invoke-Aws -Arguments @('ecs','describe-services','--cluster','test')).ok | Should Be $true
        ($script:CapturedAws -join '|') | Should Be 'ecs|describe-services|--cluster|test|--profile|surf-school-lab|--region|sa-east-1|--output|json|--no-cli-pager|--cli-connect-timeout|10|--cli-read-timeout|30'
    }
    It 'Terraform recibe chdir, var y ruta con espacios como argumentos individuales' {
        Invoke-Terraform -Arguments @('plan','-var=lab_enabled=false','-out=C:\plan con espacios.tfplan') | Should Be 'resultado'
        $script:CapturedTerraform.Count | Should Be 4
        $script:CapturedTerraform[0] | Should Be "-chdir=$TerraformDir"
        $script:CapturedTerraform[3] | Should Be '-out=C:\plan con espacios.tfplan'
    }
    It 'AWS propaga codigo de salida no cero' {
        Mock aws { $global:LASTEXITCODE=2 }
        { Invoke-Aws -Arguments @('sts','get-caller-identity') } | Should Throw
    }
    It 'Terraform propaga codigo de salida no cero' {
        Mock terraform { $global:LASTEXITCODE=1 }
        { Invoke-Terraform -Arguments @('version','-json') } | Should Throw
    }
}
Describe 'Consultas y validacion inicial con mocks' {
    Mock Get-Command { [pscustomobject]@{Name='mock'} }
    Mock aws { $global:LASTEXITCODE=0; 'surf-school-lab' }
    Mock Write-LabStatus {}
    Mock Invoke-Terraform { '{"terraform_version":"1.16.0"}' }
    Mock Invoke-Aws {
        param($Arguments)
        switch ($Arguments[0]) {
            sts { [pscustomobject]@{Account='636487155373';Arn='arn:aws:iam::636487155373:user/surf-school-admin'} }
            ecs { [pscustomobject]@{failures=@();services=@((New-TestEcs))} }
            rds { [pscustomobject]@{DBInstances=@([pscustomobject]@{DBInstanceStatus='available'})} }
            elbv2 {
                if ($Arguments[1] -eq 'describe-target-groups') {
                    [pscustomobject]@{TargetGroups=@([pscustomobject]@{VpcId=$VpcId;TargetType='ip';TargetGroupArn='arn:test'})}
                } else { [pscustomobject]@{LoadBalancers=@([pscustomobject]@{LoadBalancerName='surf-school-alb'})} }
            }
            ec2 { [pscustomobject]@{VpcEndpoints=@([pscustomobject]@{ServiceName='com.amazonaws.sa-east-1.logs'},[pscustomobject]@{ServiceName='otro'})} }
        }
    }
    It 'Initialize-Lab enlaza identidad, version y Target Group completos' {
        Initialize-Lab
        Assert-MockCalled -Scope It Invoke-Aws -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'sts|get-caller-identity' }
        Assert-MockCalled -Scope It Invoke-Terraform -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'version|-json' }
    }
    It 'Get-Ecs envia los seis argumentos' {
        (Get-Ecs).status | Should Be 'ACTIVE'
        Assert-MockCalled -Scope It Invoke-Aws -ParameterFilter { ($Arguments -join '|') -eq 'ecs|describe-services|--cluster|surf-school-cluster|--services|surf-school-api-service' }
    }
    It 'Get-Db envia identificador correcto' {
        (Get-Db).DBInstanceStatus | Should Be 'available'
        Assert-MockCalled -Scope It Invoke-Aws -ParameterFilter { ($Arguments -join '|') -eq 'rds|describe-db-instances|--db-instance-identifier|surf-school-db' }
    }
    It 'Get-Alb filtra el nombre' { @(Get-Alb).Count | Should Be 1 }
    It 'Get-Endpoints envia filtros y excluye otros servicios' {
        @(Get-Endpoints).Count | Should Be 1
        Assert-MockCalled -Scope It Invoke-Aws -ParameterFilter { $Arguments.Count -eq 5 -and $Arguments[3] -eq "Name=vpc-id,Values=$VpcId" }
    }
    It 'Rechaza identidad incorrecta antes de continuar' {
        Mock Invoke-Aws { [pscustomobject]@{Account='otra';Arn='otro'} } -ParameterFilter { $Arguments[0] -eq 'sts' }
        { Initialize-Lab } | Should Throw
    }
}
Describe 'RDS y esperas' {
    Mock Invoke-Aws {}
    Mock Wait-Lab { param($Description,$Condition) for ($i=0; $i -lt 4; $i++) { if (& $Condition) { return } }; throw 'No converge' }
    It 'Inicia una vez y espera estados intermedios' {
        $script:states = New-Object 'System.Collections.Generic.Queue[string]'
        @('stopped','starting','available') | ForEach-Object { $script:states.Enqueue($_) }
        Mock Get-Db { [pscustomobject]@{DBInstanceStatus=$script:states.Dequeue()} }
        Set-DbState $true
        Assert-MockCalled -Scope It Invoke-Aws -Times 1 -Exactly -ParameterFilter { ($Arguments -join '|') -eq 'rds|start-db-instance|--db-instance-identifier|surf-school-db' }
    }
    It 'Detiene una vez y espera stopped' {
        $script:states = New-Object 'System.Collections.Generic.Queue[string]'
        @('starting','available','stopping','stopped') | ForEach-Object { $script:states.Enqueue($_) }
        Mock Get-Db { [pscustomobject]@{DBInstanceStatus=$script:states.Dequeue()} }
        Set-DbState $false
        Assert-MockCalled -Scope It Invoke-Aws -Times 1 -Exactly -ParameterFilter { $Arguments[1] -eq 'stop-db-instance' }
    }
    It 'No modifica RDS ya detenido' {
        Mock Get-Db { [pscustomobject]@{DBInstanceStatus='stopped'} }
        Set-DbState $false
        Assert-MockCalled -Scope It Invoke-Aws -Times 0 -Exactly
    }
    It 'Rechaza estado RDS no soportado' {
        Mock Get-Db { [pscustomobject]@{DBInstanceStatus='failed'} }
        { Set-DbState $true } | Should Throw
    }
}
Describe 'Deployment ECS tras desasociacion' {
    It 'No acepta cero tareas con deployment IN_PROGRESS' { Test-EcsStopped (New-TestEcs 'IN_PROGRESS') | Should Be $false }
    It 'Acepta PRIMARY COMPLETED sin tareas ni asociacion' { Test-EcsStopped (New-TestEcs) | Should Be $true }
    It 'Rechaza deployment FAILED' { { Test-EcsStopped (New-TestEcs 'FAILED') } | Should Throw }
    It 'No acepta deployments multiples' {
        $e=New-TestEcs; $e.deployments=@($e.deployments[0],$e.deployments[0]); Test-EcsStopped $e | Should Be $false
    }
    It 'No acepta tareas pendientes o asociacion residual' {
        $e=New-TestEcs; $e.pendingCount=1; Test-EcsStopped $e | Should Be $false
        $e=New-TestEcs; $e.loadBalancers=@(@{targetGroupArn='arn:test'}); Test-EcsStopped $e | Should Be $false
    }
}
Describe 'Filtro de planes Terraform' {
    It 'Acepta los seis recursos solo con create en START o delete en STOP' {
        foreach ($address in $AllowedAddresses) {
            Assert-LabPlan (New-TestPlan $address @('create')) $true
            Assert-LabPlan (New-TestPlan $address @('delete')) $false
            Assert-LabPlan (New-TestPlan $address @('no-op')) $false
        }
    }
    It 'Rechaza recurso ajeno incluso no-op' {
        { Assert-LabPlan (New-TestPlan 'aws_db_instance.ajeno' @('delete')) $false } | Should Throw
        { Assert-LabPlan (New-TestPlan 'aws_db_instance.ajeno' @('no-op')) $false } | Should Throw
    }
    It 'Rechaza update, replace y operacion en sentido contrario' {
        foreach ($actions in @(@('update'),@('delete','create'),@('create','delete'))) {
            { Assert-LabPlan (New-TestPlan -Actions $actions) $true } | Should Throw
        }
        { Assert-LabPlan (New-TestPlan -Actions @('delete')) $true } | Should Throw
        { Assert-LabPlan (New-TestPlan -Actions @('create')) $false } | Should Throw
    }
    It 'Rechaza planes incompletos, errores, importaciones y movimientos ajenos' {
        { Assert-LabPlan $null $true } | Should Throw
        $p=New-TestPlan; $p | Add-Member complete $false; { Assert-LabPlan $p $true } | Should Throw
        $p=New-TestPlan; $p | Add-Member errored $true; { Assert-LabPlan $p $true } | Should Throw
        $p=New-TestPlan; $p.resource_changes[0].change | Add-Member importing @{id='test'}; { Assert-LabPlan $p $true } | Should Throw
        $p=New-TestPlan; $p.resource_changes[0] | Add-Member previous_address 'aws_lb.ajeno'; { Assert-LabPlan $p $true } | Should Throw
    }
    It 'Acepta no cambios y lecturas de data sources' {
        Assert-LabPlan ([pscustomobject]@{resource_changes=@()}) $true
        Assert-LabPlan (New-TestPlan 'data.aws_vpc.surf_school' @('read') 'data') $true
    }
}

Describe 'Apply-LabPlan aislado; todos los comandos Terraform son mocks' {
    Mock Test-Path { $true }
    Mock Get-Content { '{"backend":{"type":"s3","config":{"bucket":"surf-school-terraform-state-636487155373","key":"lab/terraform.tfstate","region":"sa-east-1","profile":"surf-school-lab","use_lockfile":true}}}' }
    Mock New-Item {}
    Mock Remove-Item {}
    Mock Invoke-Terraform {
        param($Arguments)
        switch ($Arguments[0]) {
            workspace { 'default' }
            plan { $script:SavedPlanPath=$Arguments[-1].Substring(5) }
            show { '{"resource_changes":[{"address":"aws_lb.surf_school[0]","mode":"managed","change":{"actions":["create"]}}]}' }
            apply { $script:AppliedPath=$Arguments[-1] }
        }
    }
    It 'Inspecciona JSON y transmite exactamente el plan guardado al mock' {
        Apply-LabPlan $true
        $script:AppliedPath | Should Be $script:SavedPlanPath
        Assert-MockCalled -Scope It Invoke-Terraform -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'plan' -and '-var=lab_enabled=true' -in $Arguments }
        Assert-MockCalled -Scope It Invoke-Terraform -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'show' -and $Arguments[1] -eq '-json' -and $Arguments[2] -eq $script:SavedPlanPath }
        Assert-MockCalled -Scope It Remove-Item -Times 2 -Exactly
    }
    It 'Plan peligroso impide llegar al mock de apply y limpia temporales' {
        Mock Invoke-Terraform { '{"resource_changes":[{"address":"aws_db_instance.ajeno","mode":"managed","change":{"actions":["delete"]}}]}' } -ParameterFilter { $Arguments[0] -eq 'show' }
        { Apply-LabPlan $false } | Should Throw
        Assert-MockCalled -Scope It Invoke-Terraform -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'apply' }
        Assert-MockCalled -Scope It Remove-Item -Times 2 -Exactly
    }
    It 'Rechaza backend local antes de planear' {
        Mock Get-Content { '{"backend":{"type":"local"}}' }
        { Apply-LabPlan $true } | Should Throw
        Assert-MockCalled -Scope It Invoke-Terraform -Times 0 -Exactly
    }
    It 'Rechaza workspace distinto de default' {
        Mock Invoke-Terraform { 'otro' } -ParameterFilter { $Arguments[0] -eq 'workspace' }
        { Apply-LabPlan $true } | Should Throw
        Assert-MockCalled -Scope It Invoke-Terraform -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'plan' -or $Arguments[0] -eq 'apply' }
    }
}
Describe 'Wait-Lab real sin demoras' {
    Mock Start-Sleep { throw 'No debe dormir' }
    It 'Retorna inmediatamente si la condicion se cumple' { Wait-Lab 'listo' { $true } -Seconds 0 }
    It 'Lanza timeout si la condicion no se cumple' { { Wait-Lab 'timeout' { $false } -Seconds 0 } | Should Throw }
}
Describe 'Auditoria estatica de scripts en PowerShell 5.1' {
    It 'Los tres scripts tienen sintaxis valida y todas las llamadas usan Arguments explicito' {
        foreach ($file in @('lab-common.ps1','lab-start.ps1','lab-stop.ps1')) {
            $tokens=$null; $errors=$null
            $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "../scripts/$file"),[ref]$tokens,[ref]$errors)
            $errors.Count | Should Be 0
            $calls=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Invoke-Aws','Invoke-Terraform')},$true)
            foreach ($call in $calls) { $call.CommandElements[1].Extent.Text | Should Be '-Arguments' }
        }
    }
    It 'STOP espera Test-EcsStopped antes de Apply-LabPlan' {
        $source=Get-Content (Join-Path $PSScriptRoot '../scripts/lab-stop.ps1') -Raw
        ($source.IndexOf('return (Test-EcsStopped -Ecs $e)') -ge 0) | Should Be $true
        ($source.IndexOf('return (Test-EcsStopped -Ecs $e)') -lt $source.IndexOf('Apply-LabPlan $false')) | Should Be $true
    }
}

