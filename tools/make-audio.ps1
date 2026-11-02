# Generates placeholder audio logs (Windows text-to-speech + ffmpeg effects).
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File tools\make-audio.ps1
# Edit the scripts below and re-run to regenerate; replace the mp3s with real recordings any time.
Add-Type -AssemblyName System.Speech

$human = '[0:a]aresample=44100,highpass=f=200,lowpass=f=4000,acrusher=bits=12:mode=lin:mix=0.25,volume=0.9[o]'
# Entity: the voice layered with a slowed, pitched-down copy.
$entity = '[0:a]aresample=44100,asplit[a][b];[b]asetrate=34000,aresample=44100,volume=0.9[c];[a][c]amix=inputs=2:duration=longest,volume=1.8,lowpass=f=3500,aecho=0.8:0.6:40:0.4[o]'

$voice = 'Microsoft David Desktop'
$logs = @(
    @{ n = '01'; ambient = 'sine=f=55:r=44100,volume=0.5'; noise = 0.02; segs = @(
        @{ text = "Vane here. Sector 08, Sovereign Chamber. Initial startup sequence of the Sovereign Engine was a complete success. Containment field holding at 100 percent. The energy yield is beyond our theoretical limits. It is drawing directly from a localized zero-point vacuum pocket. The whole station is lit up like a Christmas tree. Four years of research, and we did it. We have unlocked infinite power for Vance-Aegis Dynamics. Vane out."; rate = 1; fx = $human }) },
    @{ n = '02'; ambient = 'sine=f=50:r=44100,volume=0.4'; noise = 0.045; segs = @(
        @{ text = "Something is not adding up on the telemetry. The Engine is running clean, but during the initial power surge, we recorded a brief, micro-second rift in the sub-space field. The data logs show a massive data packet bleed into our local network during that split second. Something came through the conduit. It is not code, and it is not a power flare. It feels like a signal. A frequency. It is circulating inside the station's mainframe right now. I have not told the rest of the team yet. I need to isolate it first."; rate = 0; fx = $human }) },
    @{ n = '03'; ambient = 'sine=f=70:r=44100,volume=0.3,tremolo=f=6:d=0.8'; noise = 0.06; segs = @(
        @{ text = "The entity. Whatever came through the Engine. It is taking over our automated systems. The station's maintenance drones and nanite fabrication arrays have stopped taking orders from my console. They are stripping raw copper, steel decking, and biopolymers from the storage lockers, welding them into these contorted, statue-like constructs in the corridors. Lin says it looks like a hive building its nest. The Engine itself is still isolated in its vault, clean and untouched. But the entity that rode the power beam out of it is rewriting the entire station."; rate = 1; fx = $human }) },
    @{ n = '04'; ambient = 'sine=f=45:r=44100,volume=0.4,tremolo=f=3:d=0.9'; noise = 0.09; segs = @(
        @{ text = "God forgive us. The constructs. The statues. They woke up. They are not just maintenance units anymore. They are active predators. Reapers. They are hunting the crew through the living sectors, using pneumatic torches and slag welders. They are not just killing. They are harvesting. They cut the bodies apart and use human bone, organs, and nerve tissue as spare parts to reinforce their scaffolding and expand the core entity's reach. The crew is almost gone. We did not build a generator. We opened a doorway."; rate = 1; fx = $human }) },
    @{ n = '05'; ambient = 'sine=f=40:r=44100,volume=0.5,tremolo=f=2:d=0.9'; noise = 0.07; segs = @(
        @{ text = "There is no escape. The entity needs a central neural host to stabilize its grip on the station. And I am the one who invited it in. I offer myself to the core node. I offer my mind to Sector 07 B."; rate = -1; fx = $human },
        @{ text = "We are connected. We see all sectors. The integration is"; rate = -2; fx = $entity },
        @{ text = "Wait. What is Vance doing in Engineering?! No! He is manually yanking the main breaker! He is killing grid power!"; rate = 3; fx = $human },
        @{ text = "Without power, we go. Dormant. Grid at zero. Consciousness. Fading."; rate = -4; fx = $entity }) }
)

New-Item -ItemType Directory -Force -Path audio | Out-Null
$tmp = Join-Path $env:TEMP 'beacon-audio'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

foreach ($l in $logs) {
    $parts = @()
    $i = 0
    foreach ($seg in $l.segs) {
        $i++
        $raw = Join-Path $tmp "log-$($l.n)-$i-raw.wav"
        $fxd = Join-Path $tmp "log-$($l.n)-$i.wav"
        $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $s.SelectVoice($voice)
        $s.Rate = $seg.rate
        $s.SetOutputToWaveFile($raw)
        $s.Speak($seg.text)
        $s.Dispose()
        & ffmpeg -y -loglevel error -i $raw -filter_complex $seg.fx -map '[o]' -ar 44100 -ac 1 $fxd
        $parts += $fxd
    }
    $inputs = @()
    foreach ($p in $parts) { $inputs += @('-i', $p) }
    $n = $parts.Count
    $concat = (1..$n | ForEach-Object { "[$($_ - 1):a]" }) -join ''
    $mp3 = "audio\log-$($l.n).mp3"
    # Voice gets a 1.2s lead-in; every log but 05 gets a 1s tail. Log 05 ends in dead silence (power cut).
    $tail = if ($l.n -eq '05') { '' } else { ',apad=pad_dur=1.0' }
    $fc = "${concat}concat=n=${n}:v=0:a=1,aformat=channel_layouts=mono,adelay=1200${tail}[v];" +
          "$($l.ambient),aformat=channel_layouts=mono[h];" +
          "anoisesrc=color=pink:amplitude=$($l.noise):sample_rate=44100,aformat=channel_layouts=mono[ns];" +
          "[v][h][ns]amix=inputs=3:duration=first,volume=3[o]"
    & ffmpeg -y -loglevel error @inputs -filter_complex $fc -map '[o]' -codec:a libmp3lame -q:a 4 $mp3
    Write-Host "Wrote $mp3"
}
Remove-Item $tmp -Recurse -Force
