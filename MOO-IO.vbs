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
' Prepare artwork for hosts and guests before opening LÖVE.
' PowerShell remains invisible. Errors have a readable local log.
Dim assetCommand, assetStatus
If Not fso.FileExists(base & "\assets\reference\img\weapons\hammer_1.png") Then
  sh.Popup "Primeira abertura: preparando as imagens do jogo. Isso requer internet caso voce ainda nao tenha os sprites locais.", 5, "Moo IO - preparando imagens", 64
End If
assetCommand = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & Chr(34) & base & "\scripts\prepare-assets.ps1" & Chr(34)
sh.CurrentDirectory = base
assetStatus = sh.Run(assetCommand, 0, True)
If assetStatus <> 0 Then
  MsgBox "Nao foi possivel preparar as imagens." & vbCrLf & "Confira ARTES-PENDENTES.txt ou server\data\mooio-assets.log.", 16, "Moo IO"
  WScript.Quit assetStatus
End If
sh.Run Chr(34) & loveExe & Chr(34) & " " & Chr(34) & base & Chr(34), 1, False
