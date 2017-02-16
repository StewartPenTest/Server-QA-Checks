﻿<#
    Compiles all the needed powershell files for QA checks into one master script.
#>

Param ([string]$Settings)
Set-StrictMode -Version 2

If ([string]::IsNullOrEmpty($Settings)) { $Settings = 'default-settings.ini' }
[string]$version = ('v3.{0}.{1}' -f (Get-Date -Format 'yy'), (Get-Date -Format 'MMdd'))
[string]$date    = Get-Date -Format 'yyyy/MM/dd HH:mm'
[string]$path    = Split-Path (Get-Variable MyInvocation -ValueOnly).MyCommand.Path
Try { $gh = Get-Host;  [int]$ws = $gh.UI.RawUI.WindowSize.Width - 2 } Catch { [int]$ws = 80 }
If ($ws -lt 80) { $ws = 80 }

###################################################################################################
# Required Functions                                                                              #
###################################################################################################

Function Write-Colr
{
    Param ([String[]]$Text,[ConsoleColor[]]$Colour,[Switch]$NoNewline=$false)
    For ([int]$i = 0; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -Foreground $Colour[$i] -NoNewLine }
    If ($NoNewline -eq $false) { Write-Host '' }
}

Function Write-Header
{
    Param ([string]$Message,[int]$Width); $underline=''.PadLeft($Width-16,'─')
    $q=('╔═══════════╗    ','','','','║           ║    ','','','','║  ','█▀█ █▀█','  ║    ','','║  ','█▄█ █▀█','  ║    ','','║  ',' ▀     ','  ║    ','','║  ',' CHECK ','  ║','  ██','║  ','       ','  ║',' ██ ','║  ','      ','','██▄ ██  ','╚════════','','',' ▀██▀ ')
    $s=('QA Script Engine','Written by Mike @ My Random Thoughts','support@myrandomthoughts.co.uk','','','',$Message,$version,$underline)
    [System.ConsoleColor[]]$c=('White','Gray','Gray','Red','Cyan','Red','Green','Yellow','Yellow');Write-Host ''
    For ($i=0;$i-lt$q.Length;$i+=4) { Write-Colr '  ',$q[$i],$q[$i+1],$q[$i+2],$q[$i+3],$s[$i/4].PadLeft($Width-19) -Colour Yellow,White,Cyan,White,Green,$c[$i/4] }
    Write-Host ''
}

Function DivLine { Param ([int]$Width); Return ' '.PadRight($Width, '─') }
Function Load-IniFile
{
    Param ([string]$InputFile)
    If ((Test-Path -Path $InputFile) -eq $false)
    {
        Switch (Split-Path -Path (Split-Path -Path $InputFile -Parent) -Leaf)
        {
            'i18n'     { [string]$errMessage = '  ERROR: Language ' }
            'settings' { [string]$errMessage = '  ERROR: Settings ' }
            Default    { [string]$errMessage = (Split-Path -Path (Split-Path -Path $InputFile -Parent) -Leaf) }
        }
        Write-Host ($errMessage + 'file "{0}" not found.' -f (Split-Path -Path $InputFile -Leaf)) -ForegroundColor Red
        Write-Host  '  ERROR:'$InputFile                                                          -ForegroundColor Red
        Write-Host ''
        Break
    }

    [string]   $comment = ";"
    [string]   $header  = "^\s*(?!$($comment))\s*\[\s*(.*[^\s*])\s*]\s*$"
    [string]   $item    = "^\s*(?!$($comment))\s*([^=]*)\s*=\s*(.*)\s*$"
    [hashtable]$ini     = @{}
    Switch -Regex -File $inputfile {
        "$($header)" { $section = ($matches[1] -replace ' ','_'); $ini[$section.Trim()] = @{} }
        "$($item)"   { $name, $value = $matches[1..2]; If (($name -ne $null) -and ($section -ne $null)) { $ini[$section][$name.Trim()] = $value.Trim() } }
    }
    Return $ini
}

###################################################################################################

Clear-Host
Write-Header -Message 'QA Script Engine Check Compiler' -Width $ws

# Load settings file
[hashtable]$iniSettings = (Load-IniFile -InputFile ("$path\settings\$Settings" ))
[hashtable]$lngStrings  = (Load-IniFile -InputFile ("$path\i18n\{0}_text.ini" -f ($iniSettings['settings']['language'])))
[string]$shared = "Function newResult { Return ( New-Object -TypeName PSObject -Property @{'server'=''; 'name'=''; 'check'=''; 'datetime'=(Get-Date -Format 'yyyy-MM-dd HH:mm'); 'result'='Unknown'; 'message'=''; 'data'='';} ) }"

[string]$scriptHeader = @"
#Requires -Version 2
<#
    QA MASTER SCRIPT

    DO NOT EDIT THIS FILE - ALL CHANGES WILL BE LOST
    THIS FILE IS AUTO-COMPILED FROM SEVERAL SOURCE FILES

    VERSION : $version
    COMPILED: $date
#> 

"@
$scriptHeader += @' 

[CmdletBinding(DefaultParameterSetName = 'HLP')]
Param (
    [Parameter(ParameterSetName='QAC', Mandatory=$true, Position=1)][string[]]$ComputerName,
    [Parameter(ParameterSetName='QAC', Mandatory=$false           )][switch]  $SkipHTMLHelp,
    [Parameter(ParameterSetName='QAC', Mandatory=$false           )][switch]  $GenerateCSV,
    [Parameter(ParameterSetName='QAC', Mandatory=$false           )][switch]  $GenerateXML,
    [Parameter(ParameterSetName='HLP', Mandatory=$false           )][switch]  $Help
)

Set-StrictMode -Version 2
 
'@

[string]$shortcode = ($iniSettings['settings']['shortcode'] + '_').ToString().Replace(' ', '-')
If ($shortcode -eq '_') { $shortcode = '' }

Write-Host '  Removing Previous Check Versions...... ' -NoNewline -ForegroundColor White
[string]$outPath = "$path\QA_$shortcode$version.ps1"
If (Test-Path -Path $outPath) { Try { Remove-Item $outPath -Force } Catch { } }
Write-host 'Done' -ForegroundColor Green

###################################################################################################
# Build CHECKs Script                                                                             #
###################################################################################################

# Get full list of checks...
[object]$qaChecks = Get-ChildItem -Path ($path + '\checks') -Recurse |
    Where-Object { (-not $_.PSIsContainer) -and ($_.Name).StartsWith('c-') -and ($_.Name).EndsWith('.ps1') -and (-not ($_.DirectoryName).Contains('-specific')) |
    Sort-Object $_.Name
}

###################################################################################################
# CHECKS building                                                                                 #
###################################################################################################

Write-Colr '  Generating New QA Check Script........ ', $qaChecks.Count, ' checks ' -Colour White, Green, White
Write-Colr '  Using Settings File................... ', $Settings.ToUpper()         -Colour White, Green
Write-Host '   ' -NoNewline; For ($j = 0; $j -lt ($qaChecks.Count + 5); $j++) { Write-Host '▄' -NoNewline -ForegroundColor DarkGray }; Write-Host ''
Write-Host '   ' -NoNewline

# Start building the QA file
Out-File -FilePath $outPath -InputObject $scriptHeader                                                                 -Encoding utf8
Out-File -FilePath $outPath -InputObject ('[string]   $version               = "' + $version   + '"')                  -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('[string]   $settingsFile          = "' + $Settings  + '"')                  -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('[hashtable]$script:lang           = @{}'                 )                  -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('[hashtable]$script:qahelp         = @{}'                 )                  -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('')                                                                          -Encoding utf8 -Append

# Add the shared variables code
Out-File -FilePath $outPath -InputObject ($shared)                                                                     -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('')                                                                          -Encoding utf8 -Append; Write-Host '▀' -NoNewline -ForegroundColor Cyan

# Get a list of all the checks, adding them into an array
[string]$cList = '[array]$script:qaChecks = ('
[string]$cLine = ''
ForEach ($qa In $qaChecks)
{
    [string]$checkName = ($qa.BaseName).Substring(1, 8).Replace('-','')
    If (-not $iniSettings["$checkName-skip"])
    {
        $cCheck = 'c-' + $qa.BaseName.Substring(2); $cLine += "'$cCheck',"
        If ($cList.EndsWith('(')) { $space = '' } Else { $space = "`n".PadRight(28) }
        If ($cLine.Length -ge 130) { $cList += "$space$cLine"; $cLine='' }
    }
}

If ($cLine.Length -gt 10)
{
    If ($cList.Substring($cList.Length - 10, 10) -ne $cLine.Substring($cLine.Length - 10, 10))
    {
        $cList += "$space$cLine"
        $cLine=''
    }
}

$cList = $cList.Trim(',') + ')'
Out-File -FilePath $outPath -InputObject $cList                                                                        -Encoding utf8 -Append; Write-Host '▀' -NoNewline -ForegroundColor Cyan
Out-File -FilePath $outPath -InputObject ('')                                                                          -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject (''.PadLeft(190, '#'))                                                        -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('# QA Check Script Blocks')                                                  -Encoding utf8 -Append

[System.Text.StringBuilder]$qaHelp = ''

# Add each check into the script
ForEach ($qa In $qaChecks)
{
    Out-File -FilePath $outPath -InputObject "`$c$($qa.Name.Substring(2, 6).Replace('-','')) = {"                      -Encoding utf8 -Append
    Out-File -FilePath $outPath -InputObject ($shared)                                                                 -Encoding utf8 -Append
    
    Out-File -FilePath $outPath -InputObject '$script:lang        = @{}'                                               -Encoding utf8 -Append
    Out-File -FilePath $outPath -InputObject '$script:appSettings = @{}'                                               -Encoding utf8 -Append
    [string]$checkName = ($qa.Name).Substring(1, 8).Replace('-','')
    If ($iniSettings["$checkName-skip"]) { $checkName += '-skip' }

    # Add each checks settings
    Try {
        ForEach ($key In ($iniSettings[$checkName].Keys | Sort-Object))
        {
            [string]$value = $iniSettings[$checkName][$key]
            If ($value -eq '') { $value = "''" }
            [string]$appSetting = ('$script:appSettings[' + "'{0}'] = {1}" -f $key, $value)
            Out-File -FilePath $outPath -InputObject $appSetting                                                       -Encoding utf8 -Append
        }
    } Catch { }

    # Add language specific strings to each check
    Try
    {
        ForEach ($key In ($lngStrings['common'].Keys | Sort-Object))
        {
            [string]$value = $lngStrings['common'][$key]
            If ($value -eq '') { $value = "''" }
            [string]$lang = ('$script:lang[' + "'{0}'] = {1}" -f $key, $value)
            Out-File -FilePath $outPath -InputObject $lang                                                             -Encoding utf8 -Append
        }

        $checkName = $checkName.TrimEnd('-skip')
        ForEach ($key In ($lngStrings[$checkName].Keys | Sort-Object))
        {
            [string]$value = $lngStrings[$checkName][$key]
            If ($value -eq '') { $value = "''" }
            [string]$lang = ('$script:lang[' + "'{0}'] = {1}" -f $key, $value)
            Out-File -FilePath $outPath -InputObject $lang                                                             -Encoding utf8 -Append
        }
    }
    Catch { }

    # Add the check itself
    Out-File -FilePath $outPath -InputObject (Get-Content -Path ($qa.FullName))                                        -Encoding utf8 -Append

    # Generate the help text for from each check (taken from the header information)
    # ALSO, add any required additional script functions
    [string]  $xmlHelp    = "<xml>"
    [string[]]$keyWords   = @('DESCRIPTION', 'PASS', 'WARNING', 'FAIL', 'MANUAL', 'NA', 'APPLIES', 'REQUIRED-FUNCTIONS')
    [string[]]$getContent = (Get-Content -Path ($qa.FullName))
    ForEach ($keyWord In $KeyWords)
    {
        # Code from Reddit user "sgtoj"
        $regEx = [RegEx]::Match($getContent, "$($keyWord):((?:.|\s)+?)(?:(?:[A-Z\- ]+:)|(?:#>))")
        $sectionValue = $regEx.Groups[1].Value.Replace("`r`n", ' ').Replace('  ', '').Trim()

        If ([string]::IsNullOrEmpty($sectionValue) -eq $false)
        {
            # Add any required additional script functions
            If ($keyWord -eq 'REQUIRED-FUNCTIONS') {
                ForEach ($function In ($sectionValue).Split(',')) {
                    Out-File -FilePath $outPath -InputObject (Get-Content "$path\functions\$($function.Trim()).ps1")   -Encoding utf8 -Append
                }
            }
            Else
            {
                $keyWord  = $keyWord.ToLower()
                $xmlHelp += "<$keyWord>$sectionValue</$keyWord>"
            }
        }
    }
    $xmlHelp  += "</xml>"
    $checkName = $checkName.TrimEnd('-skip')
    $qaHelp.AppendLine('$script:qahelp[' + "'$checkName']='$xmlHelp'") | Out-Null

    # Complete this check
    Out-File -FilePath $outPath -InputObject '}'                                                                       -Encoding utf8 -Append
    Out-File -FilePath $outPath -InputObject ''                                                                        -Encoding utf8 -Append; Write-Host '▀' -NoNewline -ForegroundColor Green
}
Out-File -FilePath $outPath -InputObject (''.PadLeft(190, '#'))                                                        -Encoding utf8 -Append

# Write out the EN-GB help file
Out-File -FilePath "$path\i18n\en-gb_help.ps1" -InputObject ($qaHelp.ToString()) -Force                                -Encoding utf8;         Write-Host '▀' -NoNewline -ForegroundColor Cyan

[string]$language = ($iniSettings['settings']['language'])
If (($language -eq '') -or ((Test-Path -Path "$path\i18n\$language.ini") -eq $false)) { $language = 'en-gb' }
Out-File -FilePath $outPath -InputObject (Get-Content ("$path\i18n\$language" + "_help.ps1"))                          -Encoding utf8 -Append; Write-Host '▀' -NoNewline -ForegroundColor Cyan
Out-File -FilePath $outPath -InputObject (''.PadLeft(190, '#'))                                                        -Encoding utf8 -Append
Try
{
    ForEach ($key In ($lngStrings['engine'].Keys | Sort-Object))
    {
        [string]$value = $lngStrings['engine'][$key]
        If ($value -eq '') { $value = "''" }
        [string]$lang = ('$script:lang[' + "'{0}'] = {1}" -f $key, $value)
        Out-File -FilePath $outPath -InputObject $lang                                                                 -Encoding utf8 -Append
    }
}
Catch { }
Out-File -FilePath $outPath -InputObject (''.PadLeft(190, '#'))                                                        -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('[string]$reportCompanyName = "' + ($iniSettings['settings']['reportCompanyName']) + '"') -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject ('[string]$script:qaOutput   = "' + ($iniSettings['settings']['outputLocation'])    + '"') -Encoding utf8 -Append
Out-File -FilePath $outPath -InputObject (Get-Content ($path + '\engine\main.ps1'))                                    -Encoding utf8 -Append; Write-Host '▀' -NoNewline -ForegroundColor Cyan
Write-Host ''

###################################################################################################
# FINISH                                                                                          #
###################################################################################################

Write-Host (DivLine -Width $ws) -ForegroundColor Yellow
Write-Colr '  Execute ',$(Split-Path -Leaf $outPath),' for command line help' -Colour White, Yellow, White
Remove-Variable version, date, path, outpath -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ''
