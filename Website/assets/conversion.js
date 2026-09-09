/* All visitor text stays in the page. Only browser speech can use a remote service. */
(function () {
  'use strict';
  var q=function(selector){return document.querySelector(selector);};
  var all=function(selector){return Array.from(document.querySelectorAll(selector));};
  var motion=window.matchMedia('(prefers-reduced-motion: reduce)');
  // A closed event vocabulary for a future analytics adapter. No network, storage,
  // IDs, URLs, referrers, transcripts, or free-form values enter these events.
  var events=new Set(['acquisition_clicked','demo_started','demo_result_shown','demo_review_shown','acquisition_after_demo']);
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
  var downloadDialog=q('[data-download-dialog]');
  all('[data-acquire]').forEach(function(link){
    if(store){link.href=store;link.textContent=link.dataset.placement==='header'?'Download ↗':'Download for iPhone ↗';}
    link.addEventListener('click',function(event){if(!store&&downloadDialog&&typeof downloadDialog.showModal==='function'){event.preventDefault();downloadDialog.showModal();}track('acquisition_clicked',link.dataset.placement);if(hasDemoResult)track('acquisition_after_demo',link.dataset.placement);});
  });
  if(downloadDialog){
    downloadDialog.addEventListener('click',function(event){if(event.target===downloadDialog){var rect=downloadDialog.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)downloadDialog.close();}});
    q('[data-close-download]').addEventListener('click',function(){downloadDialog.close();});
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

  /* ————————————————————————— the thought ring —————————————————————————
     A day's worth of unsorted thoughts turning around the sentence that says
     what to do with them. Each bubble is read once from the custom properties
     it is authored with and then positioned from a single transform per frame,
     so the entrance scatter, the idle drift and the turn compose into one
     write instead of fighting each other over separate properties.

     Everything here is decoration: the layer is aria-hidden, the hero reads and
     converts without it, and it is not drawn at all when the reader has asked
     for less motion or the section is off screen.
     ————————————————————————————————————————————————————————————————— */
  var hero=q('.hero'),orbit=q('[data-orbit]');
  var TURN=52000;                 /* ms for the ring to come all the way round */
  var HOLD=260,STEP=64,FLIGHT=940; /* the entrance: a beat, then one at a time */
  var RAD=Math.PI/180;
  function clamp(n,lo,hi){return n<lo?lo:n>hi?hi:n;}
  /* a small overshoot at the end of the flight, so a thought arrives the way a
     thing with weight arrives rather than easing politely to a stop */
  function num(style,name,fallback){var v=parseFloat(style.getPropertyValue(name));return isNaN(v)?fallback:v;}

  var bubbles=all('.bubble').map(function(el,n){
    var cs=getComputedStyle(el);
    var i=num(cs,'--i',n);
    /* deterministic per-bubble character: no two bob, sway, tilt or spin the
       same way, so the ring never falls into step with itself */
    var seed=Math.sin(i*12.9898+n*78.233)*43758.5453;
    var rnd=seed-Math.floor(seed);
    var alt=i%2?1:-1;
    return {
      el:el,
      a:num(cs,'--a',0),rr:num(cs,'--rr',1),s:num(cs,'--s',1),i:i,
      halfW:0,halfH:0,
      bobA:6+rnd*6,  bobS:0.5+rnd*0.45,  bobP:rnd*6.28,
      swayA:4+(1-rnd)*5, swayS:0.32+rnd*0.3, swayP:(1-rnd)*6.28,
      tilt:alt*(0.8+rnd*1.9),
      spin:alt*(26+rnd*30)   /* how much it turns on the way out */
    };
  });

  var RX=0,RY=0,keepX=0,keepY=0,turnScale=1,born=0,frame=0,ringVisible=true;

  /* The ellipse is asked of the bubbles rather than assumed: it is the widest
     ring that still keeps every thought inside the section. The ring turns, so
     each one takes its turn at the widest point and the narrowest fit wins for
     all of them — a sentence is not a fixed width, and on a phone it is the
     text that decides how big the ring can be. */
  function measure(){
    if(!orbit||!bubbles.length)return;
    hero.style.minHeight=(q('.hero__copy').offsetHeight+280)+'px';
    var w=orbit.clientWidth||window.innerWidth;
    var h=orbit.clientHeight||600;
    var margin=32;
    var vertical=h/2;
    var readable=w/2;
    for(var n=0;n<bubbles.length;n++){
      var b=bubbles[n];
      if(!b.el.offsetParent&&b.el.offsetWidth===0)continue;  /* dropped by CSS at this width */
      b.halfW=Math.hypot(b.el.offsetWidth,b.el.offsetHeight)*b.s/2;
      b.halfH=(b.el.offsetHeight+b.el.offsetWidth*0.07)*b.s/2;
      readable=Math.min(readable,(w/2-b.halfW-margin-b.swayA)/b.rr);
      vertical=Math.min(vertical,(h/2-b.halfH-margin-b.bobA)/b.rr);
    }
    /* The box the words actually ink, not the box they are laid out in. The
       copy container is the full measure at every width, but the message is
       centred inside it and much narrower than that on a desktop — sizing the
       keep-out to the container would push the ring off the page to protect
       whitespace. Ranges give the real extents, so this tracks the type at
       whatever size it is set. */
    var box=inkedBox(q('.hero__copy'),orbit);
    keepX=box.halfW+18;
    keepY=box.halfH+18;
    /* Wide enough that the sides clear the message where there is room for
       them to, tall enough that the top and bottom arcs clear it everywhere. */
    RX=Math.max(0,readable);
    /* Far enough past the message that a thought coming over the top or under
       the bottom is at full strength rather than half-faded by the rule below —
       on a phone those two arcs are the only places the ring can be seen at
       all, so they have to be worth looking at. */
    RY=Math.max(0,Math.min(vertical,Math.max(RX*0.6,keepY+70)));
    /* A bubble is the same size on a phone as on a desktop while the screen is
       a third of the width, so the same angle of tilt reads as a much bigger
       gesture. It is dialled back rather than dropped — the turn is the point. */
    turnScale=w<900?0.45:1;
  }

  /* Nothing is drawn on the message. A thought whose own edge reaches the
     words fades out and comes back on the far side, which is what makes the
     ring work on a phone, where the type takes most of the screen and there is
     no ellipse that goes round it. The thought's own half-size is in the
     measure, because it is the capsule that overlaps the sentence, not the
     point it is positioned at. 1 clear of the words, 0 across them. */
  function clear(x,y,halfW,halfH){
    var d=Math.max((Math.abs(x)-halfW)/keepX,(Math.abs(y)-halfH)/keepY);
    /* d reaches 1 as the capsule's near edge meets the box, so the ramp starts
       just inside it and finishes just outside: anything actually over the
       words is gone, and anything clear of them is at full strength. */
    return clamp((d-0.88)/0.26,0,1);
  }

  /* The union of the message's own line boxes, measured about the ring's
     centre. Each block is measured with a Range so a centred line reports the
     width of its words rather than the width of the column. */
  function inkedBox(copy,host){
    var halfW=40,halfH=40;
    if(!copy||!host)return {halfW:halfW,halfH:halfH};
    var frame=host.getBoundingClientRect();
    var cx=frame.left+frame.width/2,cy=frame.top+frame.height/2;
    var range=document.createRange();
    Array.prototype.forEach.call(copy.children,function(block){
      var parts=block.tagName==='H1'?block.children:[block];
      Array.prototype.forEach.call(parts,function(part){
        range.selectNodeContents(part);
        var r=range.getBoundingClientRect();
        if(!r.width||!r.height)return;
        halfW=Math.max(halfW,Math.abs(r.left-cx),Math.abs(r.right-cx));
        halfH=Math.max(halfH,Math.abs(r.top-cy),Math.abs(r.bottom-cy));
      });
    });
    return {halfW:halfW,halfH:halfH};
  }

  function paint(now){
    frame=0;
    if(!born)born=now;
    var t=now/1000;
    var turn=(now%TURN)/TURN*-360;
    var elapsed=now-born;
    var settled=true;
    for(var n=0;n<bubbles.length;n++){
      var b=bubbles[n];
      /* out of the indicator, one after another */
      var e=1-Math.pow(1-clamp((elapsed-HOLD-b.i*STEP)/FLIGHT,0,1),3);
      if(e<1)settled=false;
      var ang=(b.a+turn)*RAD;
      var bob=Math.sin(t*b.bobS+b.bobP);
      var sway=Math.sin(t*b.swayS+b.swayP);
      var x=RX*b.rr*e*Math.cos(ang)+sway*b.swayA;
      var y=RY*b.rr*e*Math.sin(ang)+bob*b.bobA;
      var rot=(b.tilt+sway*0.7+(1-e)*b.spin)*turnScale;
      var sc=b.s*(0.06+0.94*e);
      b.el.style.transform='translate('+x.toFixed(1)+'px,'+y.toFixed(1)+'px) rotate('+rot.toFixed(2)+'deg) scale('+sc.toFixed(3)+')';
      b.el.style.opacity=(Math.min(1,e*2.6)*clear(x,y,b.halfW,b.halfH)).toFixed(3);
    }
    if(ringVisible&&!document.hidden)frame=requestAnimationFrame(paint);
    else if(!settled)frame=requestAnimationFrame(paint);   /* let the entrance finish */
  }

  /* The finished state, with nothing moving: every thought at rest on the ring
     where it was authored. It is what a reader who has asked for reduced motion
     gets, and it is a ring rather than an empty hero because the thoughts are
     the picture, not the animation. */
  function settle(){
    for(var n=0;n<bubbles.length;n++){
      var b=bubbles[n],ang=b.a*RAD;
      var sx=RX*b.rr*Math.cos(ang),sy=RY*b.rr*Math.sin(ang);
      b.el.style.transform='translate('+sx.toFixed(1)+'px,'+sy.toFixed(1)+'px) rotate('+(b.tilt*turnScale).toFixed(2)+'deg) scale('+b.s+')';
      b.el.style.opacity=clear(sx,sy,b.halfW,b.halfH).toFixed(3);
    }
  }
  function start(){
    if(!bubbles.length)return;
    measure();
    if(motion.matches){if(frame)cancelAnimationFrame(frame);frame=0;settle();return;}
    if(!frame)frame=requestAnimationFrame(paint);
  }
  function stop(){if(frame)cancelAnimationFrame(frame);frame=0;}

  if(orbit){
    start();
    if('ResizeObserver' in window)new ResizeObserver(function(){measure();if(motion.matches)settle();}).observe(q('.hero__copy'));
    var resizeTimer;
    window.addEventListener('resize',function(){
      clearTimeout(resizeTimer);
      resizeTimer=setTimeout(function(){measure();if(motion.matches)settle();},160);
    });
    motion.addEventListener('change',function(){stop();born=0;start();});
    /* Nothing is painted for a hero nobody is looking at. */
    if('IntersectionObserver' in window&&hero){
      new IntersectionObserver(function(entries){
        entries.forEach(function(entry){
          ringVisible=entry.isIntersecting;
          hero.classList.toggle('is-offscreen',!entry.isIntersecting);
          if(ringVisible&&!motion.matches&&!frame&&!document.hidden)frame=requestAnimationFrame(paint);
          if(!ringVisible)stop();
        });
      },{threshold:0}).observe(hero);
    }
  }
  document.addEventListener('visibilitychange',function(){
    document.documentElement.classList.toggle('motion-paused',document.hidden);
    if(document.hidden){stop();cancelVoice();}
    else if(ringVisible&&!motion.matches&&!frame)frame=requestAnimationFrame(paint);
  });

  /* ————————————————————————————— try it ————————————————————————————— */
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

  /* The microphone lives inside the field, where a phone keyboard puts one.
     Where the browser has no speech service it is removed rather than left as a
     dead control, and the field keeps working on its own. */
  var mic=q('[data-mic]'),micLabel=q('[data-mic-label]'),status=q('[data-voice-status]');
  var Recognition=window.SpeechRecognition||window.webkitSpeechRecognition;
  var recognition=null,session=0,voiceTimer=null;
  function finishVoice(){clearTimeout(voiceTimer);voiceTimer=null;recognition=null;mic.setAttribute('aria-pressed','false');micLabel.textContent='Speak';}
  function cancelVoice(){session++;if(recognition){try{recognition.abort();}catch(e){/* Already ended. */}}finishVoice();status.textContent='';}
  if(!Recognition||!window.isSecureContext){mic.hidden=true;status.textContent='Speaking isn’t available in this browser. Type a thought or tap an example.';}
  else{
    mic.setAttribute('aria-pressed','false');
    mic.addEventListener('click',function(){
      if(recognition){cancelVoice();status.textContent='Stopped listening.';return;}
      var current=++session,transcript='',failed=false,started=false;
      try{recognition=new Recognition();recognition.lang='en-US';recognition.interimResults=true;recognition.continuous=false;}catch(e){finishVoice();status.textContent='Speaking isn’t available here. Try typing instead.';return;}
      var active=recognition;
      mic.setAttribute('aria-pressed','true');micLabel.textContent='Stop';status.textContent='Allow microphone access to speak, or stop and type.';
      function same(){return current===session;}
      active.onstart=function(){if(!same())return;started=true;clearTimeout(voiceTimer);status.textContent='Listening. Say one thought in English.';track('demo_started','voice');voiceTimer=setTimeout(function(){if(same())try{active.stop();}catch(e){cancelVoice();}},20000);};
      active.onresult=function(event){if(!same())return;var interim='';for(var i=event.resultIndex;i<event.results.length;i++){var r=event.results[i];if(r.isFinal)transcript+=(transcript?' ':'')+r[0].transcript;else interim+=r[0].transcript;}status.textContent=interim||'Finishing your thought…';};
      active.onerror=function(event){if(!same())return;failed=true;var errors={'not-allowed':'Microphone access wasn’t granted. Try typing or an example.','service-not-allowed':'Speaking isn’t available here. Try typing or an example.','no-speech':'No speech heard. Try again or type a thought.','network':'The speech service couldn’t connect. Try typing instead.','aborted':'Stopped listening.'};status.textContent=errors[event.error]||'That didn’t complete. Try typing or an example.';finishVoice();};
      active.onend=function(){if(!same())return;finishVoice();if(failed)return;if(transcript.trim()){status.textContent='Heard you.';input.value=transcript.trim();selectExample(null);showResult(transcript,'voice');}else status.textContent=started?'No speech heard. Try again or type a thought.':'That didn’t start. Try typing instead.';};
      try{active.start();voiceTimer=setTimeout(function(){if(!same()||started)return;cancelVoice();status.textContent='Microphone access is still unavailable. Try typing instead.';},10000);}catch(e){finishVoice();status.textContent='Speaking isn’t available here. Try typing instead.';}
    });
  }
  window.addEventListener('pagehide',cancelVoice);
})();
