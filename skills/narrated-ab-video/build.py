#!/usr/bin/env python3
"""Assemble a narrated video from cards and recorded clips.

Usage: build.py <plan.json> [--voice Samantha] [--rate 182] [--eleven VOICE_ID]
--eleven uses ElevenLabs (key in ELEVENLABS_API_KEY, model eleven_multilingual_v2) instead of macOS say.
plan.json: {"out": "demo.mp4", "work": "/tmp/x", "segments": [
  {"card": "cards/title.png", "say": "narration"},
  {"clip": "raw/a-run", "banner": "cards/banner-A.png", "say": "narration", "speed": 10}
  {"clip": "raw/a-run", "spans": [[6, 12, 1], [12, 55, 8]], "say": "..."}   explicit slices (seconds, speed)
]}
Paths are relative to the plan file. A clip dir holds the recorder's *.webm and marks.json; the span
between each "sent" and "replied" mark is sped up by `speed` (model waits), and the last frame is
held until the narration ends. Writes audio files only; it never plays anything.
"""
import argparse, glob, json, os, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("plan"); ap.add_argument("--voice", default="Samantha"); ap.add_argument("--rate", default="182")
ap.add_argument("--eleven", help="ElevenLabs voice id; key from ELEVENLABS_API_KEY")
a = ap.parse_args()
base = os.path.dirname(os.path.abspath(a.plan)); plan = json.load(open(a.plan))
rel = lambda p: p if os.path.isabs(p) else os.path.join(base, p)
seg = os.path.join(rel(plan.get("work", "work")), "seg"); os.makedirs(seg, exist_ok=True)
ENC = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-ar", "44100", "-ac", "2"]

def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode: sys.exit(f"FAILED: {' '.join(cmd)[:200]}\n{r.stderr[-1500:]}")
def dur(f): return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f]).strip())
def voice(i, text):
    if a.eleven:
        import hashlib, urllib.request
        f = f"{seg}/{i:02d}-{hashlib.sha1((a.eleven + text).encode()).hexdigest()[:10]}.mp3"
        if not os.path.exists(f):  # cached: reruns don't spend characters again
            req = urllib.request.Request(f"https://api.elevenlabs.io/v1/text-to-speech/{a.eleven}?output_format=mp3_44100_128",
                data=json.dumps({"text": text, "model_id": "eleven_multilingual_v2"}).encode(), method="POST",
                headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=120) as r: open(f, "wb").write(r.read())
        return f, dur(f)
    f = f"{seg}/{i:02d}.aiff"; run("say", "-v", a.voice, "-r", a.rate, "-o", f, text); return f, dur(f)

for i, s in enumerate(plan["segments"]):
    out = f"{seg}/{i:02d}.mp4"; aud, d = voice(i, s["say"])
    if "card" in s:
        t = d + s.get("pad", 0.8)
        run("ffmpeg", "-y", "-loop", "1", "-t", f"{t:.2f}", "-i", rel(s["card"]), "-i", aud, "-filter_complex", "[1:a]apad[a]",
            "-map", "0:v", "-map", "[a]", "-t", f"{t:.2f}", *ENC, out)
    else:
        d_ = rel(s["clip"]); raw = glob.glob(f"{d_}/*.webm")[0]; marks = json.load(open(f"{d_}/marks.json"))["marks"]
        end, sp = dur(raw), s.get("speed", 10); parts, t = [], s.get("start", 0.0)
        if "spans" in s:  # explicit [[from, to, speed], ...] slices of one clip
            parts = [(x, min(y, end), k) for x, y, k in s["spans"]]
        else:
            for m in marks:
                if m["label"] == "sent": parts.append((t, m["t"] + 1.5, 1)); t = m["t"] + 1.5
                if m["label"] == "replied": parts.append((t, m["t"] - 0.5, sp)); t = m["t"] - 0.5
            parts.append((t, end, 1))
        f = [f"[0:v]trim={x:.2f}:{y:.2f},setpts=(PTS-STARTPTS)/{k}[v{n}]" for n, (x, y, k) in enumerate(parts)]
        f.append("".join(f"[v{n}]" for n in range(len(parts))) + f"concat=n={len(parts)}:v=1:a=0[c]")
        vlen = sum((y - x) / k for x, y, k in parts); total = max(vlen, d + 0.8)
        inputs = ["-i", raw]
        if s.get("banner"):
            inputs += ["-i", rel(s["banner"])]
            f.append(f"[c]tpad=stop_mode=clone:stop_duration={total - vlen + 0.1:.2f}[cp];[cp][1:v]overlay=0:0[v];[2:a]apad[a]")
        else:
            f.append(f"[c]tpad=stop_mode=clone:stop_duration={total - vlen + 0.1:.2f}[v];[1:a]apad[a]")
        run("ffmpeg", "-y", *inputs, "-i", aud, "-filter_complex", ";".join(f), "-map", "[v]", "-map", "[a]", "-t", f"{total:.2f}", *ENC, out)
    print(f"seg {i:02d} {dur(out):6.1f}s  {s.get('card') or s.get('clip')}", flush=True)

lst = f"{seg}/list.txt"; open(lst, "w").write("".join(f"file '{i:02d}.mp4'\n" for i in range(len(plan["segments"]))))
out = rel(plan.get("out", "demo.mp4")); run("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", out)
print(f"{out}  {dur(out):.1f}s")
