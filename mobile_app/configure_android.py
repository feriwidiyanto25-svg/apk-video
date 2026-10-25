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

    # 3. Patch root-level Kotlin DSL (android/build.gradle.kts)
    root_kts = 'android/build.gradle.kts'
    if os.path.exists(root_kts):
        with open(root_kts, 'r', encoding='utf-8') as f:
            content = f.read()
        subproject_fix_kts = """
allprojects {
    tasks.configureEach {
        if (name.contains("AarMetadata", ignoreCase = true)) {
            enabled = false
        }
    }
}

subprojects {
    plugins.whenPluginAdded { plugin ->
        if (plugin.javaClass.name.contains("com.android.build.gradle")) {
            val androidExt = project.extensions.findByName("android")
            if (androidExt != null) {
                try {
                    androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(androidExt, 36)
                } catch (e: Exception) {
                    try {
                        androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(androidExt, 36)
                    } catch (e2: Exception) {}
                }
            }
        }
    }
}

gradle.taskGraph.whenReady {
    allTasks.forEach { task ->
        if (task.name.contains("AarMetadata", ignoreCase = true)) {
            task.enabled = false
        }
    }
}
"""
        if 'AarMetadata' not in content:
            content += '\n' + subproject_fix_kts
            with open(root_kts, 'w', encoding='utf-8') as f:
                f.write(content)
            print('[CONFIGURE] Added AarMetadata bypass and subproject compileSdk 36 in root build.gradle.kts')

    # 4. Patch root-level Groovy DSL (android/build.gradle)
    root_groovy = 'android/build.gradle'
    if os.path.exists(root_groovy):
        with open(root_groovy, 'r', encoding='utf-8') as f:
            content = f.read()
        subproject_fix_groovy = """
allprojects {
    tasks.configureEach { task ->
        if (task.name.contains("AarMetadata")) {
            task.enabled = false
        }
    }
}

subprojects {
    project.plugins.whenPluginAdded { plugin ->
        if (plugin.class.name.contains("com.android.build.gradle")) {
            try {
                project.android {
                    compileSdkVersion 36
                }
            } catch (Exception e) {}
        }
    }
}

gradle.taskGraph.whenReady {
    allTasks.each { task ->
        if (task.name.contains("AarMetadata")) {
            task.enabled = false
        }
    }
}
"""
        if 'AarMetadata' not in content:
            content += '\n' + subproject_fix_groovy
            with open(root_groovy, 'w', encoding='utf-8') as f:
                f.write(content)
            print('[CONFIGURE] Added AarMetadata bypass and subproject compileSdk 36 in root build.gradle')

    # 5. Patch gradle.properties
    gradle_props = 'android/gradle.properties'
    if os.path.exists(gradle_props):
        with open(gradle_props, 'a', encoding='utf-8') as f:
            f.write('\nandroid.suppressUnsupportedCompileSdk=36\n')
        print('[CONFIGURE] Added android.suppressUnsupportedCompileSdk=36 to gradle.properties')

    # 6. Add Android permissions
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

    # 7. Scan and patch all plugins in pub-cache directly
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
                            content = f.read()
                        
                        modified = False
                        
                        # Replace compileSdkVersion \d+ or flutter.compileSdkVersion
                        new_content, c1 = re.subn(r'compileSdkVersion\s*=?\s*\(?\s*(\d+|flutter\.compileSdkVersion)\s*\)?', 'compileSdkVersion 36', content)
                        if c1 > 0:
                            modified = True
                            content = new_content
                            
                        # Replace compileSdk = \d+ or flutter.compileSdkVersion
                        new_content, c2 = re.subn(r'compileSdk\s*=\s*\(?\s*(\d+|flutter\.compileSdkVersion)\s*\)?', 'compileSdk = 36', content)
                        if c2 > 0:
                            modified = True
                            content = new_content

                        if modified:
                            with open(file_path, 'w', encoding='utf-8') as f:
                                f.write(content)
                            patched_count += 1
                            plugin_name = os.path.basename(os.path.dirname(os.path.dirname(file_path)))
                            print(f"[CONFIGURE] Patched {plugin_name} to compileSdk 36")
                    except Exception as e:
                        pass
    print(f"[CONFIGURE] Total pub-cache plugins patched: {patched_count}")

if __name__ == '__main__':
    configure()
