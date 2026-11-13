# Gera NitroControl-Setup.exe com o IExpress (vem no Windows). Rodar de novo sempre que mudar algum arquivo do app.
$here = $PSScriptRoot
$files = 'install.ps1', 'uninstall.ps1', 'NitroControl.ps1', 'ui.html', 'run.vbs', 'icon.ico'
$target = "$here\NitroControl-Setup.exe"
$sed = "$env:TEMP\NitroControl.sed"

$strings = for ($i = 0; $i -lt $files.Count; $i++) { "FILE$i=`"$($files[$i])`"" }
$list = for ($i = 0; $i -lt $files.Count; $i++) { "%FILE$i%=" }
@"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=NitroControl
AppLaunched=cmd /c powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
$($strings -join "`r`n")
[SourceFiles]
SourceFiles0=$here\
[SourceFiles0]
$($list -join "`r`n")
"@ | Set-Content $sed -Encoding ASCII

Remove-Item $target -ErrorAction SilentlyContinue
Start-Process "$env:windir\System32\iexpress.exe" -ArgumentList '/N', '/Q', $sed -Wait
if (Test-Path $target) { "Gerado: $target" } else { throw 'IExpress nao gerou o instalador.' }
