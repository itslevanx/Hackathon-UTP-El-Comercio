"""Genera los iconos de cada plataforma a partir del logotipo original."""
import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'assets/branding/conecta2-logo.jpg'
image = ImageOps.pad(Image.open(source).convert('RGB'), (1024, 1024), color='white', method=Image.Resampling.LANCZOS)

def save(relative, size):
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(target)

save('assets/branding/conecta2-icon.png', 1024)
icons = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((icons / 'Contents.json').read_text())['images']:
    size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
    save(str((icons / item['filename']).relative_to(ROOT)), size)
for density, size in {'mdpi':48, 'hdpi':72, 'xhdpi':96, 'xxhdpi':144, 'xxxhdpi':192}.items():
    save(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
for file in (ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'):
    save(str(file.relative_to(ROOT)), int(file.stem.split('_')[-1]))
for size in [192, 512]:
    save(f'web/icons/Icon-{size}.png', size)
    save(f'web/icons/Icon-maskable-{size}.png', size)
save('web/favicon.png', 32)
image.save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=[(s,s) for s in [16,32,48,64,128,256]])
print('Iconos de Conecta2 actualizados.')
