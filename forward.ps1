# OAK himoya e'lonlari kanalidan (@dissertatsiya_himoyasi_elonlari) Ped.43.02 kengashi
# e'lonlarini E'LONLAR guruhiga yuboradi (to'liq matn + manba havolasi).
# GitHub Actions'da ishlaydi: BOT_TOKEN va CHAT_ID - repo secrets. Holat: state.json (repoga commit qilinadi).
#   -DryRun : hech narsa yubormaydi
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Source    = 'dissertatsiya_himoyasi_elonlari'
$Filters   = @('Ped.43.02', 'Buxoro xalqaro')       # ikkalasi ham bo'lishi shart
$StateFile = Join-Path $PSScriptRoot 'state.json'
$LogFile   = Join-Path $PSScriptRoot 'forward.log'
$token     = $env:BOT_TOKEN
$chat      = $env:CHAT_ID

function Write-Log($msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} UTC  {1}' -f (Get-Date).ToUniversalTime(), $msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Output $line
}

function Get-Posts($url) {
    $html = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 60).Content
    $rx = 'data-post="' + $Source + '/(\d+)"[\s\S]*?class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)</div>'
    foreach ($m in [regex]::Matches($html, $rx)) {
        $text = $m.Groups[2].Value -replace '<br\s*/?>', "`n" -replace '<[^>]+>', ''
        [pscustomobject]@{ Id = [int]$m.Groups[1].Value; Text = [Net.WebUtility]::HtmlDecode($text) }
    }
}

try {
    if (-not $DryRun -and (-not $token -or -not $chat)) { throw 'BOT_TOKEN yoki CHAT_ID berilmagan' }
    if (-not $DryRun) {   # token va guruh to'g'riligini tekshirish (hech narsa yubormaydi)
        $g = Invoke-RestMethod "https://api.telegram.org/bot$token/getChat?chat_id=$chat"
        Write-Output "Guruh: $($g.result.title)"
    }
    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $sent  = @($state.sent)

    # Qidiruv natijasi + oxirgi postlar lentasi (qidiruv indeksi kechiksa ham tushib qolmasin)
    $posts = @(Get-Posts "https://t.me/s/${Source}?q=Ped.43.02") + @(Get-Posts "https://t.me/s/${Source}")
    Write-Output "Topilgan postlar: $($posts.Count)"
    $new = $posts |
        Where-Object { $p = $_; @($Filters | Where-Object { $p.Text -notlike "*$_*" }).Count -eq 0 } |
        Where-Object { $_.Id -gt $state.last_id -and $sent -notcontains $_.Id } |
        Sort-Object Id -Unique

    if (-not $new) { Write-Output 'Yangi e''lon yo''q'; exit 0 }

    foreach ($p in $new) {
        if ($DryRun) { Write-Output "[DRY] $($p.Id)  $($p.Text.Substring(0, [Math]::Min(120, $p.Text.Length)) -replace "`n",' ')"; continue }
        $link = "https://t.me/$Source/$($p.Id)"
        $body = @{
            chat_id = $chat
            text    = $p.Text.Trim() + "`n`n" + [char]::ConvertFromUtf32(0x1F517) + " Manba: $link"
            link_preview_options = @{ is_disabled = $true }
        } | ConvertTo-Json -Depth 3
        $r = Invoke-RestMethod "https://api.telegram.org/bot$token/sendMessage" -Method Post `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
        Write-Log "yuborildi  src=$($p.Id) -> msg=$($r.result.message_id)"
        $sent += $p.Id
        $state.last_id = [Math]::Max([int]$state.last_id, $p.Id)
        $state.sent = @($sent | Select-Object -Last 500)
        $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8
        Start-Sleep -Seconds 2
    }
}
catch {
    Write-Log "XATO: $($_.Exception.Message)"
    exit 1
}
