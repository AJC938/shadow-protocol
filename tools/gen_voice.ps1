# Synthesises raw voice lines with the Windows built-in speech voices.
# Output: tools/voice_raw/<key>.wav (processed into radio voices by gen_audio.py)
# Usage: powershell -NoProfile -File tools/gen_voice.ps1 <project_root>
param([string]$Root)
Add-Type -AssemblyName System.Speech
$spec = Get-Content -Raw -Encoding UTF8 (Join-Path $Root "tools\voice_lines.json") | ConvertFrom-Json
$out = Join-Path $Root "tools\voice_raw"
New-Item -ItemType Directory -Force $out | Out-Null
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voices = $synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }
$female = ($voices | Where-Object { $_ -like "*Zira*" } | Select-Object -First 1)
$male = ($voices | Where-Object { $_ -like "*David*" } | Select-Object -First 1)
foreach ($p in $spec.PSObject.Properties) {
    $key = $p.Name
    $role = $p.Value.role
    $text = [System.Security.SecurityElement]::Escape($p.Value.text)
    $voice = $male
    $rate = "0%"
    $pitch = "0%"
    switch ($role) {
        "oracle" { $voice = $female; $rate = "-6%"; $pitch = "-4%" }
        "ghost"  { $voice = $male; $rate = "-10%"; $pitch = "-12%" }
        "guard"  { $voice = $male; $rate = "+8%"; $pitch = "+4%" }
        "heavy"  { $voice = $male; $rate = "-12%"; $pitch = "-28%" }
    }
    $ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><voice name='$voice'><prosody rate='$rate' pitch='$pitch'>$text</prosody></voice></speak>"
    $synth.SetOutputToWaveFile((Join-Path $out "$key.wav"))
    $synth.SpeakSsml($ssml)
}
$synth.SetOutputToNull()
Write-Output ("voices written: " + $spec.PSObject.Properties.Name.Count)
