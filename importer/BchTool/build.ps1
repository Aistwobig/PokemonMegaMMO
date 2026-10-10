# Builds BchTool.exe next to SPICA.dll. Needs SPICA built first (see importer/README.md).
param([string]$Spica = "D:\Tools\SPICA")

$csc = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\Roslyn\csc.exe"
$fw = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
& $csc /nologo /optimize /target:exe /platform:anycpu `
    /out:"$Spica\BchTool.exe" `
    /r:"$Spica\SPICA.dll" /r:"$fw\System.Drawing.dll" /r:"$fw\System.Numerics.dll" /r:"$fw\System.Web.Extensions.dll" `
    "$PSScriptRoot\Program.cs"
if ($LASTEXITCODE -eq 0) { "built $Spica\BchTool.exe" }
