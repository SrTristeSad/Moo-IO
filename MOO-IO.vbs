' Moo IO launcher — no terminal windows.
Option Explicit
Dim fso, sh, base, loveExe, pf, pf86, candidate, item, dirs, paths, i
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)
loveExe = ""
If fso.FileExists(base & "\love.exe") Then loveExe = base & "\love.exe"
If loveExe = "" Then
  pf = sh.ExpandEnvironmentStrings("%ProgramFiles%")
  candidate = pf & "\LOVE\love.exe"
  If fso.FileExists(candidate) Then loveExe = candidate
End If
If loveExe = "" Then
  pf86 = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%")
  candidate = pf86 & "\LOVE\love.exe"
  If fso.FileExists(candidate) Then loveExe = candidate
End If
If loveExe = "" Then
  paths = Split(sh.ExpandEnvironmentStrings("%PATH%"), ";")
  For i = 0 To UBound(paths)
    If Len(paths(i)) > 0 Then
      candidate = paths(i) & "\love.exe"
      If fso.FileExists(candidate) Then
        loveExe = candidate
        Exit For
      End If
    End If
  Next
End If
If loveExe = "" Then
  MsgBox "Moo IO precisa do LÖVE 2D 11.5." & vbCrLf & "Instale em love2d.org e abra este launcher novamente.", 16, "Moo IO"
  WScript.Quit 1
End If
sh.CurrentDirectory = base
sh.Run Chr(34) & loveExe & Chr(34) & " " & Chr(34) & base & Chr(34), 1, False
