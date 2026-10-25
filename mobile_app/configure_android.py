import os
import re

def configure():
    print("[CONFIGURE] Configuring Android build files...")
    
    # 1. Patch app-level Kotlin DSL (android/app/build.gradle.kts)
    app_kts = 'android/app/build.gradle.kts'
    if os.path.exists(app_kts):
        with open(app_kts, 'r', encoding='utf-8') as f:
            content = f.read()
        content = re.sub(r'compileSdk\s*=\s*(flutter\.compileSdkVersion|\d+)', 'compileSdk = 36', content)
        content = re.sub(r'targetSdk\s*=\s*(flutter\.targetSdkVersion|\d+)', 'targetSdk = 35', content)
        content = re.sub(r'minSdk\s*=\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 21', content)
        with open(app_kts, 'w', encoding='utf-8') as f:
            f.write(content)
        print('[CONFIGURE] Set compileSdk = 36 in app/build.gradle.kts')

    # 2. Patch app-level Groovy DSL (android/app/build.gradle)
    app_groovy = 'android/app/build.gradle'
    if os.path.exists(app_groovy):
        with open(app_groovy, 'r', encoding='utf-8') as f:
            content = f.read()
        content = re.sub(r'compileSdk\s*=\s*(flutter\.compileSdkVersion|\d+)', 'compileSdk = 36', content)
        content = re.sub(r'compileSdkVersion\s+(flutter\.compileSdkVersion|\d+)', 'compileSdkVersion 36', content)
        content = re.sub(r'targetSdk\s*=\s*(flutter\.targetSdkVersion|\d+)', 'targetSdk = 35', content)
        content = re.sub(r'targetSdkVersion\s+(flutter\.targetSdkVersion|\d+)', 'targetSdkVersion 35', content)
        content = re.sub(r'minSdk\s*=\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 21', content)
        content = re.sub(r'minSdkVersion\s+(flutter\.minSdkVersion|\d+)', 'minSdkVersion 21', content)
        with open(app_groovy, 'w', encoding='utf-8') as f:
            f.write(content)
        print('[CONFIGURE] Set compileSdk = 36 in app/build.gradle')

    # 3. Patch gradle.properties
    gradle_props = 'android/gradle.properties'
    if os.path.exists(gradle_props):
        with open(gradle_props, 'a', encoding='utf-8') as f:
            f.write('\nandroid.suppressUnsupportedCompileSdk=36\n')
        print('[CONFIGURE] Added android.suppressUnsupportedCompileSdk=36 to gradle.properties')

    # 4. Add Android permissions
    manifest_path = 'android/app/src/main/AndroidManifest.xml'
    if os.path.exists(manifest_path):
        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = f.read()
        perms = (
            '    <uses-permission android:name="android.permission.INTERNET"/>\n'
            '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n'
            '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n'
        )
        if '<uses-permission' not in manifest:
            manifest = manifest.replace('<application', perms + '    <application')
            with open(manifest_path, 'w', encoding='utf-8') as f:
                f.write(manifest)
            print('[CONFIGURE] Successfully added permissions to AndroidManifest.xml')

    # 5. Scan and patch all plugins in pub-cache directly to compileSdk 36
    patch_pub_cache()

def patch_pub_cache():
    cache_dirs = [
        os.path.expanduser('~/.pub-cache'),
        '/home/runner/.pub-cache',
        os.environ.get('PUB_CACHE', '')
    ]
    
    seen = set()
    patched_count = 0
    for base in cache_dirs:
        if not base or not os.path.exists(base) or base in seen:
            continue
        seen.add(base)
        print(f"[CONFIGURE] Scanning pub-cache at: {base}")
        for root, dirs, files in os.walk(base):
            for file in files:
                if file in ('build.gradle', 'build.gradle.kts'):
                    file_path = os.path.join(root, file)
                    try:
                        with open(file_path, 'r', encoding='utf-8') as f:
                            lines = f.readlines()
                        
                        modified = False
                        new_lines = []
                        for line in lines:
                            new_line = line
                            if not line.strip().startswith('//'):
                                if 'compileSdkVersion' in line:
                                    nl = re.sub(r'(compileSdkVersion\s*=?\s*\(?)\s*(\d+|flutter\.compileSdkVersion)(\s*\)?)', r'\g<1>36\g<3>', line)
                                    if nl != line:
                                        modified = True
                                        new_line = nl
                                elif 'compileSdk' in line:
                                    nl = re.sub(r'(compileSdk\s*=?\s*\(?)\s*(\d+|flutter\.compileSdkVersion)(\s*\)?)', r'\g<1>36\g<3>', line)
                                    if nl != line:
                                        modified = True
                                        new_line = nl
                            new_lines.append(new_line)

                        if modified:
                            content = ''.join(new_lines)
                            with open(file_path, 'w', encoding='utf-8') as f:
                                f.write(content)
                            patched_count += 1
                            plugin_name = os.path.basename(os.path.dirname(os.path.dirname(file_path)))
                            print(f"[CONFIGURE] Patched {plugin_name} to compileSdk 36 in pub-cache")
                    except Exception as e:
                        pass
    print(f"[CONFIGURE] Total pub-cache plugins patched: {patched_count}")

if __name__ == '__main__':
    configure()
