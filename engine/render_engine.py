import os
import sys
import json
import asyncio
import argparse
import subprocess
import requests
import re

def log(msg):
    print(f"[RENDER_ENGINE] {msg}", flush=True)

class GitHubReleaseClient:
    def __init__(self, repo, token):
        self.repo = repo
        self.token = token
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        }

    def get_release_by_tag(self, tag):
        url = f"https://api.github.com/repos/{self.repo}/releases/tags/{tag}"
        resp = requests.get(url, headers=self.headers)
        if resp.status_code != 200:
            raise Exception(f"Failed to find release for tag {tag}: {resp.status_code} - {resp.text}")
        return resp.json()

    def download_asset(self, asset, dest_path):
        url = asset["url"]
        headers = {**self.headers, "Accept": "application/octet-stream"}
        log(f"Downloading {asset['name']} to {dest_path}...")
        with requests.get(url, headers=headers, stream=True) as r:
            r.raise_for_status()
            with open(dest_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
        log(f"Downloaded {asset['name']} successfully ({os.path.getsize(dest_path)} bytes).")

    def upload_asset(self, release_id, file_path, asset_name):
        upload_url = f"https://uploads.github.com/repos/{self.repo}/releases/{release_id}/assets?name={asset_name}"
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/octet-stream",
            "X-GitHub-Api-Version": "2022-11-28"
        }
        log(f"Uploading {asset_name} to release {release_id}...")
        with open(file_path, "rb") as f:
            resp = requests.post(upload_url, headers=headers, data=f)
        if resp.status_code not in (200, 201):
            log(f"Upload asset warning: {resp.status_code} - {resp.text}")
        else:
            log(f"Uploaded {asset_name} successfully!")

def generate_script_with_gemini(topic, gemini_api_key):
    log(f"Generating script for topic: '{topic}' using Gemini...")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={gemini_api_key}"
    payload = {
        "contents": [{
            "parts": [{
                "text": (
                    f"Buatkan naskah video pendek (YouTube Shorts / Facebook Reels) berdurasi 30-45 detik "
                    f"mengenai topik berikut:\n\"{topic}\"\n\n"
                    "Aturan Penting:\n"
                    "1. Gunakan Bahasa Indonesia yang santai, menarik, dan punya hook kuat di 3 detik pertama.\n"
                    "2. JANGAN sertakan instruksi visual, tanda kurung, intro 'Halo teman-teman', atau emoji.\n"
                    "3. Hanya tuliskan kata-kata yang akan diucapkan oleh narator secara langsung (voiceover only).\n"
                    "4. Maksimal 60-80 kata."
                )
            }]
        }]
    }
    resp = requests.post(url, json=payload, headers={"Content-Type": "application/json"})
    if resp.status_code != 200:
        log(f"Gemini API error ({resp.status_code}): {resp.text}. Falling back to topic directly.")
        return topic

    data = resp.json()
    try:
        script = data["candidates"][0]["content"]["parts"][0]["text"].strip()
        log(f"Generated script:\n{script}")
        return script
    except Exception as e:
        log(f"Error parsing Gemini response: {e}. Falling back to topic.")
        return topic

async def generate_speech_and_subtitles(text, voice, audio_path, ass_path):
    import edge_tts
    log(f"Generating voiceover with voice: {voice}...")
    communicate = edge_tts.Communicate(text, voice)
    
    words_data = []
    with open(audio_path, "wb") as f_audio:
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                f_audio.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                # Offset and duration are in 100-nanosecond units (1s = 10,000,000 units)
                start_ms = chunk["offset"] / 10000
                duration_ms = chunk["duration"] / 10000
                end_ms = start_ms + duration_ms
                word = chunk["text"]
                words_data.append({
                    "word": word,
                    "start": start_ms,
                    "end": end_ms,
                    "duration": duration_ms
                })

    log(f"Voiceover saved to {audio_path}. Total words: {len(words_data)}")
    create_karaoke_ass(words_data, ass_path)

def format_ass_time(ms):
    hours = int(ms // 3600000)
    mins = int((ms % 3600000) // 60000)
    secs = int((ms % 60000) // 1000)
    centis = int((ms % 1000) // 10)
    return f"{hours}:{mins:02d}:{secs:02d}.{centis:02d}"

def create_karaoke_ass(words, ass_path):
    log("Creating dynamic karaoke subtitles (.ass)...")
    header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: ShortsStyle,Arial,72,&H00FFFFFF,&H0000FFFF,&H00000000,&H90000000,1,0,0,0,100,100,0,0,1,5.0,2.0,2,40,40,540,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Group words into 3-word chunks for punchy Shorts-style subtitles
    chunk_size = 3
    dialogues = []
    for i in range(0, len(words), chunk_size):
        chunk = words[i:i + chunk_size]
        if not chunk:
            continue
        line_start_ms = chunk[0]["start"]
        line_end_ms = chunk[-1]["end"] + 150 # slight hang time
        
        start_str = format_ass_time(line_start_ms)
        end_str = format_ass_time(line_end_ms)
        
        # Build karaoke text: {\k<centiseconds>}word
        karaoke_text = ""
        current_time = line_start_ms
        for w in chunk:
            # gap before word
            gap_cs = max(0, int((w["start"] - current_time) / 10))
            if gap_cs > 0:
                karaoke_text += f"{{\\k{gap_cs}}}"
            duration_cs = max(1, int(w["duration"] / 10))
            karaoke_text += f"{{\\k{duration_cs}}}{w['word']} "
            current_time = w["end"]
            
        dialogues.append(f"Dialogue: 0,{start_str},{end_str},ShortsStyle,,0,0,0,,{karaoke_text.strip()}")

    with open(ass_path, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(dialogues) + "\n")
    log(f"Subtitles created at {ass_path}")

def get_audio_duration(audio_path):
    cmd = [
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio_path
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return float(res.stdout.strip())

def assemble_video(media_path, audio_path, ass_path, output_path):
    log("Assembling final 9:16 video with FFmpeg...")
    duration = get_audio_duration(audio_path) + 0.6
    log(f"Target duration: {duration:.2f} seconds")

    ext = os.path.splitext(media_path)[1].lower()
    is_image = ext in [".jpg", ".jpeg", ".png", ".webp"]

    # Escape subtitle path for FFmpeg subtitles filter
    # On linux runners, escape colon and special characters
    escaped_ass = ass_path.replace(":", "\\:").replace("'", "\\'")

    if is_image:
        log("Processing image with vertical scaling & subtle Ken Burns effect...")
        # Zoompan filter for subtle dynamic motion on static images
        filter_complex = (
            f"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,"
            f"zoompan=z='min(zoom+0.0008,1.15)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1080x1920:fps=30,"
            f"subtitles='{escaped_ass}'[v]"
        )
        cmd = [
            "ffmpeg", "-y",
            "-loop", "1", "-i", media_path,
            "-i", audio_path,
            "-filter_complex", filter_complex,
            "-map", "[v]",
            "-map", "1:a",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration),
            output_path
        ]
    else:
        log("Processing video with 9:16 vertical crop & loop if needed...")
        filter_complex = (
            f"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,"
            f"subtitles='{escaped_ass}'[v]"
        )
        cmd = [
            "ffmpeg", "-y",
            "-stream_loop", "-1", "-i", media_path,
            "-i", audio_path,
            "-filter_complex", filter_complex,
            "-map", "[v]",
            "-map", "1:a",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration),
            output_path
        ]

    log(f"Running command: {' '.join(cmd)}")
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise Exception(f"FFmpeg error: {result.stderr}")
    log(f"Final video rendered successfully: {output_path} ({os.path.getsize(output_path)} bytes)")

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--job-id", required=True, help="GitHub Release tag/job identifier")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    args = parser.parse_args()

    job_id = args.job_id
    repo = args.repo
    token = args.token

    if not repo or not token:
        raise Exception("Missing GITHUB_REPOSITORY or GITHUB_TOKEN environment variables / arguments.")

    client = GitHubReleaseClient(repo, token)
    work_dir = os.path.join(os.getcwd(), f"work_{job_id}")
    os.makedirs(work_dir, exist_ok=True)

    log(f"Starting job: {job_id} for repo: {repo}")

    try:
        release = client.get_release_by_tag(job_id)
        release_id = release["id"]
        assets = release.get("assets", [])

        # Find config.json and media file
        config_asset = None
        media_asset = None
        for a in assets:
            name = a["name"].lower()
            if name == "config.json":
                config_asset = a
            elif any(name.endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".mkv"]):
                media_asset = a

        if not config_asset:
            raise Exception("No 'config.json' found in release assets.")
        if not media_asset:
            raise Exception("No media file (image/video) found in release assets.")

        config_path = os.path.join(work_dir, "config.json")
        media_path = os.path.join(work_dir, media_asset["name"])
        client.download_asset(config_asset, config_path)
        client.download_asset(media_asset, media_path)

        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)

        voice = config.get("voice", "id-ID-GadisNeural")
        script = config.get("script", "").strip()
        topic = config.get("topic", "").strip()
        gemini_api_key = config.get("gemini_api_key") or os.environ.get("GEMINI_API_KEY", "")

        # If user didn't write script directly but provided topic + Gemini key
        if not script and topic:
            if gemini_api_key:
                script = generate_script_with_gemini(topic, gemini_api_key)
            else:
                script = topic
        elif not script and not topic:
            script = "Selamat datang di konten video singkat ini. Jangan lupa like dan subscribe!"

        audio_path = os.path.join(work_dir, "narration.mp3")
        ass_path = os.path.join(work_dir, "subtitles.ass")
        output_path = os.path.join(work_dir, "output_shorts.mp4")

        # 1. Generate Voice & Subtitles
        await generate_speech_and_subtitles(script, voice, audio_path, ass_path)

        # 2. Assemble Video
        assemble_video(media_path, audio_path, ass_path, output_path)

        # 3. Upload Result to GitHub Release
        client.upload_asset(release_id, output_path, "output_shorts.mp4")
        log(f"Job {job_id} COMPLETED successfully!")

    except Exception as e:
        log(f"Job {job_id} FAILED with error: {e}")
        err_file = os.path.join(work_dir, "error.txt")
        with open(err_file, "w", encoding="utf-8") as ef:
            ef.write(str(e))
        if 'release_id' in locals():
            client.upload_asset(release_id, err_file, "error.txt")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
