#!/usr/bin/env python3
"""Render a candid baseline report from saved evidence, with no parser calls."""
import argparse,collections,json,pathlib
ROOTS=[
 ('reported_speech_action_leak','Reported speech promoted to confident action','ActionabilityReader reported-obligation precedence and clause segmentation'),
 ('reported_speech_operation_candidate','Reported speech interpreted as a capture operation','CaptureOperationDetector.partition before semantic attribution'),
 ('non_actionable_confident_action','Non-actionable content promoted to confident action','ActionabilityReader / ThoughtOrganizer routing precedence'),
 ('cancellation_scope_leak_candidate','Possible cancellation scope leak','CaptureOperationDetector partition and downstream segmentation'),
 ('condition_confident_unconditional','Conditional capture produced an unconditional action','ClauseStructure dependency preservation'),
 ('negation_confident_positive','Negative intent displayed as positive action','Negation scope through repairs and title formation'),
 ('empty_contract_confident_action','Confident action where bank expects no saved item','Capture operations, abandonment and bank interpretation'),
 ('nonperson_as_person','Non-person target assigned a person name','PersonMentionResolver target-role and name evidence'),
 ('task_object_as_person','Task/topic object assigned a person name','PersonMentionResolver semantic-role boundaries'),
 ('person_identity','Person identity differs','PersonMentionResolver name boundaries and target evidence'),
 ('location_event','Location event missing or changed','LocationIntentParser trigger scope'),
 ('location_place','Location reference missing or changed','LocationIntentParser place boundaries'),
 ('location_review','Unsupported location not marked for review','LocationIntentParser deictic/unsupported state'),
 ('exact_value_display','Exact value absent from displayed/analysis content','SpeechRepair, segmentation and title projection'),
 ('over_splitting','Too many saved items','Clause segmentation and IntentConsolidation'),
 ('under_splitting','Too few saved items','Operations, consolidation and semantic segmentation'),
 ('actionability','Task versus memory routing differs','ActionabilityReader / ThoughtOrganizer'),
 ('date','Date differs','TemporalIntent parsing and temporal scope propagation'),
 ('time','Clock differs','Clock parsing and temporal scope propagation'),
 ('recurrence','Recurrence differs','RecurrenceIntentParser'),
 ('temporal_phrase_lost','Temporal phrase lacks a native interpretation','TemporalIntent unsupported handling'),
 ('ambiguity_review_absent','Bank ambiguity lacks product review state','Semantic-state / bank ambiguity contract'),
 ('target_identity_text','Target text not retained','Entity role and title projection'),
 ('object_content','Object content differs lexically','Segmentation / title projection; semantic adjudication required'),
 ('action_content','Action differs lexically','Action frame / title projection; semantic adjudication required'),
 ('destination_content','Destination content differs lexically','Context inheritance / title projection'),
 ('quote_invented_tokens','Unexplained quote-token additions','TranscriptProvenance and repair accounting'),
]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=pathlib.Path,required=True);a=ap.parse_args();out=a.output
 summary=json.loads((out/'summary.json').read_text());freeze=json.loads((out/'freeze.json').read_text());execution=json.loads((out/'execution.json').read_text());clusters={};categories=summary['per_category']
 with (out/'results.jsonl').open() as f:
  for line in f:
   r=json.loads(line);c=r['normalized_comparison'];flags=set(c['dimensions'])
   if not flags:continue
   dim,title,source=next((v for v in ROOTS if v[0] in flags),('other','Other measured disagreement','Requires investigation'))
   key=(dim,c['severity_candidate']);cluster=clusters.setdefault(key,{'candidate_family':title,'primary_dimension':dim,'severity_candidate':key[1],'count':0,'categories':collections.Counter(),'semantic_families':collections.Counter(),'structural_variants':collections.Counter(),'representatives':[],'likely_pipeline_location':source,'root_cause_confirmed':False,'bank_credible':None,'local_model_agrees':None,'disposition':'unadjudicated'})
   cluster['count']+=1;cluster['categories'][r['category']]+=1;cluster['semantic_families'][r['semantic_family']]+=1;cluster['structural_variants'][r['structure_id']]+=1
   if len(cluster['representatives'])<3:cluster['representatives'].append(r)
 for c in clusters.values():
  denominator=sum(summary['per_family'][f]['total'] for f in c['semantic_families']);c['relevant_family_denominator']=denominator;c['percent_relevant_families']=round(100*c['count']/denominator,3)
 ranked=sorted(clusters.values(),key=lambda c:(c['severity_candidate'],-c['count']));(out/'root-cause-candidates.json').write_text(json.dumps(ranked,indent=2))
 lines=['# 250K baseline: deterministic evidence','', '**Status: full rules-path measurement; semantic adjudication and confirmed root causes remain separate.**','',f"Base commit: `{freeze['base_commit']}` on `{freeze['branch']}`. The working source was dirty; the frozen source hash, not the commit alone, identifies the product.",'',f"Working source SHA-256: `{freeze['source_tree_sha256']}`",f"Parser source SHA-256: `{freeze['parser_source_sha256']}`",f"Bank SHA-256: `{freeze['bank_sha256']}`",f"Probe SHA-256: `{execution['probe_sha256']}`",f"Evaluator SHA-256: `{summary['evaluator_sha256']}`",'',f"Processed: {summary['total']:,}. Agreement on measured checks: {summary['agreement_on_measured_checks']:,}; disagreement: {summary['disagreement_on_measured_checks']:,}.",'',f"Candidate severities: {json.dumps(summary['severity_candidates'])}. These are not confirmed P0/P1/P2 product-defect counts.",'','Runtime: '+execution['runtime']+'. Fixed reference '+execution['reference_instant']+'.','',summary['warning'],'','## Top 20 candidate root-cause families','','| Family | Candidate severity | Cases | % of relevant families |','|---|---|---:|---:|']
 for c in ranked[:20]:lines.append(f"| {c['candidate_family']} | {c['severity_candidate']} | {c['count']:,} | {c['percent_relevant_families']} |")
 lines+=['','## Per-category results','','| Category | Cases | Agreement on measured checks | Fully measured |','|---|---:|---:|---:|']
 for cat,c in sorted(categories.items()):lines.append(f"| {cat} | {c['total']:,} | {c['agreement_on_measured_checks']:,} | {c['fully_measured']:,} |")
 lines+=['','## Field checks','','| Field | Evaluated items | Passed |','|---|---:|---:|']
 for field,c in sorted(summary['field_checks'].items()):lines.append(f"| {field} | {c['evaluated']:,} | {c['passed']:,} |")
 lines+=['','## Adjudication and next steps','',f"Bank-marked ambiguous cases: {summary['bank_marked_ambiguity']:,}. Independently adjudicated ambiguity and questionable-contract totals are not yet established. Local-model statistics must cite their sample denominator; do not extrapolate them to 250K.",'','Investigate P0 attribution, actionability, cancellation and conditional candidates first, then P1 entity, segmentation, location and temporal families. Treat textual overlap as a triage signal; verify semantic equivalence before calling lexical differences defects. Extract fixtures from saved evidence and preserve cancellation/conditional regression gates. No success claim or product-fix completion follows from this report.','', 'Simulator NaturalLanguage OtherWord failures remain an infrastructure issue. The host health check passed. No simulator repair or parser accommodation was attempted.']
 (out/'baseline-report.md').write_text('\n'.join(lines)+'\n')
if __name__=='__main__':main()
