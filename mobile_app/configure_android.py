import os
import re

def configure():
    print("[CONFIGURE] Configuring Android build files...")
    
    # 1. Handle Kotlin DSL (build.gradle.kts)
    kts_path = 'android/app/build.gradle.kts'
    if os.path.exists(kts_path):
        with open(kts_path, 'r', encoding='utf-8') as f:
            content = f.read()
        content = re.sub(r'compileSdk\s*=\s*(flutter\.compileSdkVersion|\d+)', 'compileSdk = 36', content)
        content = re.sub(r'targetSdk\s*=\s*(flutter\.targetSdkVersion|\d+)', 'targetSdk = 35', content)
        content = re.sub(r'minSdk\s*=\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 21', content)
            
        with open(kts_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print('[CONFIGURE] Successfully set compileSdk = 36 in android/app/build.gradle.kts')

    # 2. Handle Groovy DSL (build.gradle)
    groovy_path = 'android/app/build.gradle'
    if os.path.exists(groovy_path):
        with open(groovy_path, 'r', encoding='utf-8') as f:
            content = f.read()
        content = re.sub(r'compileSdk\s*=\s*(flutter\.compileSdkVersion|\d+)', 'compileSdk = 36', content)
        content = re.sub(r'compileSdkVersion\s+(flutter\.compileSdkVersion|\d+)', 'compileSdkVersion 36', content)
        content = re.sub(r'targetSdk\s*=\s*(flutter\.targetSdkVersion|\d+)', 'targetSdk = 35', content)
        content = re.sub(r'minSdk\s*=\s*(flutter\.minSdkVersion|\d+)', 'minSdk = 21', content)
            
        with open(groovy_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print('[CONFIGURE] Successfully set compileSdk = 36 in android/app/build.gradle')

    # 3. Add Android permissions
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

if __name__ == '__main__':
    configure()
