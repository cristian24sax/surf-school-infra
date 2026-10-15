# Surf School Infra

Infraestructura como código para el entorno de Surf School.

## Comandos cortos del laboratorio

Desde la raiz del repositorio, configura estos alias en tu terminal PowerShell:

```powershell
Set-Alias lab.start (Join-Path $PWD 'scripts/lab-start.ps1')
Set-Alias lab.stop (Join-Path $PWD 'scripts/lab-stop.ps1')
Set-Alias lab.status (Join-Path $PWD 'scripts/lab-status.ps1')
```

Despues puedes usarlos desde cualquier directorio de esa misma terminal:

```powershell
lab.status
lab.start           # Dry-run: no modifica recursos
lab.stop            # Dry-run: no modifica recursos
lab.start -Execute  # Encendido: exige escribir START
lab.stop -Execute   # Apagado: exige escribir STOP
```

Los alias no incluyen `-Execute`: debes indicarlo explicitamente para aplicar cambios. PowerShell no distingue mayusculas en los nombres de parametros, por lo que `-EXECUTE` tambien funciona.

Los alias duran hasta cerrar la terminal. Para conservarlos, agrega estas lineas a tu perfil PowerShell (`$PROFILE`), usando la ruta absoluta del repositorio:

```powershell
Set-Alias lab.start 'C:\Users\crist\Documents\aws\surf-school-infra\scripts\lab-start.ps1'
Set-Alias lab.stop 'C:\Users\crist\Documents\aws\surf-school-infra\scripts\lab-stop.ps1'
Set-Alias lab.status 'C:\Users\crist\Documents\aws\surf-school-infra\scripts\lab-status.ps1'
```

Consulta [el ciclo de vida del laboratorio](docs/aws-lab-lifecycle.md) para las dependencias, validaciones y pruebas previas. `lab.status` conserva la configuracion actual de `lab-status.ps1`; los alias solo acortan los comandos.
