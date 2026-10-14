# Ciclo de vida del laboratorio AWS

Cuenta `636487155373`, perfil `surf-school-lab`, región `sa-east-1` e identidad exigida `arn:aws:iam::636487155373:user/surf-school-admin`.

## Arquitectura y alcance

ECS Fargate ejecuta `surf-school-api-service` en `surf-school-cluster`, con el contenedor `surf-school-api` y puerto 3000. El ALB público `surf-school-alb` recibe HTTP en el puerto 80 y reenvía al Target Group existente `surf-school-api-tg`. Las tareas privadas usan cuatro Interface Endpoints para ECR API, ECR DKR, Logs y Secrets Manager. RDS es `surf-school-db`.

Terraform administra únicamente estos recursos temporales:

| Dirección exacta | Encendido | Apagado |
| --- | --- | --- |
| `aws_lb.surf_school[0]` | create/no-op | delete/no-op |
| `aws_lb_listener.http[0]` | create/no-op | delete/no-op |
| `aws_vpc_endpoint.interface["ecr_api"]` | create/no-op | delete/no-op |
| `aws_vpc_endpoint.interface["ecr_dkr"]` | create/no-op | delete/no-op |
| `aws_vpc_endpoint.interface["logs"]` | create/no-op | delete/no-op |
| `aws_vpc_endpoint.interface["secretsmanager"]` | create/no-op | delete/no-op |

VPC `vpc-06210c3c1ffff6868`, subredes, security groups, ECS, RDS, Target Group y S3 Gateway Endpoint se conservan. Algunos son data sources y otros están fuera de esta configuración Terraform. No se usa destroy ni targeting. Se rechazan updates, reemplazos, importaciones y direcciones adicionales; solo se permiten los dos movimientos declarados en `moved.tf`. Las lecturas de data sources y cambios de outputs no son operaciones sobre recursos.

## Dependencias y preparación

Windows PowerShell 5.1 o PowerShell 7, AWS CLI v2 y Terraform **>= 1.16.0**, conforme a `providers.tf`, con proveedor AWS `~> 6.0`. No se rebaja esa restricción. Se necesita conectividad AWS y permisos STS, lectura de recursos, actualización ECS, start/stop RDS, administración de ALB/listener/endpoints y acceso al backend S3 y su lockfile. No hay secretos incorporados.

Desde la raíz, inicializa y valida manualmente la configuración antes de usar Execute:

```powershell
aws configure list-profiles
aws sts get-caller-identity --profile surf-school-lab --region sa-east-1
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform workspace show
```

Backend remoto: bucket `surf-school-terraform-state-636487155373`, key `lab/terraform.tfstate`, región `sa-east-1`, perfil `surf-school-lab`, `use_lockfile=true`, cifrado habilitado. Solo se acepta workspace `default`. Los scripts no ejecutan init, migran estados ni reconfiguran el backend. `.terraform/terraform.tfstate` es metadata de inicialización del backend, no un estado local de infraestructura creado por estos scripts. Conserva el lockfile del proveedor generado durante init.

## Uso

```powershell
.\scripts\lab-stop.ps1
.\scripts\lab-start.ps1
.\scripts\lab-stop.ps1 -Execute
.\scripts\lab-start.ps1 -Execute
.\scripts\lab-start.ps1 -Execute -TimeoutSeconds 2400 -HealthTimeoutSeconds 600
```

Sin Execute se validan herramientas, perfil e identidad y se consultan recursos. No se ejecutan plan, apply ni modificaciones. Con Execute se exige escribir literalmente `STOP` o `START`, respetando mayúsculas. La cancelación no modifica recursos. Las rutas se resuelven desde el script, independientemente del directorio actual. `lab-common.ps1` debe permanecer junto a ambos scripts.

Apagado: desiredCount=0, esperar cero tareas running y pending, quitar asociación ECS mediante `--load-balancers []`, esperar desasociación, detener RDS y esperar stopped, generar plan con `lab_enabled=false`, inspeccionar JSON, aplicar ese mismo archivo y verificar ausencia de ALB/endpoints y estado ECS/RDS.

Encendido: generar y validar plan con `lab_enabled=true`, aplicar archivo guardado, esperar ALB active y cuatro endpoints available, iniciar RDS y esperar available, resolver ARN del Target Group, asociar contenedor/puerto y desiredCount=1, esperar un deployment COMPLETED con una tarea y cero pendientes, resolver DNS y comprobar HTTP 200 y JSON status=ok en `/health`.

RDS starting/stopping/modifying/backing-up/rebooting se consulta hasta poder continuar; estados no soportados fallan. No se usa el waiter inexistente db-instance-stopped. Las esperas tienen límites por etapa (1800 segundos por defecto; health 300), con consultas cada diez segundos y tiempos de conexión/lectura AWS acotados. Una consulta en curso puede exceder ligeramente el límite de etapa. Plan/apply dependen de los tiempos de Terraform y del proveedor; el lock espera máximo 60 segundos.

El plan temporal se guarda bajo el directorio temporal del usuario, se inspecciona con show -json y se elimina en finally. Puede contener datos sensibles: no compartirlo. Interrumpir abruptamente el proceso puede dejarlo en disco. No hay auto-approve ni estado local generado. No ejecutar operadores concurrentes ni cambiar credenciales/configuración durante la operación.

## Fallos y costos

Un fallo detiene las etapas siguientes, produce un error y muestra ECS, RDS, ALB y endpoints mediante consultas independientes. Estado DESCONOCIDO significa que debe verificarse manualmente. No hay rollback automático: un error de plan durante STOP puede dejar ECS/RDS apagados y ALB/endpoints facturando; un START incompleto puede dejar recursos nuevos activos. Corrige el problema y repite la operación; revisa primero el resumen y la consola. El éxito solo se declara después de las comprobaciones finales.

Con el laboratorio encendido facturan tareas Fargate, RDS, ALB/capacidad y direcciones IPv4 públicas, e Interface Endpoints por zona y tráfico. Al apagar se eliminan ALB y cuatro endpoints y se detienen tareas/RDS. Persisten costos potenciales de almacenamiento RDS, backups/snapshots, S3/backend, ECR, CloudWatch Logs, Secrets Manager y otros recursos fuera del alcance, como NAT si existiera. El inventario Terraform no representa toda la cuenta.

RDS se reinicia automáticamente tras siete días detenido y mantiene cargos de almacenamiento y backups: [documentación oficial de RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html). Revisar periódicamente estado y facturación. La desasociación ECS usa una lista vacía según [AWS CLI update-service](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ecs/update-service.html).

## Pruebas manuales antes de Execute

1. Ejecutar init/validate/version y confirmar backend, workspace default y credenciales exactas. Inspeccionar variables, archivos tfvars y cambios locales; no guardar secretos en documentación.
2. Ejecutar ambos dry-run desde la raíz y desde otro directorio. Confirmar que el estado AWS y el remoto no cambian. Probar perfil ausente/identidad diferente en un entorno controlado: debe rechazar la operación.
3. Revisar manualmente un plan `terraform -chdir=terraform plan -var=lab_enabled=false` con el lab encendido: solo deben proponerse seis eliminaciones. No aplicar un plan inesperado. Revisar `show -json` de un plan guardado si se desea comparar las direcciones exactas. El modo dry-run de los scripts no genera este plan.
4. Inspeccionar ECS: deploymentController ECS, REPLICA, asociación exclusiva al Target Group esperado, contenedor y puerto correctos. Comprobar que no existen endpoints duplicados para esos servicios en la VPC.
5. En una ventana de pruebas, usar Execute con una confirmación incorrecta: debe cancelar antes de cualquier cambio. El dry-run sí requiere acceso de lectura AWS.

Después de estas comprobaciones, probar STOP/START en el laboratorio: verificar seis eliminaciones/creaciones, persistencia de recursos conservados, ECS sin tareas pendientes al apagar, RDS stopped/available y /health. Repetir STOP y START para comprobar idempotencia; simular timeouts y fallos de permisos solo en un entorno controlado. Probar el filtro con planes simulados que contengan un update, replace o recurso ajeno: todos deben fallar. No probar un cambio peligroso con apply real.

`lab-status.ps1` no se modifica: usa su configuración original y no sustituye las comprobaciones de identidad y perfil de estos scripts.
