$content = Get-Content '.\modules\core\Core.Rest.psm1'
$first = $content | Select-Object -First 364
$last = $content | Select-Object -Skip 402
$combined = $first + $last
$combined | Set-Content '.\modules\core\Core.Rest.psm1' -Encoding UTF8