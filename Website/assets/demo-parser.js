/* Pure, conservative browser preview. It never schedules, persists, or contacts a service. */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.SpeakItPreview = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  var words = {one:1,two:2,three:3,four:4,five:5,six:6,seven:7,eight:8,nine:9,ten:10,eleven:11,twelve:12};
  var wordHour = Object.keys(words).join('|');
  var clockPattern = new RegExp('\\b(?:at\\s+)?(\\d{1,2}(?::\\d{2})?|'+wordHour+')\\s*(a\\.?m\\.?|p\\.?m\\.?)\\b|\\bat\\s+(\\d{1,2}(?::\\d{2})?|'+wordHour+')\\b', 'i');
  var placePattern = /\bwhen (?:i|we) (get|arrive|reach|leave) (?:to |at )?(home|work|the office|the house)\b/i;
  var dayPattern = /\b(tomorrow|today|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i;
  var temporal = /\b(tomorrow|today|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next|later|morning|afternoon|evening|noon|midnight|week|weekend|month|year|every|daily|weekly|before|after|until|in \d+|on the \d+|by the \d+|at (?:\d|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve))\b|\d{1,2}:\d{2}|\b\d{1,2}\s*[ap]\.?m\.?\b/i;
  var unsupportedTime = /\b(next|later|morning|afternoon|evening|noon|midnight|week|weekend|month|year|every|daily|weekly|before|after|until|in \d+|on the \d+|by the \d+)\b|\b\d{1,2}[\/-]\d{1,2}\b|\b(january|february|march|april|may|june|july|august|september|october|november|december)\b/i;
  var filler = /^(?:please\s+)?(?:remind me to|remember to|note to self[:,]?|i need to|i should|don't forget to|do not forget to)\s+/i;
  var action = /^(?:please\s+)?(?:call|book|buy|email|send|pay|renew|chase|collect|pick up|cancel|move|ask|tell|check|fix|order|return|post|drop off|reply|confirm|reschedule|take|bring|finish|water|feed|submit|text|walk|read|clean|write|put|get|visit|make|do)\b/i;
  var multiAction = /(?:[.!?]\s+|\band(?: then)?\s+|[,;]\s*)(?:remind me|call|book|buy|email|send|pay|renew|collect|pick up|ask|check|order|take|bring|finish|text|water|feed|submit|write)\b/i;
  var personFact = /^(?:oh[, ]+)?[A-Z][a-z]+\s+(?:prefers|likes|loves|hates|avoids|drinks|works|lives|studies|is|was|has|takes)\b|\bpartner\b|\b[A-Z][a-z]+['’]s\b/;
  var reference = /\b(code|password|parking|gate|level|row|key|phone number|number is)\b|\+?\d[\d ()\-.]{6,}\d|[\w.+-]+@[\w-]+\.[\w.-]+/i;
  function cap(value) { return value.charAt(0).toUpperCase() + value.slice(1); }
  function base(original) {
    return {original:original,title:original,destination:'Memory',kind:'Note',section:'Saved detail',detail:'Kept as a note',summary:'A detail to find again, in your own words.',caveat:'This is a preview. Nothing has been saved.',isTask:false,needsReview:false};
  }
  function review(original, reason) {
    var result=base(original);
    result.destination='Keep it for review';result.kind='Needs review';result.section='Original thought';result.detail='No date or reminder assumed';
    result.summary=reason;result.caveat='This simplified preview leaves your words intact. It does not schedule a reminder.';result.needsReview=true;
    return result;
  }
  function parse(text) {
    var original=String(text == null ? '' : text).trim();
    if (!original) return null;
    if (original.length>240) return review(original,'Try one short thought at a time in this preview.');
    var clean=original.replace(/\s+/g,' ').replace(/[.!?]+$/,'');
    var result=base(original);
    if (/^(?:idea\b|what if\b|maybe we\b|we should\b)/i.test(clean)) {
      result.destination='Memory · Ideas';result.kind='Idea';result.summary='An idea worth keeping, without turning it into a task.';return result;
    }
    var taskText=clean.replace(filler,'');
    if (multiAction.test(taskText)) return review(original,'There may be more than one thought here. Try them one at a time.');
    if (/^(?:don't|do not|stop|delete|change|actually|instead|cancel my|cancel the reminder)\b/i.test(taskText)) return review(original,'This sounds like a change or instruction. The preview won’t act on it.');
    // A fact mentioning a time is still a fact, not a reminder.
    if (!action.test(taskText)) {
      if (reference.test(clean)) {result.destination='Memory · Reference';result.kind='Reference';result.summary='A useful detail, ready to look up later.';}
      else if(personFact.test(clean)) {result.destination='Memory · People';result.kind='People';result.summary='A detail about someone, kept where you can find it.';}
      else if (/\bremind\b|\bwhen i\b/i.test(clean)) return review(original,'This preview can’t confidently interpret that instruction. Your words stay intact.');
      return result;
    }
    var place=taskText.match(placePattern),day=taskText.match(dayPattern),clock=taskText.match(clockPattern);
    if(place && temporal.test(taskText.replace(place[0],''))) return review(original,'This names both a place and a time. Choose one trigger in the app.');
    if(unsupportedTime.test(taskText)) return review(original,'That timing needs more interpretation than this preview supports.');
    result.isTask=true;result.destination='Today';result.kind='Task';result.section='When you have time';result.detail='No date';result.summary='Something to do, kept in Today without inventing a deadline.';
    result.caveat='This is a preview. No task or reminder has been saved.';
    var title=taskText;
    if (place) {
      var name=/home|house/i.test(place[2])?'Home':'Work';
      result.kind='Place reminder';result.section='Place reminder';result.detail=(/leave/i.test(place[1])?'Leaving ':'Arriving at ')+name;
      result.summary='A reminder for the place you named.';
      result.caveat='In the app, set '+name+' and allow location and notifications. This preview does not monitor your location.';
      title=title.replace(place[0],'');
    } else if(day||clock||temporal.test(taskText)) {
      if(!clock && temporal.test(taskText.replace(day?day[0]:/$^/,''))) return review(original,'That timing needs more interpretation than this preview supports.');
      var parts=[];
      if(day){parts.push(cap(day[1].toLowerCase()));title=title.replace(day[0],'');}
      if(clock){
        var raw=(clock[1]||clock[3]).toLowerCase(),bits=raw.split(':'),hour=words[raw]||Number(bits[0]),minute=bits.length>1?Number(bits[1]):0;
        var suffix=clock[2]?clock[2].replace(/\./g,'').toUpperCase():'';
        if(minute>59||hour>23||(suffix&&(hour<1||hour>12))) return review(original,'That clock time needs checking. No time has been assumed.');
        if(!suffix && hour>=1&&hour<=12) return review(original,'Did you mean AM or PM? Add it so the time is unambiguous.');
        if(!suffix){suffix=hour>=12?'PM':'AM';hour=(hour%12)||12;}
        parts.push(hour+':'+String(minute).padStart(2,'0')+' '+suffix);title=title.replace(clock[0],'');
      }
      if(!day) return review(original,'Which day did you mean? Add a day such as “tomorrow”.');
      result.detail=parts.join(', ');result.section='Scheduled';result.kind=clock?'Reminder':'Dated task';
      result.summary=clock?'A reminder for the time you named.':'A task for the day you named. No reminder time assumed.';
      result.caveat='This is a preview. No reminder has been scheduled.';
    }
    title=title.replace(/\s+/g,' ').replace(/\s+(?:at|on|by)$/i,'').replace(/[,\s]+$/,'').trim();
    result.title=cap(title||taskText);
    return result;
  }
  return Object.freeze({parse:parse});
});
