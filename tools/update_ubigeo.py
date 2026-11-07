#!/usr/bin/env python3
"""Genera el catálogo local del INEI a partir de una exportación HTML de SISCONCODE."""
import argparse
import hashlib
import json
import re
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path

SOURCE = 'https://webapp.inei.gob.pe:8443/sisconcode/ubigeo/listaBusquedaUbigeoPorUbicacionGeografica.htm'

class CatalogParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.hidden = 0
        self.rows = []
        self.cells = None
        self.cell = None
        self.details = []
        self.detail_cell = None
        self.coordinates = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'div' and (self.hidden or 'display:none' in attrs.get('style', '').replace(' ', '')):
            if not self.hidden:
                self.details = []
            self.hidden += 1
        if self.hidden:
            if tag == 'td': self.detail_cell = []
            return
        if tag == 'tr':
            self.cells = []
            self.coordinates = {}
        if tag == 'td': self.cell = []

    def handle_data(self, data):
        if self.hidden:
            if self.detail_cell is not None: self.detail_cell.append(data)
        elif self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if self.hidden:
            if tag == 'td' and self.detail_cell is not None:
                self.details.append(' '.join(''.join(self.detail_cell).split()))
                self.detail_cell = None
            if tag == 'div':
                self.hidden -= 1
                if not self.hidden:
                    for name in ('LATITUD', 'LONGITUD'):
                        if name in self.details:
                            i = self.details.index(name)
                            nums = re.findall(r'\d+(?:\.\d+)?', self.details[i+2])
                            if len(nums) == 3:
                                d,m,s = map(float, nums)
                                if m < 60 and s < 60:
                                    self.coordinates[name] = -round(d + m/60 + s/3600, 6)
            return
        if tag == 'td' and self.cell is not None:
            if self.cells is not None: self.cells.append(' '.join(''.join(self.cell).split()))
            self.cell = None
        if tag == 'tr' and self.cells is not None:
            if len(self.cells) == 4:
                for index, length in ((3,6),(2,4),(1,2)):
                    match = re.fullmatch(r'(\d{%d})\s+(.+)' % length, self.cells[index])
                    if match:
                        code, name = match.groups()
                        row = [code,name]
                        if length == 6 and set(self.coordinates) == {'LATITUD','LONGITUD'}:
                            lat,lng=self.coordinates['LATITUD'],self.coordinates['LONGITUD']
                            if -19 < lat < 1 and -82 < lng < -68: row += [lat,lng]
                        self.rows.append(row)
                        break
            self.cells = None


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('html', type=Path)
    p.add_argument('--retrieved', required=True, help='YYYY-MM-DD')
    p.add_argument('--output', type=Path, default=Path('assets/geography/peru_ubigeo_2026.json'))
    args=p.parse_args()
    raw=args.html.read_bytes()
    # SISCONCODE declares ISO-8859-1 in its response.
    html=raw.decode('iso-8859-1')
    if not re.search(r'UBIGEO AÑO.*?2026',html,re.S): raise ValueError('Expected INEI version 2026')
    parser=CatalogParser();parser.feed(html)
    rows=sorted(parser.rows)
    assert len({r[0] for r in rows}) == len(rows), 'Duplicate codes in source'
    counts=Counter(len(r[0]) for r in rows)
    assert counts == {2:25,4:196,6:1893}, counts
    codes={r[0] for r in rows}
    for code,name,*_ in rows:
        assert '\ufffd' not in name and '\x00' not in name, code
        if len(code)>2: assert code[:-2] in codes, code
    payload={'metadata':{'publisher':'Instituto Nacional de Estadística e Informática (INEI)',
        'source':'SISCONCODE', 'version':'2026', 'versionCategoriaPK':'9-1',
        'url':SOURCE, 'parameters':{'versionCategoriaPK':'9-1','nivel':'1','strVersion':'2026','strDpto':'TODOS','strProv':'TODOS','strDist':'TODOS','flagDpto':'','flagProv':'','flagDist':''},
        'retrievedOn':args.retrieved, 'sourceSha256':hashlib.sha256(raw).hexdigest(),
        'counts':{'departments':25,'provinces':196,'districts':1893},
        'capitalCoordinates':'Optional INEI capital coordinates, south/west, decimal degrees; not home locations.'},
        'departments':[r for r in rows if len(r[0])==2],
        'provinces':[r for r in rows if len(r[0])==4],
        'districts':[r for r in rows if len(r[0])==6]}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
    print(counts)
    print('Missing capital coordinates:',[(r[0],r[1]) for r in payload['districts'] if len(r)<4])
    print('Output bytes:',args.output.stat().st_size)

if __name__ == '__main__': main()
