function StyleTo-Html
{
<#
.SYNOPSIS
    Use pandoc within wsl.exe to postprocess a .md file. The .html file has
    improved styling.

.DESCRIPTION
    Redirect pandoc output into native file system. Add a border on <pre><code>
    sequences, use Courier font, table CSS formatting.
#>
    param(
        [string]$Path = (Get-Item *.md -EA SilentlyContinue | Select-Object -First 1).FullName,
        [string]$Target = "html"
    )

    if (-not $Path -or -not (Test-Path $Path -PathType Leaf)) {
        throw "Specify a .md file to convert to html.";
    }

    $Path = Resolve-Path $Path;
    $i = Get-Item $Path;

    $bn = $i.FullName;
    $cd = $i.DirectoryName;
    $to = $cd + "\" + $i.BaseName + ".$Target";

    if ($Target -eq "html") {
        & ${env:ProgramFiles}\Pandoc\pandoc.exe -f markdown -t $Target $bn > $to;
    } elseif ($Target -eq "pdf") {
        Push-Location $cd
        $from = "./" + $i.Name;
        $to = "./" + $i.BaseName + ".$Target";
        & wsl -- pandoc -H ~/head.tex -f markdown -t $Target --pdf-engine=xelatex $from -o $to -V geometry:a4paper,margin=20mm -V colorlinks;
        Pop-Location;
    } else {
        & ${env:LOCALAPPDATA}\Pandoc\pandoc.exe -f markdown -t $Target $bn -o $to;
    }
    if ($Target -ne "html") {
        return;
    }
    $ct = @'
<html lang="en-us">
<title></title>
<head>
    <style>
    pre {
        border-color: black;
        border-width: 1px;
        border-style: solid;
        background-color: whitesmoke;
        border-radius: 5px;
        padding: 10px;
        text-wrap: pretty;
    }
    code {
        font-family: 'Courier New', Courier, monospace;
        font-size: large;
    }
    body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        font-size: x-large;
    }
    table {
        border-spacing: 0;
    }
    th, td, h1, h2 {
        border-bottom: 1px solid black;
    }
    th, td {
        padding: 4px;
        border-left: 1px solid black;
    }
    blockquote {
        font-style: italic;
        margin-left: 15px;
        margin-right: 15px;
        border-left: 2px solid black;
        padding-left: 5px;
        padding-right: 5px;
    }
    .odd {
        background-color: whitesmoke;
    }
    </style>
</head>
<body>
'@ + (Get-Content -Raw $to) +
@"
</body>
</html>
"@;
    $title = Get-Content $i.FullName -First 1;
    $ct = $ct.Replace("<title></title>", "<title>$title</title>");
    $ct | Set-Content -Encoding utf8 $to;
    Invoke-Item $to;
}
