' NSRU Lab NetKeepAlive hidden launcher
' Runs KeepAlive.ps1 without showing any console window (WindowStyle 0)
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = scriptDir & "\KeepAlive.ps1"

If fso.FileExists(psScript) Then
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """"
    WshShell.Run cmd, 0, False
End If
