# Remove o NitroControl: tarefas, atalhos, registro, configuracoes e a pasta de instalacao.
param([switch]$Elevated)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)   # enum: funciona em qualquer idioma ("Administradores" no pt-BR)
if (-not $isAdmin) {
    if ($Elevated) { exit 1 }   # ja tentou elevar uma vez e mesmo assim nao e admin: para aqui, sem loop
    try { Start-Process powershell "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated" -Verb RunAs } catch {}
    exit
}
Add-Type -AssemblyName System.Windows.Forms
$title = 'NitroControl'
if ([Windows.Forms.MessageBox]::Show('Remover o NitroControl deste computador?', $title, 'YesNo', 'Question') -ne 'Yes') { exit }

$dir = $PSScriptRoot
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | ? { $_.CommandLine -match 'NitroControl\.ps1' } |
    % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process | ? { $_.CommandLine -match 'NitroControl\\browser' } |
    % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

'NitroControl', 'NitroControl Energia' | % { Unregister-ScheduledTask -TaskName $_ -Confirm:$false -ErrorAction SilentlyContinue }
"$([Environment]::GetFolderPath('CommonDesktopDirectory'))\NitroControl.lnk", "$([Environment]::GetFolderPath('CommonPrograms'))\NitroControl.lnk" |
    % { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
Remove-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NitroControl' -Recurse -Force -ErrorAction SilentlyContinue
Start-Sleep 1  # deixa o navegador fechar antes de apagar o perfil dele
Remove-Item "$env:LOCALAPPDATA\NitroControl" -Recurse -Force -ErrorAction SilentlyContinue

[Windows.Forms.MessageBox]::Show("NitroControl removido.`nAs configuracoes da BIOS continuam como estao ate reiniciar.", $title, 'OK', 'Information') | Out-Null
# a pasta e apagada depois que este script termina
Start-Process cmd.exe "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q `"$dir`"" -WindowStyle Hidden
