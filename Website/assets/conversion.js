/* All visitor text stays in the page. Only browser speech can use a remote service. */
(function () {
  'use strict';
  var q=function(selector){return document.querySelector(selector);};
  var all=function(selector){return Array.from(document.querySelectorAll(selector));};
  var motion=window.matchMedia('(prefers-reduced-motion: reduce)');
  // A closed event vocabulary for a future analytics adapter. No network, storage,
  // IDs, URLs, referrers, transcripts, or free-form values enter these events.
  var events=new Set(['acquisition_clicked','demo_started','demo_result_shown','demo_review_shown','acquisition_after_demo','story_replayed']);
  var placements=new Set(['header','hero','demo','closing']);
  var methods=new Set(['example','text','voice']);
  var hasDemoResult=false;
  function track(name,context){
    if(!events.has(name)||navigator.doNotTrack==='1'||navigator.globalPrivacyControl===true)return;
    var detail={name:name};
    if(placements.has(context))detail.placement=context;
    if(methods.has(context))detail.method=context;
    document.dispatchEvent(new CustomEvent('speak-it:conversion',{detail:Object.freeze(detail)}));
  }
  var meta=q('meta[name="speak-it-app-store-url"]');
  var store='';
  try {var url=new URL(meta?meta.content:'');if(url.protocol==='https:'&&url.hostname==='apps.apple.com'&&/\/id\d+/.test(url.pathname))store=url.href;}catch(e){/* Prelaunch is the default. */}
  all('[data-acquire]').forEach(function(link){
    if(store){link.href=store;link.textContent='Get Speak It for iPhone ↗';}
    link.addEventListener('click',function(){track('acquisition_clicked',link.dataset.placement);if(hasDemoResult)track('acquisition_after_demo',link.dataset.placement);});
  });
  if(store){
    q('[data-availability]').textContent='For iPhone';q('[data-closing-eyebrow]').textContent='For iPhone';
    q('[data-closing-copy]').textContent='Start with your first 10 captures, free.';
    all('[data-email-note],[data-prelaunch-pricing]').forEach(function(el){el.hidden=true;});
  }
  /* The annual launch discount, and only the annual one. It mirrors
     SummerLaunchSale in the app, which strikes a regular price through for the
     annual plan and never for monthly — a page claiming a monthly discount the
     sheet does not show is a refund. Empty means no offer, which is the state
     to stay in until App Store Connect really is charging the lower price; the
     page then renders exactly as authored. No end date is published on purpose,
     so the offer can be ended or extended without the page having lied. */
  var LAUNCH_ANNUAL_PRICE='';
  if(LAUNCH_ANNUAL_PRICE){
    var wasPrice=q('[data-annual-was]'),nowPrice=q('[data-annual-price]');
    if(wasPrice&&nowPrice){
      wasPrice.textContent=nowPrice.textContent;
      wasPrice.hidden=false;
      nowPrice.textContent=LAUNCH_ANNUAL_PRICE;
      q('[data-launch-note]').hidden=false;
    }
  }
  // No looping spectacle: the narrative plays once and leaves a readable result.
  var visual=q('[data-story]'),story=q('.story'),replay=q('[data-replay]');
  var storyTimer;
  function playStory(manual){
    if(motion.matches)return;
    clearTimeout(storyTimer);story.classList.remove('is-playing');void story.offsetWidth;story.classList.add('is-playing');
    if(manual)track('story_replayed');
    storyTimer=setTimeout(function(){story.classList.remove('is-playing');},3900);
  }
  replay.addEventListener('click',function(){playStory(true);});
  if('IntersectionObserver' in window){
    var played=false;
    var observer=new IntersectionObserver(function(entries){entries.forEach(function(entry){visual.classList.toggle('is-offscreen',!entry.isIntersecting);if(entry.isIntersecting&&!played){played=true;playStory(false);}});},{threshold:.2});
    observer.observe(visual);
  }else playStory(false);
  document.addEventListener('visibilitychange',function(){document.documentElement.classList.toggle('motion-paused',document.hidden);if(document.hidden)cancelVoice();});
  motion.addEventListener('change',function(){if(motion.matches){clearTimeout(storyTimer);story.classList.remove('is-playing');}});

  var examples={reminder:'Call Mum tomorrow at 5 PM.',place:'Take the bins out when I get home.',memory:'Daniel prefers oat milk.'};
  var panel=q('[data-result-panel]'),input=q('#demo-input'),form=q('[data-demo-form]'),announcement=q('[data-result-announcement]');
  var resultAnimation;
  function showResult(text,method){
    var result=window.SpeakItPreview.parse(text);if(!result)return;
    q('[data-result-kicker]').textContent=result.needsReview?'Your thought, kept intact':'Preview result';
    q('[data-destination]').textContent=result.destination;q('[data-result-summary]').textContent=result.summary;
    q('[data-result-section]').textContent=result.section;q('[data-result-kind]').textContent=result.kind;
    q('[data-result-title]').textContent=result.title;q('[data-result-detail]').textContent=result.detail;
    q('[data-result-original]').textContent='“'+result.original+'”';q('[data-result-caveat]').textContent=result.caveat;
    q('[data-result-icon]').classList.toggle('task-circle--memory',!result.isTask);
    panel.classList.remove('is-new');void panel.offsetWidth;panel.classList.add('is-new');
    clearTimeout(resultAnimation);resultAnimation=setTimeout(function(){panel.classList.remove('is-new');},400);
    announcement.textContent=result.destination+'. '+result.title+'. '+result.detail+'. '+result.caveat;
    hasDemoResult=true;track(result.needsReview?'demo_review_shown':'demo_result_shown',method);
    // Preserve desktop focus; on narrow screens move to the result so it cannot
    // land beneath a keyboard or another screenful of controls.
    if(window.matchMedia('(max-width:760px)').matches){
      panel.focus({preventScroll:true});panel.scrollIntoView({block:'start',behavior:'auto'});
    }
  }
  function selectExample(key){all('[data-example]').forEach(function(el){var selected=el.dataset.example===key;el.classList.toggle('is-selected',selected);el.setAttribute('aria-pressed',String(selected));});}
  all('[data-example]').forEach(function(button){button.addEventListener('click',function(){cancelVoice();selectExample(button.dataset.example);track('demo_started','example');showResult(examples[button.dataset.example],'example');});});
  form.addEventListener('submit',function(event){event.preventDefault();cancelVoice();if(!input.value.trim()){input.setCustomValidity('Enter a thought to preview.');input.reportValidity();return;}input.setCustomValidity('');selectExample(null);track('demo_started','text');showResult(input.value,'text');});
  input.addEventListener('input',function(){input.setCustomValidity('');});

  var mic=q('[data-mic]'),micLabel=q('[data-mic-label]'),status=q('[data-voice-status]');
  var Recognition=window.SpeechRecognition||window.webkitSpeechRecognition;
  var recognition=null,session=0,voiceTimer=null;
  function finishVoice(){clearTimeout(voiceTimer);voiceTimer=null;recognition=null;mic.setAttribute('aria-pressed','false');micLabel.textContent='Speak instead';}
  function cancelVoice(){session++;if(recognition){try{recognition.abort();}catch(e){/* Already ended. */}}finishVoice();status.textContent='';}
  if(!Recognition||!window.isSecureContext){mic.hidden=true;status.textContent='Voice preview isn’t available in this browser. Try typing or an example.';}
  else{
    mic.setAttribute('aria-pressed','false');
    mic.addEventListener('click',function(){
      if(recognition){cancelVoice();status.textContent='Voice preview stopped.';return;}
      var current=++session,transcript='',failed=false,started=false;
      try{recognition=new Recognition();recognition.lang='en-US';recognition.interimResults=true;recognition.continuous=false;}catch(e){finishVoice();status.textContent='Voice isn’t available here. Try typing instead.';return;}
      var active=recognition;
      mic.setAttribute('aria-pressed','true');micLabel.textContent='Cancel listening';status.textContent='Allow microphone access to speak, or cancel and type.';
      function same(){return current===session;}
      active.onstart=function(){if(!same())return;started=true;clearTimeout(voiceTimer);status.textContent='Listening. Say one thought in English.';track('demo_started','voice');voiceTimer=setTimeout(function(){if(same())try{active.stop();}catch(e){cancelVoice();}},20000);};
      active.onresult=function(event){if(!same())return;var interim='';for(var i=event.resultIndex;i<event.results.length;i++){var r=event.results[i];if(r.isFinal)transcript+=(transcript?' ':'')+r[0].transcript;else interim+=r[0].transcript;}status.textContent=interim||'Finishing your thought…';};
      active.onerror=function(event){if(!same())return;failed=true;var errors={'not-allowed':'Microphone access wasn’t granted. Try typing or an example.','service-not-allowed':'Voice isn’t available here. Try typing or an example.','no-speech':'No speech heard. Try again or type a thought.','network':'The speech service couldn’t connect. Try typing instead.','aborted':'Voice preview stopped.'};status.textContent=errors[event.error]||'Voice didn’t complete. Try typing or an example.';finishVoice();};
      active.onend=function(){if(!same())return;finishVoice();if(failed)return;if(transcript.trim()){status.textContent='Voice preview ready.';selectExample(null);showResult(transcript,'voice');}else status.textContent=started?'No speech heard. Try again or type a thought.':'Voice didn’t start. Try typing instead.';};
      try{active.start();voiceTimer=setTimeout(function(){if(!same()||started)return;cancelVoice();status.textContent='Microphone access is still unavailable. Try typing instead.';},10000);}catch(e){finishVoice();status.textContent='Voice isn’t available here. Try typing instead.';}
    });
  }
  window.addEventListener('pagehide',cancelVoice);
})();
