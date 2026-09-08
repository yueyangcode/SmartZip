"""Workspace-only backend smoke tests; never registers a package/certificate."""
import os, pathlib, subprocess, tempfile, json, time, sys, binascii
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parents[1]
PAYLOAD = ROOT / 'build/payload'
WORK = pathlib.Path(tempfile.mkdtemp(prefix='smoke-', dir=ROOT/'build/tests'))
env = dict(os.environ, SMARTZIP_MODERN_TEST='1', SMARTZIP_MODERN_DATA=str(WORK/'config'))
CREATE_NO_WINDOW = 0x08000000
def run(args, timeout=30):
    p = subprocess.run([str(a) for a in args], env=env, capture_output=True,
                       timeout=timeout, creationflags=CREATE_NO_WINDOW)
    if p.returncode:
        raise RuntimeError(f'{args[0]} exit={p.returncode}: '+p.stdout.decode('utf-8','replace')+p.stderr.decode('utf-8','replace'))
    return p
source = WORK/'source'; source.mkdir()
(source/'内容 📦 & % ! ^.txt').write_text('SmartZip 中文 Unicode payload 123\n', encoding='utf-8')
archives=[]
for extension in ['zip','7z','tar','gz','bz2']:
    target=WORK/f'测试 空格 & % ! ^ ({extension}) 📦.{extension}'
    run([PAYLOAD/'Backend/7z.exe','a',target,source/'内容 📦 & % ! ^.txt'])
    archives.append(target)
start=time.perf_counter()
result=run([PAYLOAD/'Engine/AutoHotkey64.exe','/ErrorStdOut=UTF-8',PAYLOAD/'Engine/SmartZip.ahk','x',*archives])
outputs=[]
for f in WORK.rglob('*'):
    if not f.is_file() or source in f.parents or f in archives: continue
    if f.read_bytes()==(source/'内容 📦 & % ! ^.txt').read_bytes(): outputs.append(str(f.relative_to(WORK)))
assert len(outputs)>=5, (outputs,result.stdout.decode('utf-8','replace'))
# RAR fixture is upstream libarchive stored-data test, not shipped in installer.
fixture=ROOT/'tests/fixtures/rar5-stored.rar.uu'
rar=WORK/'RAR 中文 空格 📦.rar'
rar.write_bytes(b''.join(binascii.a2b_uu(line) for line in fixture.read_bytes().splitlines()[1:-1] if line))
run([PAYLOAD/'SmartZip.exe','x',rar])
assert (WORK/'helloworld.txt').read_bytes()==b'hello libarchive test suite!\n'
# The actual native launcher, not just the AHK engine, must round-trip file paths.
single=WORK/'single 中文 📦'; single.mkdir()
single_archive=single/'空格 & % ! ^.zip'
run([PAYLOAD/'Backend/7z.exe','a',single_archive,source/'内容 📦 & % ! ^.txt'])
run([PAYLOAD/'SmartZip.exe','x',single_archive])
assert (single/'内容 📦 & % ! ^.txt').read_bytes()==(source/'内容 📦 & % ! ^.txt').read_bytes()
split=WORK/'split 中文'; split.mkdir()
run([PAYLOAD/'Backend/7z.exe','a','-v50b',split/'分卷.7z',source/'内容 📦 & % ! ^.txt'])
volumes=sorted(split.glob('分卷.7z.*'))
assert len(volumes)>1
run([PAYLOAD/'SmartZip.exe','x',*volumes])
assert (split/'内容 📦 & % ! ^.txt').read_bytes()==(source/'内容 📦 & % ! ^.txt').read_bytes()
assert len(list(split.glob('*.txt')))==1
cabdir=WORK/'cab'; cabdir.mkdir()
# makecab itself is legacy ANSI; create an ASCII fixture, then test Unicode archive path.
cab_input=cabdir/'payload.txt'; cab_input.write_bytes((source/'内容 📦 & % ! ^.txt').read_bytes())
run([pathlib.Path(os.environ['SystemRoot'])/'System32/makecab.exe',cab_input,cabdir/'sample.cab'])
cab_input.unlink(); (cabdir/'sample.cab').rename(cabdir/'单选.cab')
run([PAYLOAD/'SmartZip.exe','x',cabdir/'单选.cab'])
assert any(f.is_file() and f.suffix!='.cab' and f.read_bytes()==(source/'内容 📦 & % ! ^.txt').read_bytes() for f in cabdir.rglob('*'))
run([PAYLOAD/'DeploymentHelper.exe','inspect','--no-ui'])
print(json.dumps({'workspace':str(WORK),'pass':True,'archive_count':len(archives),'outputs':outputs,'seconds':time.perf_counter()-start},ensure_ascii=False,indent=2))
