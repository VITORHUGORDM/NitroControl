# Instala o NitroControl em Arquivos de Programas, cria atalhos e registra o desinstalador no Windows.
# Roda de dentro do NitroControl-Setup.exe (os arquivos vem extraidos na mesma pasta deste script).
param([switch]$Elevated)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)   # enum: funciona em qualquer idioma ("Administradores" no pt-BR)
if (-not $isAdmin) {
    if ($Elevated) { exit 1 }   # ja tentou elevar uma vez e mesmo assim nao e admin: para aqui, sem loop
    # -Wait: o Setup.exe apaga a pasta temporaria assim que este processo termina
    try { $p = Start-Process powershell "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated" -Verb RunAs -Wait -PassThru; exit $p.ExitCode }
    catch { exit 1 }
}
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$title = 'NitroControl'

try {
    $dest = "$env:ProgramFiles\NitroControl"
    # fecha o app se estiver aberto (o servidor segura os arquivos)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -match 'NitroControl\.ps1' } |
        % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    New-Item -ItemType Directory -Force $dest | Out-Null
    'NitroControl.ps1', 'ui.html', 'run.vbs', 'icon.ico', 'uninstall.ps1' | % { Copy-Item "$PSScriptRoot\$_" $dest -Force }

    $sh = New-Object -ComObject WScript.Shell
    $startLnk = "$([Environment]::GetFolderPath('CommonPrograms'))\NitroControl.lnk"
    foreach ($lnk in "$([Environment]::GetFolderPath('CommonDesktopDirectory'))\NitroControl.lnk", $startLnk) {
        $l = $sh.CreateShortcut($lnk)
        $l.TargetPath = "$env:windir\System32\wscript.exe"; $l.Arguments = "`"$dest\run.vbs`""
        $l.IconLocation = "$dest\icon.ico,0"; $l.WorkingDirectory = $dest; $l.Description = 'Modos, ventoinhas e bateria do Acer Nitro'
        $l.Save()
    }

    # tarefas ja criadas ("iniciar com o Windows" / troca automatica) passam a usar a copia instalada
    foreach ($n in 'NitroControl', 'NitroControl Energia') {
        if (Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue) {
            Set-ScheduledTask -TaskName $n -Action (New-ScheduledTaskAction -Execute wscript.exe -Argument "`"$dest\run.vbs`" -Apply") | Out-Null
        }
    }

    $u = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NitroControl'
    New-Item $u -Force | Out-Null
    $vals = @{ DisplayName = 'NitroControl'; DisplayVersion = '1.0'; Publisher = 'NitroControl'; DisplayIcon = "$dest\icon.ico"
        InstallLocation = $dest; UninstallString = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\uninstall.ps1`"" }
    $vals.GetEnumerator() | % { New-ItemProperty $u -Name $_.Key -Value $_.Value -PropertyType String -Force | Out-Null }
    'NoModify', 'NoRepair' | % { New-ItemProperty $u -Name $_ -Value 1 -PropertyType DWord -Force | Out-Null }

    $r = [Windows.Forms.MessageBox]::Show("NitroControl instalado.`n`nO atalho esta na Area de Trabalho e no Menu Iniciar. Abrir agora?", $title, 'YesNo', 'Information')
    # explorer.exe abre o atalho como usuario normal (nao como administrador)
    if ($r -eq 'Yes') { Start-Process explorer.exe "`"$startLnk`"" }
} catch {
    [Windows.Forms.MessageBox]::Show("Erro na instalacao:`n$($_.Exception.Message)", $title, 'OK', 'Error') | Out-Null
    exit 1
}
