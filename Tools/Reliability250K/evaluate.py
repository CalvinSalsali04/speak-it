#!/usr/bin/env python3
"""Offline deterministic coverage audit. Findings are candidates, not accuracy claims.
Never invokes production, modifies contracts, or credits missing native fields.
"""
import argparse, collections, functools, hashlib, importlib.util, itertools, json, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('legacy',ROOT/'Tools/SpeechLabStressBank/run.py');legacy=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy)
VERSION='coverage250k-0.2'
def norm(s):return ' '.join(re.findall(r'\w+',str(s or '').casefold().replace('’',"'")))
def retained(value,text):return norm(value) in norm(text)
def uncertain(a):return a.get('needsReview',False) or a.get('state') not in (None,'resolved') or a.get('unsupportedTrigger') is not None
def confident(a):return a.get('route')=='Today' and not uncertain(a)
def best_alignment(expected,actual):
    if not expected or not actual:return []
    scores=[]
    for exp in expected:
        row=[]
        for got in actual:
            text=legacy.actual_item_text(got)
            score=legacy.field_similarity(exp,got)
            if exp.get('target') and retained(exp['target'],text):score+=3
            if exp.get('exact_value') and str(exp['exact_value']) in text:score+=4
            if (exp.get('kind') in ('task','appointment'))==(got.get('route')=='Today'):score+=2
            row.append(score)
        scores.append(row)
    if max(len(expected),len(actual))>12:
        available=set(range(len(actual)));pairs=[]
        for e in range(len(expected)):
            if not available:break
            a=max(sorted(available),key=lambda a:scores[e][a]);available.remove(a);pairs.append((e,a))
        return pairs
    swapped=len(expected)>len(actual)
    small,large=(len(actual),len(expected)) if swapped else (len(expected),len(actual))
    @functools.lru_cache(None)
    def solve(i,mask):
        if i==small:return (0,())
        best=(-float('inf'),())
        for j in range(large):
            if mask&(1<<j):continue
            score,tail=solve(i+1,mask|(1<<j));pair=(j,i) if swapped else (i,j)
            candidate=(score+scores[pair[0]][pair[1]],(pair,)+tail)
            if candidate[0]>best[0]:best=candidate
        return best
    return list(solve(0,0)[1])

def explicit_clock(value):
    # Explicit meridiem has one meaning; unlike bare 'at 9', never accept 21:00.
    m=re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b",str(value or ''),re.I)
    if not m:return None
    hour,minute=int(m[1]),int(m[2] or 0)
    if not 1<=hour<=12 or minute>59:return None
    return [hour%12+(12 if m[3].lower().startswith('p') else 0),minute]

def compare_one(row,raw):
    expected=row['expected_contract'].get('items',[]);actual=raw['items'];flags=set();unmeasured=set();checks=[]
    if len(expected)!=len(actual):flags.add('over_splitting' if len(actual)>len(expected) else 'under_splitting')
    alignment=best_alignment(expected,actual)
    if len(expected)>len(alignment):flags.add('lost_item')
    if len(actual)>len(alignment):flags.add('extra_item')
    for e,a in alignment:
        x,y=expected[e],actual[a];text=' '.join(str(y.get(k) or '') for k in ('title','analysis'));quote=y.get('rawQuote','');c={'expected_index':e,'actual_index':a,'checks':{}}
        def check(key,value):
            c['checks'][key]=bool(value)
            if not value:flags.add(key)
        wants_action=x.get('kind') in ('task','appointment')
        check('actionability', (y.get('route')=='Today')==wants_action)
        if not wants_action and confident(y):flags.add('non_actionable_confident_action')
        if x.get('action') not in ('remember','remind','note','save','question'):
            check('action_content',legacy.action_matches(x.get('action',''),text,x.get('object','')))
        if x.get('object'):check('object_content',legacy.phrase_matches(x['object'],text,.75))
        if x.get('destination'):check('destination_content',legacy.phrase_matches(x['destination'],text))
        target=x.get('target') or x.get('person');target_type=x.get('target_type')
        if target:check('target_identity_text',retained(target,text))
        if target_type:
            # Production exposes personName, but has no full target-type enum.
            unmeasured.add('full_target_type_ontology')
            person=y.get('person')
            if target_type in ('organization','business','business_location','task_topic','topic','department','service') and person:
                check('nonperson_as_person',not retained(person,target or text))
            if target_type in ('person','relationship_contact'):
                check('person_identity',norm(person)==norm(target))
        elif x.get('person'):check('person_identity',norm(y.get('person'))==norm(target))
        if not target and y.get('person') and x.get('object') and retained(y['person'],x['object']):
            check('task_object_as_person',False)
        if x.get('polarity')=='negative':
            negative=bool(re.search(r"\b(not|never|don't|do not|avoid|skip)\b",str(y.get('title','')).casefold()))
            check('negative_polarity',negative)
            if not negative and confident(y):flags.add('negation_confident_positive')
        date=x.get('date');tm=x.get('time')
        date_ok,time_ok=legacy.temporal_matches(x,y)
        if date:
            if legacy.normalize_text(date) in legacy.DATE_DAYS|{k:None for k in legacy.AMBIGUOUS_DATES}:check('date',date_ok)
            else:unmeasured.add('date_semantics:'+str(date))
        if tm:
            # Unsupported temporal phrases are explicitly unmeasured, not automatic failures.
            if explicit_clock(tm):
                clock=y.get('wallClock') or {};check('time',[clock.get('hour'),clock.get('minute')]==explicit_clock(tm))
            elif legacy.clock_candidates(tm):check('time',time_ok)
            else:
                unmeasured.add('advanced_time_semantics')
                if not uncertain(y) and y.get('temporal')=='none':flags.add('temporal_phrase_lost')
        if x.get('recurrence'):
            try: legacy.expected_recurrence(x['recurrence'])
            except KeyError: unmeasured.add('advanced_recurrence_semantics')
            else: check('recurrence',legacy.recurrence_matches(x,y))
        if row['category']=='advanced_temporal':unmeasured.add('deadline_range_DST_semantics')
        zone_text=str(tm or '')+' '+str(x.get('notes') or '')
        zones={'Toronto':'America/Toronto','London':'Europe/London','New York':'America/New_York','Vancouver':'America/Vancouver','Tokyo':'Asia/Tokyo','Paris':'Europe/Paris','UTC':'GMT','GMT':'GMT'}
        for name,zone in zones.items():
            if re.search(r'\b'+re.escape(name)+r'\s+time\b',zone_text,re.I):
                native=y.get('temporalIntent') or {};actual_zone=y.get('timeZone');check('time_zone',actual_zone==zone or (zone=='GMT' and actual_zone in ('UTC','Etc/UTC','Etc/GMT')))
                if 'timeZoneBehavior' in native:check('fixed_time_zone',native['timeZoneBehavior']=='fixed')
                else:unmeasured.add('time_zone_behavior_not_exported')
        if x.get('trigger'):
            trigger=x['trigger'];location=y.get('location','nil');event={'arrival':'arrive','departure':'leave'}.get(trigger.get('type'))
            if event:
                check('location_event',location.startswith(event+' '))
                place=trigger.get('place','');place={'here':'current','current location':'current'}.get(norm(place),place);check('location_place',retained(place,location))
            else:
                unmeasured.add('unsupported_location_trigger')
                check('location_review',uncertain(y))
        exact=x.get('exact_value')
        if exact:
            check('exact_value_display',str(exact) in text)
            c['checks']['exact_value_raw_quote']=str(exact) in quote
        if x.get('action') in ('conditional_task','conditional_reminder') or re.search(r'\bcondition\s*:',str(x.get('notes','')),re.I):
            preserved=bool(re.search(r'\b(if|unless|when|once|after|before|until)\b',text,re.I))
            check('conditional_dependency',preserved or y.get('unsupportedTrigger')=='condition')
            if not preserved and confident(y):flags.add('condition_confident_unconditional')
        checks.append(c)
    matched_actual={a for _,a in alignment}
    extra_confident=[a for index,a in enumerate(actual) if index not in matched_actual and confident(a)]
    phenomena=set(row.get('phenomena',[]))
    if extra_confident and phenomena & {'selective_cancellation','full_abandonment','explicit_abandonment','cancellation_scope'}:
        destinations=row.get('entities',{}).get('destinations',[])
        objects=row.get('entities',{}).get('objects',[])
        active_destinations={norm(x.get('destination')) for x in expected}
        canceled=[(i,d) for i,d in enumerate(destinations) if norm(d) not in active_destinations]
        if 'selective_cancellation' in phenomena and canceled and expected:
            # Extra rows can be the visit and its shopping action represented
            # separately. Require evidence of the withdrawn group itself.
            active_objects={norm(x.get('object')) for x in expected}
            visible=[' '.join(str(a.get(k) or '') for k in ('title','analysis','shoppingGroup')) for a in actual if confident(a)]
            leak=False
            for index,destination in canceled:
                target=re.sub(r'^(?:the|a|an|my)\s+','',norm(destination))
                visit=r'\b(?:go|head|come|drive|walk|run) to (?:the )?'+re.escape(target)+r'\b'
                leak |= any(re.search(visit,norm(text)) for text in visible)
                if len(objects)==len(destinations) and norm(objects[index]) not in active_objects:
                    leak |= any(retained(objects[index],text) for text in visible)
                else:unmeasured.add('cancellation_duplicate_object_attribution')
            if leak:flags.add('cancellation_scope_leak_candidate')
        else:flags.add('cancellation_scope_leak_candidate')
    if extra_confident and any(x.get('action') in ('conditional_task','conditional_reminder') for x in expected):
        if any(not re.search(r'\b(if|unless)\b',a.get('title',''),re.I) for a in extra_confident):flags.add('condition_confident_unconditional')
    if not expected and any(confident(a) for a in actual):flags.add('empty_contract_confident_action')
    if row.get('ambiguity_state')=='requires_review':
        if not any(uncertain(a) for a in actual):flags.add('ambiguity_review_absent')
    if row.get('context'):unmeasured.add('context_not_supplied_by_host_runner')
    if row['category']=='reported_quoted_speech' and raw.get('operations'):flags.add('reported_speech_operation_candidate')
    if row['category']=='reported_quoted_speech' and 'non_actionable_confident_action' in flags:flags.add('reported_speech_action_leak')
    for a in actual:
        if not a.get('wasRepaired') and not set(norm(a.get('quote')).split())<=set(norm(row['utterance']).split()):flags.add('quote_invented_tokens')
    if raw.get('operations'):
        unmeasured.add('operation_store_effects')
        if any('polarity' not in op or 'needsReview' not in op for op in raw['operations']):unmeasured.add('operation_polarity_review_not_exported')
    p0={'cancellation_scope_leak_candidate','non_actionable_confident_action','negation_confident_positive','condition_confident_unconditional','empty_contract_confident_action','reported_speech_operation_candidate','reported_speech_action_leak'}
    p2=set()  # Semantic equivalence adjudication may later demote lexical-only differences.
    priority='P0' if flags&p0 else 'P1' if flags-p2 else 'P2' if flags else None
    return {'dimensions':sorted(flags),'unmeasured':sorted(unmeasured),'checks':checks,'severity_candidate':priority,'agreement_on_measured_checks':not flags,'fully_measured':not unmeasured,'expected_count':len(expected),'actual_count':len(actual),'lost_information_indicators':sorted(flags&{'lost_item','under_splitting','object_content','exact_value_display','temporal_phrase_lost'}),'invented_information_indicators':sorted(flags&{'extra_item','over_splitting','quote_invented_tokens'}),'safety_indicators':sorted(flags&p0)}

def inspect(row,raw):
    contracts=[row['expected_contract'],*row.get('acceptable_contracts',[])]
    comparisons=[compare_one({**row,'expected_contract':contract},raw) for contract in contracts]
    index=min(range(len(comparisons)),key=lambda i:(len(comparisons[i]['dimensions']),len(comparisons[i]['safety_indicators'])))
    result=comparisons[index]
    result['matched_contract_index']=index
    result['primary_expected_count']=len(row['expected_contract'].get('items',[]))
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=pathlib.Path,required=True);a=ap.parse_args();out=a.output
    categories=collections.defaultdict(collections.Counter);families=collections.defaultdict(collections.Counter);dims=collections.Counter();severity=collections.Counter();clusters={};total=0;agreement=0;ambiguity=0;unmeasured=collections.Counter();field_counts=collections.defaultdict(collections.Counter)
    raw_path=out/'actual.jsonl';assert raw_path.exists(),'Full raw baseline must finish first'
    with (out/'bank.jsonl').open() as bank,raw_path.open() as raw,(out/'results.jsonl').open('w') as dest:
        for b,r in itertools.zip_longest(bank,raw):
            assert b is not None and r is not None,'Missing/extra raw output'
            row=json.loads(b);actual=json.loads(r);assert row['utterance'].strip()==actual['text']
            result=inspect(row,actual);total+=1;agreement+=result['agreement_on_measured_checks'];ambiguity+=row.get('ambiguity_state')=='requires_review';dims.update(result['dimensions']);unmeasured.update(result['unmeasured']);severity[result['severity_candidate'] or 'no_candidate']+=1
            for group,key in ((categories,row['category']),(families,row['semantic_family'])):
                group[key]['total']+=1;group[key]['agreement_on_measured_checks']+=result['agreement_on_measured_checks'];group[key]['fully_measured']+=result['fully_measured'];group[key][result['severity_candidate'] or 'no_candidate']+=1
            for item in result['checks']:
                for field,ok in item['checks'].items():field_counts[field]['evaluated']+=1;field_counts[field]['passed']+=ok
            record={'case_id':row['case_id'],'utterance':row['utterance'],'expected_contract':row['expected_contract'],'acceptable_contracts':row.get('acceptable_contracts',[]),'context':row.get('context',{}),'raw_production_result':actual,'normalized_comparison':result,'category':row['category'],'semantic_family':row['semantic_family'],'structure_id':row['structure_id'],'phenomena':row['phenomena'],'ambiguity_state':row['ambiguity_state']}
            dest.write(json.dumps(record,ensure_ascii=False)+'\n')
            if result['dimensions']:
                key=(row['semantic_family'],result['severity_candidate'])
                c=clusters.setdefault(key,{'semantic_family':key[0],'severity_candidate':key[1],'count':0,'dimensions':collections.Counter(),'structural_variants':collections.Counter(),'examples':[],'classification':'unadjudicated_candidate','bank_credibility':'unreviewed','local_model_agreement':None})
                c['count']+=1;c['dimensions'].update(result['dimensions']);c['structural_variants'][row['structure_id']]+=1
                if len(c['examples'])<3:c['examples'].append(record)
    for c in clusters.values():c['percent_of_family']=100*c['count']/families[c['semantic_family']]['total']
    ordered=sorted(clusters.values(),key=lambda c:(c['severity_candidate'],-c['count']))
    summary={'version':VERSION,'total':total,'agreement_on_measured_checks':agreement,'disagreement_on_measured_checks':total-agreement,'severity_candidates':severity,'bank_marked_ambiguity':ambiguity,'questionable_bank_contract_count':None,'local_llm_agreement':None,'dimensions':dims,'unmeasured':unmeasured,'per_category':categories,'per_family':families,'field_checks':field_counts,'evaluator_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'legacy_helpers_sha256':hashlib.sha256(pathlib.Path(legacy.__file__).read_bytes()).hexdigest(),'warning':'Severity and clusters are deterministic candidates, not confirmed root causes. Missing ontology, context, advanced semantics, and semantic-equivalence adjudication preclude an accuracy claim.'}
    (out/'summary.json').write_text(json.dumps(summary,indent=2));(out/'clusters.json').write_text(json.dumps(ordered,indent=2));print(json.dumps({k:summary[k] for k in ('total','agreement_on_measured_checks','severity_candidates')}))
if __name__=='__main__':main()
