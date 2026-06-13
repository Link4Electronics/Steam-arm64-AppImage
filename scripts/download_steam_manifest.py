#!/usr/bin/env python3
import os
import shutil
import urllib.request
import zipfile
import sys

CDN_BASE_URL = "https://steamcdn-a.akamaihd.net/client/"

def parse_manifest(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    depots = {}
    current = None
    
    for line in content.split('\n'):
        line = line.lstrip()
        if not line or line == '{':
            continue
        if line == '}':
            current = None
            continue
        
        if '"' not in line:
            continue
        
        parts = line.split('\t')
        key = parts[0].strip('"')
        
        if len(parts) == 1 and key:
            current = key
            depots[current] = {}
            continue
        
        value = parts[-1].strip('"').rstrip(',').rstrip('"')
        if current and key and value:
            depots[current][key] = value
    
    return depots

def sanitize_path(path):
    if not path:
        return path
    path = path.strip().replace('\\', '/')
    parts = path.split('/')
    clean = []
    for p in parts:
        if p and p != '.' and p != '..':
            clean.append(p)
    return '/'.join(clean)

def fix_backslash_paths(base_dir):
    """Rename any paths with backslashes to use forward slashes."""
    for root, dirs, files in os.walk(base_dir, topdown=False):
        for d in dirs:
            if '\\' in d:
                old_path = os.path.join(root, d)
                new_path = old_path.replace('\\', '/')
                if os.path.exists(new_path):
                    for f in os.listdir(old_path):
                        src = os.path.join(old_path, f)
                        dst = os.path.join(new_path, f)
                        if os.path.isdir(src):
                            shutil.move(src, dst)
                        elif os.path.isfile(src):
                            shutil.move(src, dst)
                    os.rmdir(old_path)
                else:
                    os.rename(old_path, new_path)
        
        for f in files:
            if '\\' in f:
                old_path = os.path.join(root, f)
                new_path = old_path.replace('\\', '/')
                os.rename(old_path, new_path)

def download_file(url, output_path):
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    
    if os.path.exists(output_path):
        print(f"Skipping: {os.path.basename(output_path)}")
        return True
    
    print(f"Downloading: {url}")
    try:
        urllib.request.urlretrieve(url, output_path)
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False

def extract_zip(zip_path, extract_to):
    print(f"Extracting: {os.path.basename(zip_path)}")
    os.makedirs(extract_to, exist_ok=True)
    
    temp_dir = extract_to + '_temp'
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)
    
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            for member in zf.namelist():
                fixed = sanitize_path(member)
                if member != fixed:
                    print(f"  Fixed: {member[:60]}...")
                try:
                    zf.extract(fixed, temp_dir)
                except:
                    try:
                        zf.extract(member, temp_dir)
                    except Exception as e:
                        print(f"  Error: {member[:40]}: {e}")
    except Exception as e:
        print(f"Error: {e}")
        shutil.rmtree(temp_dir)
        return True
    
    for item in os.listdir(temp_dir):
        src = os.path.join(temp_dir, item)
        dst = os.path.join(extract_to, item)
        if os.path.exists(dst):
            if os.path.isdir(src) and os.path.isdir(dst):
                for subitem in os.listdir(src):
                    subsrc = os.path.join(src, subitem)
                    subdst = os.path.join(dst, subitem)
                    if os.path.isdir(subsrc):
                        if os.path.exists(subdst) and os.path.isdir(subdst):
                            for subsubitem in os.listdir(subsrc):
                                subsubdst = os.path.join(subdst, subsubitem)
                                subsubsrc = os.path.join(subsrc, subsubitem)
                                if os.path.isfile(subsubdst):
                                    os.remove(subsubdst)
                                if os.path.isfile(subsubsrc):
                                    shutil.move(subsubsrc, subdst)
                            if os.path.isdir(subsrc) and not os.listdir(subsrc):
                                os.rmdir(subsrc)
                        else:
                            shutil.move(subsrc, subdst)
                    elif os.path.isfile(subsrc):
                        if os.path.isfile(subdst):
                            os.remove(subdst)
                        shutil.move(subsrc, subdst)
                if os.path.isdir(src) and not os.listdir(src):
                    os.rmdir(src)
            elif os.path.isfile(src) and os.path.isfile(dst):
                pass
        else:
            shutil.move(src, dst)
    
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    fix_backslash_paths(extract_to)
    
    return True

SKIP_DEPOTS = {
    # Android ARM64 – wrong architecture (overwrites Linux ARM64 .so files)
    'bins_androidarm64_linuxarm64',
}

def fix_dns_via_python():
    """Fallback: try to write /etc/resolv.conf from Python
    if shell methods failed earlier."""
    import os, socket
    try:
        socket.getaddrinfo('steamcdn-a.akamaihd.net', 443)
        return  # DNS already works
    except OSError:
        pass
    resolv_paths = [
        "/etc/resolv.conf",
    ]
    for path in resolv_paths:
        try:
            with open(path, 'w') as f:
                f.write("nameserver 1.1.1.1\nnameserver 8.8.8.8\n")
            print(f"  Fixed /etc/resolv.conf via Python fallback")
            return
        except (IOError, PermissionError):
            continue
    # Last resort: try as root
    try:
        import subprocess
        subprocess.run(
            ["dd", "of=/etc/resolv.conf"],
            input=b"nameserver 1.1.1.1\nnameserver 8.8.8.8\n",
            check=False, timeout=5,
        )
    except Exception:
        pass

def main():
    manifest = "steam_client_publicbeta_linuxarm64"
    extract_dir = "steam"
    download_dir = os.path.join(extract_dir, "package")
    
    os.makedirs(extract_dir, exist_ok=True)
    os.makedirs(download_dir, exist_ok=True)
    manifest_file = os.path.join(download_dir, manifest)

    # Try DNS fix once before downloading manifest
    fix_dns_via_python()

    if not download_file(CDN_BASE_URL + manifest, manifest_file):
        # DNS might still be broken; try fixing and retry once
        fix_dns_via_python()
        if not download_file(CDN_BASE_URL + manifest, manifest_file):
            print("FATAL: Could not download manifest (DNS/network issue).")
            sys.exit(1)

    print(f"Parsing: {manifest}")
    depots = parse_manifest(manifest_file)
    print(f"Found {len(depots)} depots, skipping {sum(1 for n in depots if n in SKIP_DEPOTS)} overlapping/Android depots\n")
    
    for name, info in sorted(depots.items()):
        if not isinstance(info, dict):
            continue
        if name in SKIP_DEPOTS:
            continue
        file_entry = info.get('file')
        if not file_entry:
            continue
        
        file_entry = sanitize_path(file_entry)
        url = CDN_BASE_URL + file_entry
        output_path = os.path.join(download_dir, file_entry)
        
        if not download_file(url, output_path):
            continue
        
        if '.zip' in output_path:
            extract_zip(output_path, extract_dir)

if __name__ == '__main__':
    main()
