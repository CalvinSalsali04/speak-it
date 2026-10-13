#!/usr/bin/env python3
"""Generate a finite, reproducible local TTS development cohort. No human audio.
Synthetic noise/voices do not represent an accent, speaker group or phone mic.
"""
import argparse, array, hashlib, json, math, pathlib, random, subprocess, wave

def load(path):
    with wave.open(str(path),'rb') as w:
        assert (w.getnchannels(),w.getsampwidth(),w.getframerate()) == (1,2,16000)
        values=array.array('h',w.readframes(w.getnframes()))
    return [x/32768 for x in values]

def write(path, values):
    assert all(abs(x)<1 for x in values), 'Clipping: reduce generation level'
    with wave.open(str(path),'wb') as w:
        w.setparams((1,2,16000,0,'NONE','not compressed'))
        w.writeframes(array.array('h',(round(x*32767) for x in values)).tobytes())

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--out',required=True)
    a=p.parse_args(); out=pathlib.Path(a.out); out.mkdir(parents=True,exist_ok=True)
    manifest=pathlib.Path(__file__).with_name('cases.json')
    cases=json.loads(manifest.read_text())['cases']
    records=[]
    for voice in ['Samantha','Daniel']:
        for case in cases:
            parts=[]
            for index,text in enumerate(case['parts']):
                prefix=out/(case['id']+'-'+voice+'-part'+str(index))
                source=prefix.with_suffix('.txt'); source.write_text(text)
                subprocess.run(['say','-v',voice,'-r','175','-f',str(source),'-o',str(prefix.with_suffix('.aiff'))],check=True)
                subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(prefix.with_suffix('.aiff')),'-ar','16000','-ac','1',str(prefix.with_suffix('.wav'))],check=True)
                parts.append(load(prefix.with_suffix('.wav')))
            samples=[0.0]*4800; boundaries=[]
            for index,part in enumerate(parts):
                if index:
                    boundaries.append({'startSeconds':len(samples)/16000,'durationSeconds':case.get('pauseSeconds',0)})
                    samples.extend([0.0]*round(16000*case.get('pauseSeconds',0)))
                samples.extend(x*0.65 for x in part)
            speech_end=len(samples)/16000
            samples.extend([0.0]*96000)
            variants=['quiet']+(['snr20','snr10'] if case['id'] in ['AS05','AS07','AS09'] else [])
            for variant in variants:
                rng=random.Random(case['id']+voice+variant)
                noise=[]; prev=0
                for _ in samples:
                    prev=0.85*prev+0.15*rng.gauss(0,1); noise.append(prev)
                active=[x for x in samples if abs(x)>0.005]
                speech_rms=math.sqrt(sum(x*x for x in active)/max(1,len(active)))
                noise_rms=math.sqrt(sum(x*x for x in noise)/len(noise))
                level=10**(-50/20) if variant=='quiet' else speech_rms/(10**(int(variant[3:])/20))
                mixed=[s+n*level/noise_rms for s,n in zip(samples,noise)]
                peak=max(abs(x) for x in mixed)
                if peak>=0.97: mixed=[x*(0.96/peak) for x in mixed]
                path=out/(case['id']+'-'+voice+'-'+variant+'.wav'); write(path,mixed)
                records.append({'id':case['id'],'voice':voice,'variant':variant,'audio':str(path.resolve()),'script':' '.join(case['parts']), 'expected':case['expected'],'durationSeconds':len(samples)/16000,'speechEndSeconds':speech_end,'pauses':boundaries,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'noise':'seeded synthetic filtered noise; not recorded room tone'})
    (out/'manifest.json').write_text(json.dumps({'schemaVersion':1,'syntheticDevelopmentOnly':True,'sourceCasesSHA256':hashlib.sha256(manifest.read_bytes()).hexdigest(),'records':records},indent=2)+'\n')
    print('Generated',len(records),'synthetic recordings from',len(cases),'scripts.')
if __name__=='__main__': main()
