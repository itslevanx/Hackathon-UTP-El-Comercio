#!/usr/bin/env python3
"""Prepara la configuración pública local para ejecutar desde Xcode."""
import argparse
import base64
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT_KEYS = (
    'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'CARTO_API_KEY',
    'DEFAULT_NEIGHBORHOOD', 'DEFAULT_SECTOR',
)


def encode_config(config):
    if not isinstance(config, dict):
        raise ValueError('El archivo local debe contener un objeto JSON.')
    for key in ('SUPABASE_URL', 'SUPABASE_ANON_KEY'):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError(f'Falta {key} en el archivo local.')
    key = config['SUPABASE_ANON_KEY']
    if key.startswith('sb_secret_'):
        raise ValueError('Usa una clave pública publishable, nunca una clave secreta.')
    parts = key.split('.')
    if len(parts) == 3:
        try:
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
        except (ValueError, UnicodeDecodeError):
            payload = {}
        if isinstance(payload, dict) and payload.get('role') == 'service_role':
            raise ValueError('Una clave service_role no puede incluirse en la app.')
    encoded = []
    for name in CLIENT_KEYS:
        if name not in config:
            continue
        value = config[name]
        if not isinstance(value, str):
            raise ValueError(f'{name} debe ser texto.')
        encoded.append(base64.b64encode(f'{name}={value}'.encode()).decode())
    return '// Configuración local de iOS. No versionar este archivo.\nDART_DEFINES=' + ','.join(encoded) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env', type=Path, default=ROOT / '.env.local.json')
    args = parser.parse_args()
    try:
        text = encode_config(json.loads(args.env.read_text()))
    except (OSError, ValueError) as error:
        parser.exit(1, f'No se pudo preparar la configuración: {error}\n')
    output = ROOT / '.env.ios.xcconfig'
    temporary = output.with_suffix('.xcconfig.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)
    os.replace(temporary, output)
    print('Configuración local de iOS lista. No se muestran valores ni claves.')


if __name__ == '__main__':
    main()
