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
        [string]$Path = (Get-Item *.md -EA SilentlyContinue | Select -First 1).FullName
    )

    if (-not $Path -or -not (Test-Path $Path -PathType Leaf)) {
        throw "Specify a .md file to convert to html.";
    }

    $Path = Resolve-Path $Path;
    $i = Get-Item $Path;

    $bn = $i.Name;
    $cd = $i.DirectoryName;
    $to = $cd + "\" + $i.BaseName + ".html";

    & wsl.exe --cd $cd -- pandoc -f markdown_mmd -t html ./$bn > $to;
    $ct = @'
<html lang="en-us">
<head>
    <style>
        pre {
            border-color: black;
            border-width: 1px;
            border-style: solid;
            background-color: whitesmoke;
        }
        code {
            font-family: 'Courier New', Courier, monospace;
        }
        body {
            font-family: Tahoma;
        }
        h1, h2 {
            text-decoration: underline;
        }
        th, td {
            border-bottom-color: black;
            border-bottom-width: 1px;
            border-bottom-style: solid;
            border-spacing: 0;
        }
        th, td {
            padding-left: 0;
            padding-right: 0;
        }
        blockquote {
            font-family: 'Times New Roman', Times, serif;
            font-style: italic;
        }
    </style>
</head>
<body>
'@ + (Get-Content -Raw $to) +
@"
</body>
</html>
"@;
    $ct | Set-Content -Encoding utf8 $to;
    Invoke-Item $to;
}
