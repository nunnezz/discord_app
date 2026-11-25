$cache = "C:\Users\nunes\AppData\Local\Pub\Cache\hosted\pub.dev"
# (pacote-referência, lista de sub-pacotes a checar)
$targets = @(
  @('agora_rtc_engine', @('agora_rtc_engine-6.6.4','iris_method_channel-2.2.7','iris_platform_interface-2.1.1')),
  @('shared_preferences', @('shared_preferences_windows-2.4.1','shared_preferences_web-2.4.3','shared_preferences_android-2.5.5','shared_preferences_linux-2.4.1')),
  @('image_picker', @('image_picker_android-0.8.13+25','image_picker_ios-0.8.13+7','image_picker_for_web-3.1.1','image_picker_windows-0.2.2')),
  @('video_player', @('video_player_android-2.13.0','video_player_web-2.4.0')),
  @('url_launcher', @('url_launcher_windows-3.1.6','url_launcher_web-2.4.3','url_launcher_android-6.3.35','url_launcher_linux-3.2.3')),
  @('path_provider', @('path_provider_windows-2.3.0','path_provider_android-2.3.1','path_provider_linux-2.2.2')),
  @('supabase_flutter', @('realtime_client-2.13.2','gotrue-2.27.3','storage_client-2.8.1')),
  @('app_links', @('app_links-7.2.2')),
  @('flutter_dotenv', @('flutter_dotenv-5.2.1'))
)
foreach ($t in $targets) {
  Write-Output "=== $($t[0]) ==="
  foreach ($d in $t[1]) {
    $yaml = Join-Path $cache "$d\pubspec.yaml"
    if (-not (Test-Path $yaml)) { Write-Output "  $d : (ausente)"; continue }
    # Pega as linhas sob "platforms:" dentro do bloco plugin (procura nomes de SO)
    $names = (Select-String -Path $yaml -Pattern "^\s+(android|ios|web|windows|macos|linux):" | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -Unique
    Write-Output "  $d : $($names -join ', ')"
  }
}
