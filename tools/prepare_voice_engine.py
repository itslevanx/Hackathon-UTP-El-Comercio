#!/usr/bin/env python3
"""Download pinned MIT sources and build the iOS static XCFramework locally."""
import argparse, hashlib, os, pathlib, shutil, subprocess, tarfile, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
PLUGIN = ROOT / 'packages/conecta2_voice'
VERSION = '1.9.5'
SHA256 = 'ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720'
URL = f'https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/refs/tags/v{VERSION}'

def run(*args): subprocess.run(list(map(str,args)),check=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ios',action='store_true');parser.add_argument('--cmake',default='cmake');args=parser.parse_args()
    vendor=PLUGIN/'native/whisper';vendor.parent.mkdir(parents=True,exist_ok=True)
    if not vendor.exists():
        archive=vendor.parent/'source.tar.gz'
        if not archive.exists(): urllib.request.urlretrieve(URL,archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA256: raise SystemExit('Hash de fuentes inválido')
        with tarfile.open(archive) as tf:
            for m in tf.getmembers():
                if m.name.startswith('/') or '..' in pathlib.PurePosixPath(m.name).parts or m.issym() or m.islnk():
                    raise SystemExit('Archivo de fuentes inválido')
            tf.extractall(vendor.parent)
        (vendor.parent/f'whisper.cpp-{VERSION}').rename(vendor)
        archive.unlink()
    if not args.ios: return
    headers=PLUGIN/'native/headers';headers.mkdir(exist_ok=True)
    for p in list((vendor/'include').glob('*.h'))+list((vendor/'ggml/include').glob('*.h')): shutil.copy2(p,headers/p.name)
    products=[]
    for sdk in ['iphoneos','iphonesimulator']:
        build=PLUGIN/f'native/build-{sdk}'
        run(args.cmake,'-S',vendor,'-B',build,'-G','Xcode','-DCMAKE_SYSTEM_NAME=iOS',f'-DCMAKE_OSX_SYSROOT={sdk}',
            f'-DCMAKE_OSX_ARCHITECTURES={"arm64" if sdk=="iphoneos" else "arm64;x86_64"}','-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0','-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO',
            '-DBUILD_SHARED_LIBS=OFF','-DWHISPER_BUILD_TESTS=OFF','-DWHISPER_BUILD_EXAMPLES=OFF','-DWHISPER_BUILD_SERVER=OFF',
            '-DGGML_BLAS=OFF','-DGGML_METAL=OFF','-DGGML_ACCELERATE=OFF','-DGGML_OPENMP=OFF','-DGGML_NATIVE=OFF','-DWHISPER_ALL_WARNINGS=OFF')
        run(args.cmake,'--build',build,'--config','Release','--target','whisper','--parallel','4')
        libraries=[p for p in build.rglob('*.a') if p.name in ['libwhisper.a','libggml.a','libggml-base.a','libggml-cpu.a'] and '/Release-' in str(p) and '/Objects-normal/' not in str(p)]
        if len(libraries)!=4: raise SystemExit(f'Bibliotecas incompletas: {libraries}')
        output=PLUGIN/f'native/{sdk}/libWhisperNative.a';output.parent.mkdir(exist_ok=True)
        run('xcrun','libtool','-static','-o',output,*libraries);products.extend(['-library',output,'-headers',headers])
    framework=PLUGIN/'ios/conecta2_voice/WhisperNative.xcframework'
    if framework.exists(): shutil.rmtree(framework)
    run('xcodebuild','-create-xcframework',*products,'-output',framework)

if __name__=='__main__':main()
