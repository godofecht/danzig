# danzig-gain-standalone

A command-line WAV gain processor built on the danzig DSP core.

## What it demonstrates

danzig's audio code has no dependency on VST3. This example uses it offline,
with no host and no plugin bundle, which makes it the fastest way to check that
a change to the DSP does what you meant.

It reads a WAV header as an `extern struct`, validates the format, reads the
samples into one allocation, applies `danzig.dBToLinear(gain_db)` across the
buffer, and writes the result with the original header.

The WAV header is worth a look if you have not laid one out in Zig before:

```zig
const WavHeader = extern struct {
    riff: [4]u8 = "RIFF".*,
    size: u32,
    wave: [4]u8 = "WAVE".*,
    fmt: [4]u8 = "fmt ".*,
    fmt_size: u32 = 16,
    format: u16 = 1,
    channels: u16,
    ...
};
```

`extern struct` gives C layout, so `std.mem.asBytes(&header)` is the 44 bytes on
disk with no manual packing.

## Build

From the repository root:

```bash
zig build
```

## Run

```bash
./zig-out/bin/danzig-gain-standalone <input.wav> <output.wav> <gain_db>
```

With no arguments it prints usage:

```bash
zig build run-standalone
```

```
Usage: danzig-gain-standalone <input.wav> <output.wav> <gain_db>
Example: danzig-gain-standalone input.wav output.wav 6.0
```

## A worked example

Make a 1 second, 440 Hz sine at half scale. 32-bit float PCM is the only format
this tool reads.

```bash
python3 - <<'PY'
import struct, math
sr, n, ch = 48000, 48000, 1
data = b''.join(struct.pack('<f', 0.5 * math.sin(2 * math.pi * 440 * i / sr)) for i in range(n))
hdr = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(data), b'WAVE', b'fmt ',
                  16, 1, ch, sr, sr * ch * 4, ch * 4, 32, b'data', len(data))
open('sine.wav', 'wb').write(hdr + data)
PY
```

Apply +6 dB:

```bash
./zig-out/bin/danzig-gain-standalone sine.wav sine-6db.wav 6.0
```

```
Processing audio:
  Channels: 1
  Sample rate: 48000 Hz
  Samples: 48000
  Duration: 1.00 seconds
  Gain: 6.0 dB

✓ Successfully processed and saved to: sine-6db.wav
```

Check the peaks moved by the right amount. +6 dB is a factor of 1.9953, so 0.5
should become 0.9976:

```bash
python3 - <<'PY'
import struct
def peak(p):
    return max(abs(v) for (v,) in struct.iter_unpack('<f', open(p, 'rb').read()[44:]))
print('in  peak', round(peak('sine.wav'), 4))
print('out peak', round(peak('sine-6db.wav'), 4))
PY
```

```
in  peak 0.5
out peak 0.9976
```

## Limits

- 32-bit float PCM WAV only, with a canonical 44-byte header. Anything else
  gives `Only 32-bit float PCM WAV files are supported`.
- Gain is clamped to -48 to +48 dB. Outside that it returns `InvalidGain`.
- The whole file is read into memory at once.
- The gain is applied flat rather than ramped, since there is no parameter
  moving during an offline render.

---

See [docs/WIKI.md](../../docs/WIKI.md) for the audio helpers.
