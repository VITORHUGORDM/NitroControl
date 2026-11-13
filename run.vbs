' Abre o NitroControl sem piscar janela do PowerShell. Argumentos (ex.: -Apply) sao repassados.
Set fso = CreateObject("Scripting.FileSystemObject")
cmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & fso.GetParentFolderName(WScript.ScriptFullName) & "\NitroControl.ps1"""
For Each a In WScript.Arguments
    cmd = cmd & " " & a
Next
CreateObject("WScript.Shell").Run cmd, 0, False
