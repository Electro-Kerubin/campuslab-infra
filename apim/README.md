# APIM de CampusLab (Azure API Management)

Publica el BFF detrás de Azure API Management (tier **Consumption**, suscripción *Azure for Students*) con CORS, versionado `/v1` y validación de JWT. Guía completa: [GUIA_APIM_CAMPUSLAB.md](../../GUIA_APIM_CAMPUSLAB.md).

```
Angular :4200 ──▶ https://apim-campuslab-15444.azure-api.net/campuslab/v1/api/...  ──▶ Dev Tunnel ──▶ BFF :8080
                    (CORS · JWT de Entra ID · /v1)                                 (campuslab-bff.brs)
```

| Archivo | Para qué |
|---|---|
| `crear-apim.sh` | Crea el resource group y la instancia APIM (región `brazilsouth`: la suscripción solo permite `canadacentral`, `mexicocentral`, `brazilsouth`, `westus3`, `southafricanorth`) |
| `configurar-api.sh` | Publica la API `campuslab-v1` y sus operaciones comodín `/*` (GET, POST, PUT, PATCH, DELETE, OPTIONS). Idempotente: sirve para cambiar `BFF_URL` |
| `aplicar-politica.sh` | Sube un XML de política a la API |
| `policy-v1.xml` | Política final: CORS + bloqueo de `/actuator`, `/swagger-ui`, `/v3/api-docs` + `validate-jwt` (excepto `/api/public/`) |
| `policy-v1-cors.xml` | Solo CORS, para probarlo aislado |
| `apim.env` | Nombres generados (no se versiona) |

Todos se ejecutan desde esta carpeta en **Git Bash**. Si `az` no se encuentra: `export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"`.

## Levantar la demo (cada vez que la necesiten)

1. **BFF** (con cualquiera de los dos modos funciona; se midió que APIM reemplaza las cabeceras CORS del backend y llega un solo `Access-Control-Allow-Origin`):
   ```bash
   cd ../../ms-campuslab-bff && mvn -q -DskipTests package
   java -jar target/ms-campuslab-bff-1.0-SNAPSHOT.jar
   # opcional: CAMPUSLAB_CORS_ENABLED=false java -jar ...   (el BFF deja de responder CORS; requiere el cambio opcional del paso 5 de la guía)
   ```
2. **Túnel** (URL fija `https://campuslab-bff-8080.brs.devtunnels.ms`; dura 30 días):
   ```bash
   devtunnel host campuslab-bff        # en PowerShell o terminal nueva, para que cargue el PATH
   ```
   Si el túnel se vence o lo recrean y cambia la URL: `BFF_URL=<nueva> ./configurar-api.sh`.
3. **Frontend** apuntando a APIM: en `CampusLab---Frontend/src/environments/environment.development.ts`
   `apiUrl: 'https://apim-campuslab-15444.azure-api.net/campuslab/v1/api'` y `npm start`. **No commitear ese cambio**; para el build de producción va en `environment.ts`.

## Verificar

```bash
U=https://apim-campuslab-15444.azure-api.net/campuslab/v1
curl -s -o /dev/null -w "%{http_code}\n" $U/api/public/health          # 200
curl -s -o /dev/null -w "%{http_code}\n" $U/api/catalog/labs           # 401 sin token
curl -s -o /dev/null -w "%{http_code}\n" $U/actuator/health            # 404
curl -si -X OPTIONS $U/api/bookings/1/status -H "Origin: http://localhost:4200" \
  -H "Access-Control-Request-Method: PUT" -H "Access-Control-Request-Headers: authorization,content-type"  # 200 + allow-*
```

## Notas

- **Audience del JWT:** el frontend envía el `id_token`, por eso `validate-jwt` exige el `clientId` del SPA (`34af23ca-…`) y no `api://campuslab-bff`.
- **Origen permitido:** hoy solo `http://localhost:4200`. Para un frontend desplegado, agregar otro `<origin>` en `policy-v1.xml` y volver a aplicarla.
- **`az rest` en Windows:** las respuestas de APIM traen BOM y rompen la consola `cp1252`; por eso `aplicar-politica.sh` guarda la respuesta con `--output-file`.
- **No exponer `ms-campuslab-mq-admin`** (crea y borra colas) por este gateway.

## Limpieza

```bash
az group delete -n rg-campuslab-apim --yes --no-wait
az apim deletedservice purge --service-name apim-campuslab-15444 --location brazilsouth   # solo si quieren reutilizar el nombre
devtunnel delete campuslab-bff
```
