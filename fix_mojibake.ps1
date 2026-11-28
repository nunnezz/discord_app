$f = "c:\Users\nunes\Downloads\projetos\discord_app\lib\voice\voice_call_screen.dart"
$code = @'
using System;
using System.Collections.Generic;
public class MojibakeMap {
  public static Dictionary<string,string> Pairs() {
    var d = new Dictionary<string,string>();
    d["\u00C3\u00A9"] = "\u00E9";   // e acute
    d["\u00C3\u00B3"] = "\u00F3";   // o acute
    d["\u00C3\u00AD"] = "\u00ED";   // i acute
    d["\u00C3\u00A1"] = "\u00E1";   // a acute
    d["\u00C3\u00BA"] = "\u00FA";   // u acute
    d["\u00C3\u00A3"] = "\u00E3";   // a tilde
    d["\u00C3\u00A7"] = "\u00E7";   // c cedilla
    d["\u00C3\u00AA"] = "\u00EA";   // e circumflex
    d["\u00C3\u00B4"] = "\u00F4";   // o circumflex
    d["\u00C3\u00B5"] = "\u00F5";   // o tilde
    d["\u00C3\u00A0"] = "\u00E0";   // a grave (C3 A0)
    d["\u00C3\u00A2"] = "\u00E2";   // a circumflex
    d["\u00C3\u009A"] = "\u00DA";   // U acute
    d["\u00C3\u0087"] = "\u00C7";   // C cedilla
    d["\u00C3\u0089"] = "\u00C9";   // E acute
    d["\u00C3\u0093"] = "\u00D3";   // O acute
    d["\u00C3\u0081"] = "\u00C1";   // A acute
    d["\u00C3\u0094"] = "\u00D4";   // O circumflex
    d["\u00C3\u0095"] = "\u00D5";   // O tilde
    d["\u00C3\u0083"] = "\u00C3";   // A tilde
    d["\u00C3\u00BC"] = "\u00FC";   // u diaeresis
    d["\u00C3\u009C"] = "\u00DC";   // U diaeresis
    d["\u00E2\u20AC\u201D"] = "\u2014"; // em dash
    d["\u00E2\u20AC\u201C"] = "\u2013"; // en dash
    return d;
  }
  public static string Fix(string s) {
    foreach (var kv in Pairs()) { s = s.Replace(kv.Key, kv.Value); }
    return s;
  }
}
'@
Add-Type -TypeDefinition $code
$text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
$fixed = [MojibakeMap]::Fix($text)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($f, $fixed, $utf8NoBom)
Write-Output "OK"
