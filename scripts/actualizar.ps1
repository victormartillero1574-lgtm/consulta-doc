# Recolector diario de jurisprudencia (sumarios) y doctrina desde SAIJ (datos publicos).
# Compatible con Windows PowerShell 5.1 y PowerShell 7 (pwsh en GitHub Actions).
param([int]$PorConsulta = 100, [int]$Pagina = 50, [int]$MaxEnriquecer = 0)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
$salida = Join-Path $raiz 'docs/data/docs.json'
$headers = @{ Accept = 'application/json'; 'X-Requested-With' = 'XMLHttpRequest' }

$ER = "Entre R$([char]0xED)os"; $JUR = "Jurisdicci$([char]0xF3)n"
$consultas = @(
    @{ ambito = $ER;           tipo = 'Jurisprudencia'; faceta = "Total|Tipo de Documento/Jurisprudencia/Sumario|$JUR/Local/$ER" },
    @{ ambito = 'Nacional';    tipo = 'Jurisprudencia'; faceta = 'Total|Tipo de Documento/Jurisprudencia/Sumario' },
    @{ ambito = 'Nacional';    tipo = 'Doctrina';       faceta = 'Total|Tipo de Documento/Doctrina' }
)

function Como-Lista($x) { if ($null -eq $x) { @() } else { @($x) } }

$base = @{}
if (Test-Path $salida) {
    foreach ($d in (Get-Content $salida -Raw -Encoding UTF8 | ConvertFrom-Json)) { $base[$d.id] = $d }
}
$hoy = (Get-Date).ToString('yyyy-MM-dd')
$nuevos = 0

foreach ($c in $consultas) {
    $obtenidos = 0
    for ($o = 0; $o -lt $PorConsulta; $o += $Pagina) {
        $f = [uri]::EscapeDataString($c.faceta)
        $u = "https://www.saij.gob.ar/busqueda?o=$o&p=$Pagina&f=$f&s=fecha-rango%7CDESC&v=colapsada"
        try {
            $resp = Invoke-WebRequest -Uri $u -Headers $headers -UseBasicParsing -TimeoutSec 60
            $json = $resp.Content | ConvertFrom-Json
        } catch {
            Write-Warning "Fallo consulta $($c.ambito)/$($c.tipo) offset $o : $($_.Exception.Message)"
            break
        }
        $lista = Como-Lista $json.searchResults.documentResultList
        if ($lista.Count -eq 0) { break }
        foreach ($item in $lista) {
            $doc = ($item.documentAbstract | ConvertFrom-Json).document
            $meta = $doc.metadata; $cont = $doc.content
            $id = $meta.uuid
            if ($base.ContainsKey($id)) { continue }
            $desc = @(Como-Lista $cont.descriptores.descriptor | ForEach-Object { $_.elegido.termino } | Where-Object { $_ })
            if ($c.tipo -eq 'Doctrina') {
                $titulo = $cont.'titulo-doctrina'
                $texto = ''
                $autores = @(Como-Lista $cont.'autor-doctrina'.autor)
                $num = $cont.'numero-doctrina'
            } else {
                $titulo = $doc.titulo; if (-not $titulo) { $titulo = $cont.titulo }
                $texto = $cont.texto
                $autores = @()
                $num = $cont.'numero-sumario'
            }
            if (-not $titulo -and -not $texto) { continue }
            $base[$id] = [pscustomobject]@{
                id = $id; tipo = $c.tipo; ambito = $c.ambito; numero = $num
                titulo = $titulo; texto = $texto; autores = $autores; descriptores = $desc
                url = "https://www.saij.gob.ar/$($meta.'friendly-url'.description)"
                agregado = $hoy
            }
            $nuevos++; $obtenidos++
        }
        Start-Sleep -Milliseconds 700
    }
    Write-Host "$($c.ambito) / $($c.tipo): $obtenidos nuevos"
}

# Completar datos del fallo (fecha, caratula, provincia, materia, publicacion) desde SAIJ
if ($MaxEnriquecer -le 0) { $MaxEnriquecer = if ($PorConsulta -ge 1000) { 3000 } else { 700 } }
$pend = @($base.Values | Where-Object { -not $_.PSObject.Properties['enriquecido'] } | Sort-Object agregado, id | Select-Object -First $MaxEnriquecer)
$hechos = 0
foreach ($doc in $pend) {
    try {
        $r = Invoke-WebRequest -Uri "https://www.saij.gob.ar/view-document?guid=$($doc.id)" -Headers $headers -UseBasicParsing -TimeoutSec 40
        $c = (($r.Content | ConvertFrom-Json).data | ConvertFrom-Json).document.content
    } catch { continue }
    $nuevo = [ordered]@{ fecha = $c.fecha; caratula = ("$($c.caratula)" -replace '\s+', ' ').Trim(); provincia = $c.provincia; materia = $c.materia; sala = $c.sala; publicacion = $c.publicacion; enriquecido = $true }
    foreach ($k in $nuevo.Keys) { $doc | Add-Member -NotePropertyName $k -NotePropertyValue $nuevo[$k] -Force }
    $hechos++
    Start-Sleep -Milliseconds 300
}
Write-Host "Datos completados: $hechos de $($pend.Count)"

New-Item -ItemType Directory -Force (Split-Path $salida) | Out-Null
$todos = @($base.Values | Sort-Object agregado -Descending)
$jsonOut = ConvertTo-Json -InputObject $todos -Depth 6 -Compress
[System.IO.File]::WriteAllText($salida, $jsonOut, (New-Object System.Text.UTF8Encoding $false))
$metaOut = @{ actualizado = (Get-Date).ToUniversalTime().ToString('o'); total = $todos.Count; nuevos_hoy = $nuevos } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText((Join-Path (Split-Path $salida) 'meta.json'), $metaOut, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Total en base: $($todos.Count) | Nuevos: $nuevos"
