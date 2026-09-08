#!/usr/bin/env python3
"""Measure pinned, unmodified pyfa EOS against an independent official SDE adapter.

Development only. Does not download anything. The isolated GUI-config placeholder
prevents wx/SSO initialization; all fitting arithmetic is the actual pyfa EOS.
Uses a new SQLite game DB and an in-memory character DB, never user settings.
Requires SQLAlchemy1.4.54/logbook1.8.2; optional --deps points to an isolated install.
"""
from __future__ import annotations
import argparse, hashlib, json, pathlib, sys, types, zipfile, sqlite3

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--pyfa-source', type=pathlib.Path, required=True)
parser.add_argument('--deps', type=pathlib.Path)
parser.add_argument('--sde', type=pathlib.Path, required=True)
parser.add_argument('--sde-build', required=True)
parser.add_argument('--source-sha256', required=True)
parser.add_argument('--work-dir', type=pathlib.Path, required=True, help='New isolated scratch directory')
parser.add_argument('--inputs', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
if args.output.exists() or args.work_dir.exists():
    parser.error('Output/work directory already exists; choose new paths to preserve evidence')
lock = json.loads((pathlib.Path(__file__).with_name('pyfa-source.lock.json')).read_text())
for name, sha in lock['files'].items():
    data = (args.pyfa_source / name).read_bytes()
    if hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() != sha:
        parser.error(f'Pinned pyfa source mismatch: {name}')
if hashlib.sha256(args.sde.read_bytes()).hexdigest() != args.source_sha256:
    parser.error('SDE archive checksum mismatch')
inputs = json.loads(args.inputs.read_text(encoding='utf-8'))
args.work_dir.mkdir(parents=True)
root = args.work_dir.resolve()
sys.path.insert(0, str(args.pyfa_source.resolve()))
if args.deps:
    sys.path.insert(0, str(args.deps.resolve()))
sys.modules['config'] = types.ModuleType('config')
sys._called_from_test = True
import eos.config
eos.config.gamedata_connectionstring = 'sqlite:///' + (root / 'pyfa-sde.db').as_posix()
import eos.db

def load_sde():
    path = args.sde
    with zipfile.ZipFile(path) as z:
        with z.open('_sde.jsonl') as f:
            identities = [row for row in map(json.loads, f) if row.get('_key') == 'sde']
        if len(identities) != 1 or str(identities[0].get('buildNumber')) != args.sde_build:
            raise ValueError('Requested SDE build differs from official archive identity')
        result = {}
        for name in ['categories','groups','types','dogmaAttributes','dogmaEffects','typeDogma']:
            with z.open(name + '.jsonl') as f:
                result[name] = {r['_key']: r for r in map(json.loads, f)}
        return result

def build():
    eos.db.gamedata_meta.create_all()
    data = load_sde()
    con = sqlite3.connect(root / 'pyfa-sde.db')
    def insert(table, rows):
        columns = [r[1] for r in con.execute(f'PRAGMA table_info({table})')]
        rows = list(rows)
        if rows:
            con.executemany(f'INSERT INTO {table} ({",".join(columns)}) VALUES ({",".join("?" for _ in columns)})',
                            [[row.get(col) for col in columns] for row in rows])
    insert('invcategories', (dict(r,categoryID=k,name=r['name'].get('en',str(k))) for k,r in data['categories'].items()))
    insert('invgroups', (dict(r,groupID=k,name=r['name'].get('en',str(k))) for k,r in data['groups'].items()))
    attrs = {k:{a['attributeID']:a['value'] for a in r.get('dogmaAttributes',[])} for k,r in data['typeDogma'].items()}
    attr_rows = []
    type_rows = []
    for k,r in data['types'].items():
        a = attrs.get(k,{}).copy()
        for aid, field in {4:'mass',38:'capacity',161:'volume',162:'radius'}.items():
            if field in r: a.setdefault(aid,r[field])
        for aid,value in a.items(): attr_rows.append({'typeID':k,'attributeID':aid,'value':value})
        req = {str(int(a[aid])):int(a.get(lid,1)) for aid,lid in [(182,277),(183,278),(184,279),(1285,1286),(1289,1287),(1290,1288)] if a.get(aid)}
        type_rows.append(dict(r,typeID=k,typeName=r['name'].get('en',str(k)),typeDescription='',reqskills=json.dumps(req),requiredfor='{}',metaLevel=a.get(633),replacements='[]'))
    insert('invtypes',type_rows)
    insert('dgmattribs',(dict(r,attributeID=k,attributeName=r['name'],displayName=r.get('displayName',{}).get('en',''),description=r.get('description','')) for k,r in data['dogmaAttributes'].items()))
    insert('dgmtypeattribs',attr_rows)
    insert('dgmeffects',(dict(r,effectID=k,effectName=r['name'],description='') for k,r in data['dogmaEffects'].items()))
    insert('dgmtypeeffects',({'typeID':k,'effectID':e['effectID']} for k,r in data['typeDogma'].items() for e in r.get('dogmaEffects',[])))
    con.commit()
    print('Created independent pyfa SQLite from official SDE.',flush=True)


build()
from eos.saveddata.fit import Fit
from eos.saveddata.ship import Ship
from eos.saveddata.module import Module
from eos.saveddata.drone import Drone
from eos.saveddata.character import Character
from eos.saveddata.damagePattern import DamagePattern
from eos.const import FittingModuleState

units = {'cpu_output':'tf','cpu_used':'tf','powergrid_output':'MW','powergrid_used':'MW','speed':'m/s','ehp':'HP','align_time':'s','dps':'HP/s','dps_with_reload':'HP/s','drone_dps':'HP/s','alpha':'HP'}
outputs = []
for case in inputs['cases']:
    name, context = case['id'], case['input']
    if set(context) != {'nativeFit','damageProfile','boosters','fleetEffects','environment'}:
        raise ValueError(f'{name}: unsupported or missing context')
    if context['damageProfile'] != dict(em=.25, thermal=.25, kinetic=.25, explosive=.25):
        raise ValueError('This capture supports explicit25%omni only')
    if any(context[key] != [] for key in ['boosters','fleetEffects','environment']):
        raise ValueError('This capture does not support projected effects')
    nativeFit = context['nativeFit']
    if set(nativeFit) != {'ship_type_id','skill_mode','skills','modules','drones','implants'}:
        raise ValueError(f'{name}: unsupported nativeFit fields')
    if nativeFit['skills'] or nativeFit['implants'] or nativeFit['skill_mode'] not in ['all5','custom']:
        raise ValueError('This capture supports all5/all0 without implants only')
    fit = Fit(Ship(eos.db.getItem(nativeFit['ship_type_id'])), name)
    fit.character = Character('Reference '+name, 5 if nativeFit['skill_mode']=='all5' else 0)
    fit.damagePattern = DamagePattern(25,25,25,25)
    fit.factorReload = False
    for m in nativeFit['modules']:
        if set(m) != {'type_id','slot_type','index','state','charge_type_id'}:
            raise ValueError('Unsupported module fields')
        module = Module(eos.db.getItem(m['type_id']))
        expected_slot = {'low':1,'medium':2,'high':3,'rig':4,'subsystem':5}[m['slot_type']]
        if module.slot != expected_slot:
            raise ValueError('Module slot does not match pyfa slot')
        module.owner = fit
        module.state = {'offline':FittingModuleState.OFFLINE,'online':FittingModuleState.ONLINE,'active':FittingModuleState.ACTIVE,'overloaded':FittingModuleState.OVERHEATED}[m['state']]
        if m['charge_type_id']:
            module.charge = eos.db.getItem(m['charge_type_id'])
        fit.modules.append(module)
    for d in nativeFit['drones']:
        if set(d) != {'type_id','quantity','state'}:
            raise ValueError('Unsupported drone fields')
        drone = Drone(eos.db.getItem(d['type_id']))
        drone.owner = fit
        drone.amount = d['quantity']
        if d['state'] not in ['active','online']:
            raise ValueError('Unsupported drone state')
        drone.amountActive = d['quantity'] if d['state']=='active' else 0
        fit.drones.append(drone)
    fit.calculateModifiedAttributes()
    stats = {key:fit.ship.getModifiedItemAttr(attr) for key,attr in [('cpu_output','cpuOutput'),('powergrid_output','powerOutput'),('speed','maxVelocity')]}
    stats.update(cpu_used=fit.getItemAttrOnlineSum(fit.modules,'cpu'),powergrid_used=fit.getItemAttrOnlineSum(fit.modules,'power'),
                 ehp=sum(fit.ehp.values()),align_time=fit.alignTime,dps=fit.getTotalDps().total,
                 drone_dps=fit.getDroneDps().total,alpha=fit.getTotalVolley().total)
    fit.factorReload=True
    fit.calculateModifiedAttributes()
    stats['dps_with_reload']=fit.getTotalDps().total
    outputs.append(dict(id=name,input=context,metrics={key:dict(value=value,unit=units[key],absoluteTolerance=1e-6,relativeTolerance=1e-6) for key,value in stats.items()}))
    print(f'Measured {name}', flush=True)
result=dict(schemaVersion=1,gameServer='Tranquility',dataVersion=f'sde:{args.sde_build};fsd:sde-{args.sde_build}',synthetic=False,
            producer=dict(name='pyfa',version='EOS-headless',revision=lock['revision'],
                          sourceArchiveSha256=args.source_sha256,
                          adapter='Independent official JSONL to pyfa SQLite; unmodified EOS calculation source; no GUI'),cases=outputs)
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
print(f'Captured {len(outputs)} independently measured fits. No parity claim until compare_pyfa.py passes.')
