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
    
    # 1. Dynamically discover all supported models for this key
    candidate_models = []
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models?key={gemini_api_key}"
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            for m in data.get("models", []):
                methods = m.get("supportedGenerationMethods", [])
                if "generateContent" in methods:
                    name = m.get("name", "")
                    clean_name = name.replace("models/", "")
                    if clean_name:
                        candidate_models.append(clean_name)
    except Exception as e:
        log(f"Dynamic Gemini model discovery warning: {e}")

    def model_score(name):
        s = 0
        if "flash" in name: s += 100
        if "3." in name: s += 60
        if "2.5" in name: s += 50
        if "2.0" in name: s += 30
        if "1.5" in name: s += 20
        if "pro" in name: s += 10
        if "exp" in name: s -= 5
        return s

    candidate_models.sort(key=model_score, reverse=True)

    fallbacks = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash-exp",
        "gemini-1.5-flash",
        "gemini-1.5-flash-latest",
        "gemini-1.5-pro",
        "gemini-pro"
    ]
    for fb in fallbacks:
        if fb not in candidate_models:
            candidate_models.append(fb)

    log(f"Discovered candidate Gemini models: {candidate_models[:6]}")

    prompt = (
        f"Buatkan naskah video pendek (YouTube Shorts / TikTok / Reels) berdurasi 45-60 detik mengenai topik berikut:\n"
        f"\"{topic}\"\n\n"
        "Aturan Penting Agar Penonton Betah & Lanjut Menonton (High Retention):\n"
        "1. HOOK 3 DETIK PERTAMA: Awali langsung dengan kalimat pembuka yang mengejutkan, paradox, mitos yang dibantah, atau pertanyaan provokatif yang bikin penasaran tinggi sehingga penonton tidak scroll.\n"
        "2. Gunakan Bahasa Indonesia lisan yang santai, lugas, mengalir cepat, dan mendalam.\n"
        "3. Jangan gunakan tanda kurung, instruksi visual, intro klise seperti 'Halo guys', atau emoji.\n"
        "4. Tuliskan HANYA kata-kata yang akan diucapkan narator secara langsung (voiceover only).\n"
        "5. Akhiri dengan pertanyaan reflektif yang memancing penonton berkomentar.\n"
        "6. Panjang naskah 110-140 kata (durasi sekitar 45-60 detik)."
    )
    
    for model in candidate_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={gemini_api_key}"
        payload = {"contents": [{"parts": [{"text": prompt}]}]}
        try:
            resp = requests.post(url, json=payload, headers={"Content-Type": "application/json"}, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                script = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                log(f"Successfully generated script with model {model}:\n{script}")
                return script
            else:
                log(f"Model {model} returned {resp.status_code}: {resp.text[:120]}")
        except Exception as e:
            log(f"Model {model} error: {e}")

    log("Gemini API fallback to topic directly.")
    return topic

async def generate_speech_and_subtitles(text, voice, audio_path, ass_path):
    import edge_tts
    log(f"Generating voiceover with voice: {voice} (calm & natural, rate: -10%)...")
    communicate = edge_tts.Communicate(text, voice, rate="-10%", boundary="WordBoundary")
    
    words_data = []
    with open(audio_path, "wb") as f_audio:
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                f_audio.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                # Offset and duration are in ticks (1 tick = 100ns = 1/10000 ms)
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

    log(f"Voiceover saved to {audio_path}. Total words captured: {len(words_data)}")
    create_karaoke_ass(words_data, ass_path, raw_text=text, audio_path=audio_path)

def format_ass_time(ms):
    hours = int(ms // 3600000)
    mins = int((ms % 3600000) // 60000)
    secs = int((ms % 60000) // 1000)
    centis = int((ms % 1000) // 10)
    return f"{hours}:{mins:02d}:{secs:02d}.{centis:02d}"

def break_chunk_into_lines(chunk_words):
    n = len(chunk_words)
    if n <= 2:
        return [chunk_words]
    elif n == 3:
        l01 = len(chunk_words[0].get("word", "")) + len(chunk_words[1].get("word", ""))
        if l01 <= 14:
            return [chunk_words[0:2], chunk_words[2:3]]
        else:
            return [[chunk_words[0]], chunk_words[1:3]]
    elif n == 4:
        return [chunk_words[0:2], chunk_words[2:4]]
    elif n == 5:
        w2_str = str(chunk_words[2].get("word", "")).strip()
        if any(w2_str.endswith(p) for p in (',', ';', ':')):
            return [chunk_words[0:3], chunk_words[3:5]]
        return [chunk_words[0:2], chunk_words[2:4], chunk_words[4:5]]
    else:  # n >= 6
        return [chunk_words[0:2], chunk_words[2:4], chunk_words[4:]]

def smart_chunk_words(words):
    """
    Intelligently group words into 2-3 line subtitle chunks based on:
    1. Sentence ending punctuation (. ! ? ...) -> Always break to keep sentences separate
    2. Audio pauses (breath/silence >= 260ms) -> Natural speech breaks
    3. Clause punctuation (, ; : —) -> Natural grammatical pauses
    4. Maximum word limits (3 to 6 words per screen)
    """
    if not words:
        return []

    sentence_ends = ('.', '!', '?', '…', '?!', '!?')
    clause_ends = (',', ';', ':', '—', '-')

    chunks = []
    current_chunk = []

    for i, w in enumerate(words):
        current_chunk.append(w)
        raw_word = str(w.get("word", "")).strip()

        is_sentence_end = any(raw_word.endswith(p) for p in sentence_ends)
        is_clause_end = any(raw_word.endswith(p) for p in clause_ends)

        # Detect natural speech pause between words (in milliseconds)
        has_audio_pause = False
        if i + 1 < len(words):
            gap_ms = words[i + 1]["start"] - w["end"]
            if gap_ms >= 260:  # Pause >= 260ms indicates breath or clause transition
                has_audio_pause = True

        chunk_len = len(current_chunk)
        rem_words = len(words) - (i + 1)

        should_break = False

        # 1. Hard break: End of sentence (e.g. "Ingat ini baik-baik.")
        if is_sentence_end:
            should_break = True

        # 2. Audio pause break: Narrator paused for breath between thoughts
        elif has_audio_pause and chunk_len >= 3:
            should_break = True

        # 3. Clause break (comma, colon) if chunk has 3 to 5 words
        elif is_clause_end and 3 <= chunk_len <= 5:
            should_break = True

        # 4. Maximum words limit: Keep screen readable (max 5-6 words per chunk)
        elif chunk_len >= 5:
            if chunk_len == 5 and i + 1 < len(words) and any(str(words[i + 1].get("word", "")).strip().endswith(p) for p in sentence_ends):
                should_break = False
            else:
                should_break = True

        # Guard against leaving an isolated 1-word chunk at the end
        if should_break:
            if rem_words == 1 and not is_sentence_end and chunk_len < 6:
                should_break = False

        if should_break or (i == len(words) - 1):
            chunks.append(current_chunk)
            current_chunk = []

    # Merge isolated 1-word final chunk into preceding chunk if preceding is small
    if len(chunks) > 1 and len(chunks[-1]) == 1 and len(chunks[-2]) <= 4:
        last = chunks.pop()
        chunks[-1].extend(last)

    return chunks

def create_karaoke_ass(words, ass_path, raw_text="", audio_path=""):
    log("Creating dynamic karaoke subtitles (.ass) with Poppins Black (Bottom Safe Zone, 2-3 Lines, Fontsize 70)...")
    
    # Fallback timing if WordBoundary data was empty: distribute words evenly across audio duration
    if not words and raw_text:
        log("No WordBoundary data captured, generating duration-proportional subtitle chunks...")
        raw_words = [w.strip() for w in raw_text.split() if w.strip()]
        total_audio_ms = 45000.0
        if audio_path and os.path.exists(audio_path):
            total_audio_ms = get_audio_duration(audio_path) * 1000.0
        
        word_dur = max(240.0, (total_audio_ms - 500.0) / max(1, len(raw_words)))
        cur_t = 200.0
        words = []
        for rw in raw_words:
            words.append({"word": rw, "start": cur_t, "end": cur_t + word_dur, "duration": word_dur})
            cur_t += word_dur

    header = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: ShortsStyle,Poppins Black,70,&H0000F5FF,&H00FFFFFF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,4.5,2.0,2,75,75,420,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    # Group words intelligently based on sentence punctuation, audio pauses, and 2-3 line layout
    chunks = smart_chunk_words(words)
    log(f"Grouped into {len(chunks)} natural sentence/clause chunks")

    dialogues = []
    for chunk_idx, chunk in enumerate(chunks):
        if not chunk:
            continue
        line_start_ms = chunk[0]["start"]
        if chunk_idx + 1 < len(chunks):
            next_start = chunks[chunk_idx + 1][0]["start"]
            line_end_ms = min(chunk[-1]["end"] + 70, next_start)
        else:
            line_end_ms = chunk[-1]["end"] + 450
        
        start_str = format_ass_time(line_start_ms)
        end_str = format_ass_time(line_end_ms)
        
        lines = break_chunk_into_lines(chunk)
        karaoke_parts = []
        current_time = line_start_ms

        for line_words in lines:
            line_text = ""
            for w in line_words:
                raw_w = re.sub(r'[{}]', '', str(w.get("word", ""))).replace('\\', '/').strip()
                clean_word = raw_w.upper()
                if not clean_word:
                    continue

                gap_cs = max(0, int((w["start"] - current_time) / 10))
                if gap_cs > 0:
                    line_text += f"{{\\k{gap_cs}}}"
                duration_cs = max(1, int(w["duration"] / 10))
                line_text += f"{{\\k{duration_cs}}}{clean_word} "
                current_time = w["end"]

            if line_text.strip():
                karaoke_parts.append(line_text.strip())

        full_karaoke_dialogue = "\\N".join(karaoke_parts)
        if full_karaoke_dialogue.strip():
            dialogues.append(f"Dialogue: 0,{start_str},{end_str},ShortsStyle,,0,0,0,,{full_karaoke_dialogue}")

    with open(ass_path, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(dialogues) + "\n")
    log(f"Subtitles created at {ass_path} (total {len(dialogues)} subtitle chunks, Fontsize: 70, Alignment: Bottom-Center Safe Zone (MarginV: 420), 2-3 lines per chunk)")

def get_audio_duration(audio_path):
    cmd = [
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio_path
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return float(res.stdout.strip())

def generate_blur_mask(mask_path, width=1080, height=1920):
    from PIL import Image
    log("Generating top & bottom cinema blur mask (1080x1920)...")
    img = Image.new("RGB", (width, height), (0, 0, 0))
    pixels = img.load()
    # Top (y < 420): full blur 255
    # Top fade (420 <= y < 560): fade from 255 to 0
    # Center (560 <= y < 1360): pure 0 (sharp clear original video & subtitles)
    # Bottom fade (1360 <= y < 1500): fade from 0 to 255
    # Bottom (y >= 1500): full blur 255
    for y in range(height):
        if y < 420:
            val = 255
        elif y < 560:
            val = int(255 * (1.0 - (y - 420) / 140.0))
        elif y < 1360:
            val = 0
        elif y < 1500:
            val = int(255 * ((y - 1360) / 140.0))
        else:
            val = 255
        color = (val, val, val)
        for x in range(width):
            pixels[x, y] = color
    img.save(mask_path)
    log(f"Generated blur mask at {mask_path}")

def assemble_video(media_path, audio_path, ass_path, output_path, bgm_name="music1.mp3"):
    log(f"Assembling final 9:16 video with FFmpeg (BGM: {bgm_name})...")
    duration = get_audio_duration(audio_path) + 0.6
    log(f"Target duration: {duration:.2f} seconds")

    ext = os.path.splitext(media_path)[1].lower()
    is_image = ext in [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff"]

    # Escape subtitle path for FFmpeg subtitles filter (normalize forward slashes)
    norm_ass = ass_path.replace("\\", "/")
    escaped_ass = norm_ass.replace(":", "\\:").replace("'", "\\'")

    # Generate Top & Bottom Blur Mask
    work_dir = os.path.dirname(output_path)
    mask_path = os.path.join(work_dir, "blur_mask.png")
    generate_blur_mask(mask_path)

    # Check for Background Music file in repository
    bgm_path = None
    if bgm_name and bgm_name.lower() != "none":
        candidate_bgm = os.path.join("music", bgm_name)
        if os.path.exists(candidate_bgm):
            bgm_path = candidate_bgm
            log(f"Found background music file: {bgm_path}")
        else:
            log(f"BGM file {candidate_bgm} not found. Skipping BGM.")

    has_bgm = bgm_path is not None

    if is_image:
        log("Processing image with Top/Bottom Cinema Blur and Poppins subtitles...")
        v_filter = (
            f"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,zoompan=z='min(zoom+0.0006,1.08)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1080x1920:fps=30,setsar=1,format=yuv420p[v_scaled];"
            f"[v_scaled]split=2[fg_sharp][fg_for_blur];"
            f"[fg_for_blur]boxblur=30:5,format=yuv420p[bg_blur];"
            f"[2:v]scale=1080:1920,setsar=1,format=yuv420p[v_mask];"
            f"[fg_sharp][bg_blur][v_mask]maskedmerge[v_merged];"
            f"[v_merged]subtitles='{escaped_ass}':fontsdir='fonts'[v]"
        )
    else:
        log("Processing video with Top/Bottom Cinema Blur and Poppins subtitles...")
        v_filter = (
            f"[0:v]fps=30,setpts=PTS-STARTPTS,scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,format=yuv420p[v_scaled];"
            f"[v_scaled]split=2[fg_sharp][fg_for_blur];"
            f"[fg_for_blur]boxblur=30:5,format=yuv420p[bg_blur];"
            f"[2:v]scale=1080:1920,setsar=1,format=yuv420p[v_mask];"
            f"[fg_sharp][bg_blur][v_mask]maskedmerge[v_merged];"
            f"[v_merged]subtitles='{escaped_ass}':fontsdir='fonts'[v]"
        )

    input_args = ["-loop", "1"] if is_image else ["-stream_loop", "-1"]

    if has_bgm:
        a_filter = (
            f"[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=1.0[voice];"
            f"[3:a]aloop=loop=-1:size=2e+09,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=0.13[bgm_loop];"
            f"[voice][bgm_loop]amix=inputs=2:duration=first:dropout_transition=2[a]"
        )
        filter_complex = f"{v_filter};{a_filter}"
        cmd = [
            "ffmpeg", "-y",
            *input_args,
            "-i", media_path,
            "-i", audio_path,
            "-loop", "1",
            "-i", mask_path,
            "-i", bgm_path,
            "-filter_complex", filter_complex,
            "-map", "[v]",
            "-map", "[a]",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-t", str(duration),
            output_path
        ]
    else:
        a_filter = (
            f"[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=1.0[a]"
        )
        filter_complex = f"{v_filter};{a_filter}"
        cmd = [
            "ffmpeg", "-y",
            *input_args,
            "-i", media_path,
            "-i", audio_path,
            "-loop", "1",
            "-i", mask_path,
            "-filter_complex", filter_complex,
            "-map", "[v]",
            "-map", "[a]",
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

def assemble_multi_scene_video(scene_images, scenes_meta, audio_path, ass_path, output_path, bgm_name="music1.mp3", work_dir="."):
    log(f"Assembling multi-scene video ({len(scene_images)} scenes) with Ken Burns motion & BGM ({bgm_name})...")
    total_dur = get_audio_duration(audio_path) + 0.5
    log(f"Total target video duration: {total_dur:.2f} seconds")

    norm_ass = ass_path.replace("\\", "/")
    escaped_ass = norm_ass.replace(":", "\\:").replace("'", "\\'")

    num_scenes = len(scene_images)
    if scenes_meta and len(scenes_meta) == num_scenes:
        w_counts = [max(1, len(str(s.get("narration", "")).split())) for s in scenes_meta]
        total_words = max(1, sum(w_counts))
        scene_durations = [(w / total_words) * total_dur for w in w_counts]
    else:
        scene_durations = [total_dur / num_scenes for _ in range(num_scenes)]

    # Guarantee min 2.5s per scene
    for i in range(num_scenes):
        if scene_durations[i] < 2.5:
            scene_durations[i] = 2.5
    curr_sum = sum(scene_durations)
    scene_durations = [(d / curr_sum) * total_dur for d in scene_durations]
    log(f"Scene durations (synced to narration): {[round(d, 2) for d in scene_durations]}")

    clip_paths = []
    for idx, (img_path, dur) in enumerate(zip(scene_images, scene_durations)):
        clip_path = os.path.join(work_dir, f"scene_clip_{idx}.mp4")
        num_frames = max(30, int(dur * 30))

        # Ken Burns: alternating gentle zoom in vs zoom out / pan
        if idx % 2 == 0:
            zoom_filter = (
                f"scale=1080:1920:force_original_aspect_ratio=increase,"
                f"crop=1080:1920,"
                f"zoompan=z='min(zoom+0.0004,1.06)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={num_frames}:s=1080x1920:fps=30,"
                f"setsar=1,format=yuv420p"
            )
        else:
            zoom_filter = (
                f"scale=1080:1920:force_original_aspect_ratio=increase,"
                f"crop=1080:1920,"
                f"zoompan=z='min(zoom+0.0003,1.05)':x='(iw-iw/zoom)*(on/{num_frames})':y='ih/2-(ih/zoom/2)':d={num_frames}:s=1080x1920:fps=30,"
                f"setsar=1,format=yuv420p"
            )

        cmd_clip = [
            "ffmpeg", "-y",
            "-i", img_path,
            "-vf", zoom_filter,
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-t", f"{dur:.3f}",
            "-pix_fmt", "yuv420p",
            clip_path
        ]
        log(f"Rendering scene clip {idx+1}/{num_scenes} ({dur:.2f}s)...")
        res = subprocess.run(cmd_clip, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            log(f"Warning: Ken Burns failed for scene {idx}: {res.stderr[:200]}, falling back to static 9:16 loop")
            fallback_filter = "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,format=yuv420p"
            cmd_fallback = [
                "ffmpeg", "-y",
                "-loop", "1",
                "-i", img_path,
                "-t", f"{dur:.3f}",
                "-vf", fallback_filter,
                "-c:v", "libx264", "-preset", "ultrafast", "-crf", "20",
                "-r", "30",
                "-pix_fmt", "yuv420p",
                clip_path
            ]
            subprocess.run(cmd_fallback, check=True)

        clip_paths.append(clip_path)

    # Concat clips
    concat_list_path = os.path.join(work_dir, "concat_scenes.txt")
    with open(concat_list_path, "w", encoding="utf-8") as f_concat:
        for cp in clip_paths:
            norm_cp = cp.replace("\\", "/")
            f_concat.write(f"file '{norm_cp}'\n")

    concatenated_video_path = os.path.join(work_dir, "concatenated_scenes.mp4")
    cmd_concat = [
        "ffmpeg", "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", concat_list_path,
        "-c", "copy",
        concatenated_video_path
    ]
    log(f"Concatenating {len(clip_paths)} scene clips...")
    res_concat = subprocess.run(cmd_concat, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res_concat.returncode != 0:
        raise Exception(f"Failed to concat scene clips: {res_concat.stderr}")

    # Check for Background Music file
    bgm_path = None
    if bgm_name and bgm_name.lower() != "none":
        candidate_bgm = os.path.join("music", bgm_name)
        if os.path.exists(candidate_bgm):
            bgm_path = candidate_bgm
            log(f"Found background music file: {bgm_path}")
        else:
            log(f"BGM file {candidate_bgm} not found. Skipping BGM.")

    has_bgm = bgm_path is not None
    v_filter = f"[0:v]subtitles='{escaped_ass}':fontsdir='fonts'[v]"

    if has_bgm:
        a_filter = (
            f"[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=1.0[voice];"
            f"[2:a]aloop=loop=-1:size=2e+09,aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=0.13[bgm_loop];"
            f"[voice][bgm_loop]amix=inputs=2:duration=first:dropout_transition=2[a]"
        )
        cmd_final = [
            "ffmpeg", "-y",
            "-i", concatenated_video_path,
            "-i", audio_path,
            "-i", bgm_path,
            "-filter_complex", f"{v_filter};{a_filter}",
            "-map", "[v]",
            "-map", "[a]",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-t", f"{total_dur:.2f}",
            output_path
        ]
    else:
        a_filter = "[1:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,volume=1.0[a]"
        cmd_final = [
            "ffmpeg", "-y",
            "-i", concatenated_video_path,
            "-i", audio_path,
            "-filter_complex", f"{v_filter};{a_filter}",
            "-map", "[v]",
            "-map", "[a]",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            "-t", f"{total_dur:.2f}",
            output_path
        ]

    log(f"Burning subtitles at bottom safe zone & mixing audio -> {output_path}...")
    res_final = subprocess.run(cmd_final, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res_final.returncode != 0:
        raise Exception(f"FFmpeg multi-scene assembly error: {res_final.stderr}")
    log(f"Multi-scene video rendered successfully: {output_path} ({os.path.getsize(output_path)} bytes)")

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

        # Find config.json
        config_asset = None
        for a in assets:
            if a["name"].lower() == "config.json":
                config_asset = a
                break

        if not config_asset:
            raise Exception("No 'config.json' found in release assets.")

        config_path = os.path.join(work_dir, "config.json")
        client.download_asset(config_asset, config_path)

        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)

        voice = config.get("voice", "id-ID-GadisNeural")
        script = config.get("script", "").strip()
        topic = config.get("topic", "").strip()
        bgm_name = config.get("bgm", "music1.mp3")
        mode = config.get("mode", "single")
        scenes_meta = config.get("scenes", [])
        gemini_api_key = config.get("gemini_api_key") or os.environ.get("GEMINI_API_KEY", "")

        # Fallback if script is completely empty
        if not script:
            if topic:
                if gemini_api_key:
                    script = generate_script_with_gemini(topic, gemini_api_key)
                else:
                    script = topic
            else:
                script = "Selamat datang di konten video singkat ini. Jangan lupa like dan subscribe!"

        audio_path = os.path.join(work_dir, "narration.mp3")
        ass_path = os.path.join(work_dir, "subtitles.ass")
        output_path = os.path.join(work_dir, "output_shorts.mp4")

        # Check for multi-scene assets (scene_1.jpg, scene_2.jpg, ...)
        scene_assets = []
        for a in assets:
            aname = a["name"].lower()
            if aname.startswith("scene_") and any(aname.endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                scene_assets.append(a)

        def get_scene_index(asset):
            m = re.search(r'scene_(\d+)', asset["name"].lower())
            return int(m.group(1)) if m else 999
        scene_assets.sort(key=get_scene_index)

        is_multi_scene = (mode == "multi_scene" or len(scene_assets) >= 2) and len(scene_assets) > 0

        if is_multi_scene:
            log(f"Multi-scene mode active! Found {len(scene_assets)} scene images.")
            scene_paths = []
            for sa in scene_assets:
                sp = os.path.join(work_dir, sa["name"])
                client.download_asset(sa, sp)
                scene_paths.append(sp)

            # 1. Generate Voice & Subtitles
            await generate_speech_and_subtitles(script, voice, audio_path, ass_path)

            # 2. Assemble Multi-Scene Video with Ken Burns & BGM
            assemble_multi_scene_video(
                scene_images=scene_paths,
                scenes_meta=scenes_meta,
                audio_path=audio_path,
                ass_path=ass_path,
                output_path=output_path,
                bgm_name=bgm_name,
                work_dir=work_dir
            )
        else:
            # Single media mode (image or video from gallery)
            media_asset = None
            for a in assets:
                name = a["name"].lower()
                if any(name.endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".mkv"]) and not name.startswith("scene_"):
                    media_asset = a
                    break
            if not media_asset:
                for a in assets:
                    name = a["name"].lower()
                    if any(name.endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".mkv"]):
                        media_asset = a
                        break
            if not media_asset:
                raise Exception("No media file (image/video) found in release assets.")

            media_path = os.path.join(work_dir, media_asset["name"])
            client.download_asset(media_asset, media_path)

            # 1. Generate Voice & Subtitles
            await generate_speech_and_subtitles(script, voice, audio_path, ass_path)

            # 2. Assemble Video with Cinema Blur, Poppins Subtitles & BGM
            assemble_video(media_path, audio_path, ass_path, output_path, bgm_name=bgm_name)

        # Upload Result to GitHub Release
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
