# NitroControl - painel estilo NitroSense para o Acer Nitro ANV15-52, funciona no Windows 10 e 11.
# Controla o hardware pela interface WMI da BIOS (AcerGamingFunction / BatteryControl), a mesma que o NitroSense usa.
# Valores tirados dos drivers acer-wmi e acer-wmi-battery do Linux.
#
# Como funciona: sem parametros = lancador (usuario normal). Ele inicia uma copia elevada deste script como
# servidor local em localhost, e abre a interface (ui.html) numa janela do Edge/Chrome sem barra de endereco.
# -Apply = reaplica as ultimas escolhas salvas e sai (usado pela tarefa agendada "iniciar com o Windows").
param([int]$Port, [string]$Token, [switch]$Apply)

# ---------------- lancador ----------------
if (-not $Port -and -not $Apply) {
    $Port = Get-Random -Minimum 41000 -Maximum 49000
    $Token = [guid]::NewGuid().ToString('N')
    try { Start-Process powershell "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Port $Port -Token $Token" -Verb RunAs }
    catch { exit }  # usuario recusou o UAC
    for ($n = 0; $n -lt 80; $n++) {
        try { Invoke-WebRequest "http://localhost:$Port/ping" -UseBasicParsing -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep -Milliseconds 250 }
    }
    $url = "http://localhost:$Port/?t=$Token"
    # Edge ou Chrome no modo --app (janela sem barra de endereco)
    $browser = 'msedge.exe', 'chrome.exe' | % {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$_", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$_" -ErrorAction SilentlyContinue).'(default)'
    } | ? { $_ -and (Test-Path $_) } | select -First 1
    if ($browser) { Start-Process $browser "--app=$url --window-size=1360,820 --user-data-dir=`"$env:LOCALAPPDATA\NitroControl\browser`"" }
    else { Start-Process $url }
    exit
}

# ---------------- servidor (elevado) ----------------
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

# -Apply roda escondido no login: registra o que fez em apply.log para dar para ver se funcionou
$logPath = "$env:LOCALAPPDATA\NitroControl\apply.log"
function Log($m) {
    if (-not $Apply) { return }
    try {
        New-Item -ItemType Directory -Force (Split-Path $logPath) | Out-Null
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 100KB) { Remove-Item $logPath }
        Add-Content $logPath "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"
    } catch {}
}
Log "inicio (usuario $env:USERNAME, tomada: $([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus))"

# logo apos o boot o WMI da Acer pode ainda nao estar pronto: no -Apply tenta por ate 40 s (a tarefa tem limite de 2 min)
for ($i = 0; ; $i++) {
    try {
        $wmi = Get-CimInstance -Namespace root\WMI -ClassName AcerGamingFunction
        $cls = Get-CimClass -Namespace root\WMI -ClassName AcerGamingFunction
        if ($wmi) { break }
        throw 'AcerGamingFunction nao encontrado.'
    } catch {
        if (-not $Apply -or $i -ge 20) { Log "ERRO: WMI da Acer nao respondeu: $($_.Exception.Message)"; throw }
        Start-Sleep 2
    }
}
$bat = Get-CimInstance -Namespace root\WMI -ClassName BatteryControl -ErrorAction SilentlyContinue

function Call($method, $value) {
    $t = if ($cls.CimClassMethods[$method].Parameters['gmInput'].CimType -eq 'UInt64') { [uint64] } else { [uint32] }
    (Invoke-CimMethod -InputObject $wmi -MethodName $method -Arguments @{ gmInput = ($value -as $t) }).gmOutput
}
function Byte1($v) { ($v -shr 8) -band 0xFF }
function Sensor($id) { ((Call GetGamingSysInfo (($id -shl 8) -bor 1)) -shr 8) -band 0xFFFF }
function Check($r) { if ($r -band 0xFF) { throw "A BIOS recusou o comando (codigo $r)." } }

try {
    $cpuUse = New-Object Diagnostics.PerformanceCounter 'Processor Information', '% Processor Utility', '_Total'
    $cpuPerf = New-Object Diagnostics.PerformanceCounter 'Processor Information', '% Processor Performance', '_Total'
    $null = $cpuUse.NextValue(); $null = $cpuPerf.NextValue()
} catch { $cpuUse = $cpuPerf = $null }
$maxMhz = (Get-CimInstance Win32_Processor | select -First 1).MaxClockSpeed

function Get-BattLimit {
    if (-not $bat) { return $null }
    $r = Invoke-CimMethod -InputObject $bat -MethodName GetBatteryHealthControlStatus -Arguments @{
        uBatteryNo = [byte]1; uFunctionQuery = [byte]1; uReserved = [byte[]](0, 0) }
    if (-not ($r.uFunctionList -band 1)) { return $null }  # BIOS sem modo de saude da bateria
    $r.uFunctionStatus[0] -eq 1
}

function Get-State {
    $ps = [Windows.Forms.SystemInformation]::PowerStatus
    $cfg = Load-Cfg
    $os =Get-CimInstance Win32_OperatingSystem
    $gpu = @(0, 0)
    try { $gpu = (nvidia-smi --query-gpu=utilization.gpu,clocks.gr --format=csv,noheader,nounits) -split ',\s*' } catch {}
    [ordered]@{
        cpuT = Sensor 0x01; gpuT = Sensor 0x0A; sysT = Sensor 0x03
        cpuFan = Sensor 0x02; gpuFan = Sensor 0x06
        profile = Byte1 (Call GetGamingMiscSetting 0x0B)
        fanMode = (Byte1 (Call GetGamingFanBehavior 0x9)) -band 0x3   # 1 auto, 2 maximo, 3 personalizado
        cpuPct = Byte1 (Call GetGamingFanSpeed 1); gpuPct = Byte1 (Call GetGamingFanSpeed 4)
        cpuUse = if ($cpuUse) { [math]::Min(100, [math]::Round($cpuUse.NextValue())) } else { 0 }
        cpuClk = if ($cpuPerf) { [math]::Round($maxMhz * $cpuPerf.NextValue() / 100) } else { $maxMhz }
        gpuUse = [int]$gpu[0]; gpuClk = [int]$gpu[1]
        ram = [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize), 1)
        ac = $ps.PowerLineStatus -eq 'Online'; batt = [int]($ps.BatteryLifePercent * 100)
        battLimit = Get-BattLimit
        autostart = $script:autostart
        autoSwitch = $cfg['autoSwitch'] -eq 1; profileAC = $cfg['profileAC']; profileDC = $cfg['profileDC']
    }
}

$cfgPath = "$env:LOCALAPPDATA\NitroControl\settings.json"
$taskName = 'NitroControl'

function Load-Cfg {
    $c = @{}
    try { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | % { $c[$_.Name] = $_.Value } } catch {}
    $c
}
function Save-Cfg($k, $v) {
    $c = Load-Cfg; $c[$k] = $v
    New-Item -ItemType Directory -Force (Split-Path $cfgPath) | Out-Null
    $c | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
}

$powerTask = 'NitroControl Energia'
function Is-AC { [Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online' }
function Test-Task($name) { [bool](Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) }
function New-EventTrigger($provider, $id, $delay) {
    $cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskEventTrigger
    New-CimInstance -CimClass $cls -ClientOnly -Property @{ Enabled = $true; Delay = $delay
        Subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='$provider'] and EventID=$id]]</Select></Query></QueryList>" }
}
# Ambas as tarefas rodam "-Apply"; o -Apply decide o que aplicar olhando se esta na tomada ou na bateria.
function Set-Task($name, $on, $triggers) {
    if (-not $on) { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue; return }
    $vbs = "$PSScriptRoot\run.vbs"  # via wscript nao pisca janela ao ligar/desligar o carregador
    $act = if (Test-Path $vbs) { New-ScheduledTaskAction -Execute wscript.exe -Argument "`"$vbs`" -Apply" }
           else { New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Apply" }
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    $pr = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $name -Action $act -Trigger $triggers -Settings $set -Principal $pr -Force | Out-Null
}
function Set-Autostart($on) {
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $logon.Delay = 'PT20S'
    # ao sair da suspensao/hibernacao a BIOS pode voltar as ventoinhas para o automatico
    Set-Task $taskName $on @($logon, (New-EventTrigger 'Microsoft-Windows-Power-Troubleshooter' 1 'PT5S'))
}
# Kernel-Power 105 = carregador conectado/desconectado
function Set-AutoSwitch($on) { Set-Task $powerTask $on @(New-EventTrigger 'Microsoft-Windows-Kernel-Power' 105 'PT3S') }

# Reaplica o que foi salvo. Com troca automatica: modo da tomada/bateria e, na bateria, ventoinhas no automatico.
function Apply-Saved {
    $c = Load-Cfg; $ac = Is-AC; $prof = $c['profile']; $fan = $c['fan']
    if (-not $c.Count) { Log "nada salvo em $cfgPath"; return }
    # velocidade salva sem modo salvo: o controle so fica ativo no Personalizado, entao o modo era esse
    if ($null -eq $fan -and ($null -ne $c['cpuPct'] -or $null -ne $c['gpuPct'])) { $fan = 3 }
    if ($c['autoSwitch'] -eq 1) {
        $prof = if ($ac) { if ($null -ne $c['profileAC']) { $c['profileAC'] } else { 4 } }
                else { if ($null -ne $c['profileDC']) { $c['profileDC'] } else { 1 } }
        if (-not $ac -and $null -ne $fan) { $fan = 1 }
    }
    $plan = [ordered]@{ profile = $prof; fan = $fan; cpuPct = $c['cpuPct']; gpuPct = $c['gpuPct']; battLimit = $c['battLimit'] }
    foreach ($k in $plan.Keys) {
        if ($null -eq $plan[$k]) { continue }
        if ($k -like '*Pct' -and $fan -ne 3) { continue }  # velocidade so vale no modo personalizado
        try { Set-Value $k $plan[$k] -NoSave; Log "$k = $($plan[$k]) ok" }
        catch { Log "$k = $($plan[$k]) FALHOU: $($_.Exception.Message)" }  # ex.: Desempenho recusado na bateria
    }
}

function Set-Value($k, [int]$v, [switch]$NoSave) {
    switch ($k) {
        'autostart' { Set-Autostart ([bool]$v); $script:autostart = Test-Task $taskName; return }
        'autoSwitch' {
            if ($v) {  # primeira vez: o modo atual vira o padrao da fonte de energia atual
                $c = Load-Cfg; $cur = Byte1 (Call GetGamingMiscSetting 0x0B)
                if ($null -eq $c['profileAC']) { Save-Cfg profileAC $(if (Is-AC) { $cur } else { 4 }) }
                if ($null -eq $c['profileDC']) { Save-Cfg profileDC $(if (Is-AC) { 1 } else { $cur }) }
            }
            Save-Cfg autoSwitch ([int][bool]$v); Set-AutoSwitch ([bool]$v)
            if ($v) { Apply-Saved }
            return
        }
        'profile' {
            if ($v -notin 0, 1, 4) { throw 'Perfil invalido.' }
            Check (Call SetGamingMiscSetting (([uint64]$v -shl 8) -bor 0x0B))
        }
        'fan' {
            # bits 0 e 3 = ventoinha CPU e GPU; modo na CPU bits 16-17, GPU bits 22-23
            $map = @{ 1 = 0x410009; 2 = 0x820009; 3 = 0xC30009 }
            if (-not $map.ContainsKey($v)) { throw 'Modo de ventoinha invalido.' }
            Check (Call SetGamingFanBehavior $map[$v])
        }
        { $_ -in 'cpuPct', 'gpuPct' } {
            $v = [math]::Max(20, [math]::Min(100, $v))  # minimo 20% para nao deixar o notebook sem ventilacao
            $id = if ($k -eq 'cpuPct') { 1 } else { 4 }
            Check (Call SetGamingFanSpeed (([uint64]$v -shl 8) -bor $id))
        }
        'battLimit' {
            if (-not $bat) { throw 'Controle de bateria nao disponivel.' }
            $r = Invoke-CimMethod -InputObject $bat -MethodName SetBatteryHealthControl -Arguments @{
                uBatteryNo = [byte]1; uFunctionMask = [byte]1; uFunctionStatus = [byte]([bool]$v); uReservedIn = [byte[]](0, 0, 0, 0, 0) }
            if ($r.uReturn) { throw "A BIOS recusou o comando (codigo $($r.uReturn))." }
        }
        default { throw 'Comando desconhecido.' }
    }
    if ($NoSave) { return }
    Save-Cfg $k $v  # so chega aqui se a BIOS aceitou
    # mexer na velocidade so e possivel no Personalizado: salva o modo junto, senao o -Apply pula a velocidade
    if ($k -like '*Pct') { Save-Cfg fan 3 }
    # com troca automatica, o modo escolhido vira o padrao da fonte de energia atual (igual ao NitroSense)
    if ($k -eq 'profile' -and (Load-Cfg)['autoSwitch'] -eq 1) { Save-Cfg $(if (Is-AC) { 'profileAC' } else { 'profileDC' }) $v }
}

if ($Apply) {
    try {
        Apply-Saved
        # a BIOS/servicos da Acer podem voltar as ventoinhas para o automatico logo depois do login: reaplica
        Start-Sleep 40
        Log 'segunda passada'
        Apply-Saved
        Log 'fim'
    } catch { Log "ERRO: $($_.Exception.Message)"; exit 1 }
    exit
}
$script:autostart = Test-Task $taskName

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
$last = Get-Date

while ($true) {
    $task = $listener.GetContextAsync()
    # janela fechada = sem pedidos; encerra depois de 2 min (o Edge reduz timers de janelas minimizadas)
    while (-not $task.Wait(1000)) { if (((Get-Date) - $last).TotalSeconds -gt 120) { $listener.Stop(); exit } }
    $ctx = $task.Result; $req = $ctx.Request; $q = $req.QueryString; $last = Get-Date
    $code = 200; $type = 'application/json; charset=utf-8'; $bytes = $null
    try {
        $path = $req.Url.AbsolutePath
        if ($path -eq '/') { $type = 'text/html; charset=utf-8'; $body = [IO.File]::ReadAllText("$PSScriptRoot\ui.html", [Text.Encoding]::UTF8) }
        elseif ($path -eq '/ping') { $body = '"ok"' }
        elseif ($path -eq '/favicon.ico') { $type = 'image/x-icon'; $bytes = [IO.File]::ReadAllBytes("$PSScriptRoot\icon.ico") }
        elseif ($q['t'] -ne $Token) { $code = 403; $body = '{"error":"acesso negado"}' }
        elseif ($path -eq '/api/state') { $body = Get-State | ConvertTo-Json -Compress }
        elseif ($path -eq '/api/set' -and $req.HttpMethod -eq 'POST') { Set-Value $q['k'] $q['v']; $body = Get-State | ConvertTo-Json -Compress }
        else { $code = 404; $body = '{"error":"nao encontrado"}' }
    } catch { $code = 500; $body = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress }
    if ($null -eq $bytes) { $bytes = [Text.Encoding]::UTF8.GetBytes($body) }
    $ctx.Response.StatusCode = $code; $ctx.Response.ContentType = $type
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
}
