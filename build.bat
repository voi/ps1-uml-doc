@powershell -NoProfile -ExecutionPolicy Unrestricted "$s = [scriptblock]::create((gc \"%~f0\" | ? { $_ -notmatch '^@' }) -join \"`n\"); & $s" %* &goto :eof

## ps1
$lines  = Get-Content -Path 'LICENSE.txt' | % { '@rem {0}' -f $_ }
$lines += ''
$lines += Get-Content -Path 'build.bat' | ? { $_ -match '^@' }
$lines += ''
$lines += Get-Content -Path 'uml_sequence.ps1'

$lines | Set-Content 'uml_sequence.bat'
