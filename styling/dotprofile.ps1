function StyleTo-Html
{
<#
.SYNOPSIS
    Use pandoc within wsl.exe to postprocess a .md file. The .html file has
    improved styling.

.DESCRIPTION
    Redirect pandoc output into native file system. Add a border on <pre><code>
    sequences, use Courier font.

    Add the html file to the git index.

.NOTES
    A pandoc bug prevents conversion of sporadic keys. Until the cause is fixed,
    the function is deactivated.
    wsl --status
    Default Distribution: openSUSE-Leap-15.4
    Default Version: 2

#>
    param(
        [string]$Path = (Get-Item *.md -EA SilentyContinue | Select -First 1).FullName
    )

    if (-not $Path) {
        throw "Specify a .md file to convert to html.";
    }

    throw "pandoc within wsl.exe cannot render *.\microcontroller.exe*: StyleTo-Html .\NtQueryTimerResolution\usleep.html";

    $Path = Resolve-Path $Path;
    $i = Get-Item $Path;

    $bn = $i.Name;
    $cd = $i.DirectoryName;
    $to = $cd + "\" + $i.BaseName + ".html";

    & wsl.exe --cd $cd -- pandoc -f markdown ./$bn > $to;
    $ct = @'
<html lang="en-us">
<head>
    <style>
        .newcode {
            font-family: 'Courier New', Courier, monospace;
            border-color: black;
            border-width: 1px;
            border-style: solid;
        }
    </style>
</head>
<body>
'@ + (Get-Content -Raw $to).Replace("<pre><code>", "<pre class=""newcode""><code>") +
@"
</body>
</html>
"@;
    $ct | Set-Content -Encoding utf8 $to;

    Push-Location $cd;
    & git add -- $to;
    Pop-Location;
}
