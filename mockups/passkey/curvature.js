'use strict';

const $ = selector => document.querySelector(selector);
const gravityStudy = document.body.dataset.study === 'gravity';
const concepts = gravityStudy ? [
  { name: 'Quiet Tide', description: 'The closest revision to the original Gravity Well. One restrained ripple travels from your click, laying down a smooth, quiet basin.', geometry: 'A narrow raised wavefront carries the bend outward. Pixels ahead of it remain exactly flat; those behind it gently settle into the click-centered well.' },
  { name: 'Twin Ripple', description: 'A second, smaller ripple follows the first. A subtle double beat makes the interaction feel deliberate without making the entire page oscillate.', geometry: 'Two separated geometric crests travel outward from the same click. The second follows 420 milliseconds later; both resolve into one steady gravity well.' },
  { name: 'Elastic Wake', description: 'The website behaves like a flexible membrane. The wave leaves a small, damped rebound behind it before the page becomes still.', geometry: 'Each point begins moving only when the wave reaches it. A local spring-like oscillation decays independently behind the travelling front.' },
  { name: 'Raised Rim', description: 'A more sculptural take. A pronounced lip rises around the advancing well, making the travelling curvature unmistakable.', geometry: 'A positive crest pushes the mesh upward and outward just before the concave basin arrives. The page texture and its shading follow the actual displaced geometry.' },
  { name: 'Deep Undertow', description: 'First a light ripple, then a slower, deeper pull. The two-stage descent gives the well more weight and a slightly more cinematic pace.', geometry: 'The first front forms a shallow basin. A broad second front arrives 620 milliseconds later and draws the already-curved surface deeper into the same well.' }
] : [
  { name: 'Gravity Well', category: 'Attraction', description: 'Authentication acquires mass. The website sinks into a deep, smooth basin while the prompt stays suspended above it.', geometry: 'Text, images, rules, and the window edges follow a concave 3D surface. Perspective compresses the center; directional shading makes the depth tangible.' },
  { name: 'Orbital Shear', category: 'Torsion', description: 'The page twists around the sign-in point, as if the surrounding space has been gently rotated. A controlled torsion, not a spinning overlay.', geometry: 'The actual website texture is carried around a localized vortex. The center recedes into depth while the outer edges stay comparatively anchored.' },
  { name: 'Saddle Space', category: 'Topology', description: 'Opposite axes curve in opposite directions. The page becomes a sculptural saddle beneath a perfectly level authentication plane.', geometry: 'The horizontal axis rises as the vertical axis sinks. Opposing corners lift and recede, bending every line on the page into the same continuous surface.' },
  { name: 'Living Fold', category: 'Material', description: 'The browser feels like a flexible sheet. Both sides fold away from a central spine, making a quiet stage for authentication.', geometry: 'A cylindrical bend foreshortens both page halves. The outer edges turn away in depth, with a narrow, curved spine remaining near the viewer.' },
  { name: 'Spatial Squeeze', category: 'Compression', description: 'Space makes room for the prompt. The middle of the website contracts into an hourglass while the top and bottom remain broad.', geometry: 'A nonuniform horizontal compression bends straight columns inward. A shallow vertical arch adds depth, rather than merely scaling the page down.' }
];

const canvas = $('#surface');
const stage = $('#stage');
const prompt = $('#prompt');
const reducedPreference = matchMedia('(prefers-reduced-motion: reduce)');
$('#reduced').checked = reducedPreference.matches;
let mode = 0;
let method = 'passkey';
let phase = 'idle';
let started = 0;
let releaseStart = 0;
let releaseAmount = 0;
let amount = 0;
// Default source: the center of the fictional page's sign-in button, in texture UV coordinates.
let origin = [.836, .795];
let waveAge = 0;
let raf = 0;
let width = 1;
let height = 1;
let contextLost = false;
let gl;
let program;
let vertexBuffer;
let texture;
let vertexCount;
let uniforms;

const vertexSource = `
precision mediump float;
attribute vec2 uv;
uniform float aspect, amount, mode, study, age;
uniform vec2 origin;
varying vec2 vUV;
varying float vLight;
varying float vWave;
float crest(float local, float delay, float band) {
  float x = (local-delay)/band;
  return exp(-x*x) * smoothstep(0.0,.18,age);
}
vec3 gravitySurface(vec2 p) {
  vec2 center = (origin-.5)*2.0*vec2(aspect,1.0);
  vec2 q = p-center;
  float r = length(q);
  float local = age-r/1.15;
  float arrived = smoothstep(0.0,.34,local);
  float basin = exp(-dot(q,q)*.64);
  float wave = .14*crest(local,.12,.13);
  float sink = .98*arrived;
  if (mode > .5 && mode < 1.5) {
    wave += .10*crest(local,.54,.12);
  } else if (mode > 1.5 && mode < 2.5) {
    wave += .23*arrived*basin*sin(max(0.0,local)*10.0)*exp(-max(0.0,local)*1.8);
  } else if (mode > 2.5 && mode < 3.5) {
    wave = .34*crest(local,.14,.19);
    p += q/max(r,.02)*wave*.11*amount;
    sink = 1.06*arrived;
  } else if (mode > 3.5) {
    float second = smoothstep(0.0,.70,local-.62);
    sink = .44*arrived+.68*second;
    wave -= .17*crest(local,.85,.27);
  }
  p -= q*(.13*amount*arrived*basin);
  return vec3(p, amount*(-sink*basin+wave));
}
vec3 surface(vec2 p) {
  if (study > .5) return gravitySurface(p);
  vec2 q = p - vec2(.17, -.08);
  float r2 = dot(q,q);
  float g = exp(-r2 * 1.7);
  float z = 0.0;
  if (mode < .5) {
    z = -.97 * amount * g;
    p -= q * (.16 * amount * g);
  } else if (mode < 1.5) {
    float theta = 1.22 * amount * exp(-r2 * 1.05);
    float c = cos(theta), s = sin(theta);
    p = vec2(c*q.x-s*q.y, s*q.x+c*q.y) + vec2(.17,-.08);
    z = -.52 * amount * g;
  } else if (mode < 2.5) {
    z = .62 * amount * (p.x*p.x/(aspect*aspect) - p.y*p.y);
    p.y += .08 * amount * sin(p.x * 2.0);
  } else if (mode < 3.5) {
    float angle = amount * 1.48;
    float x = p.x / aspect;
    p.x = aspect * sin(x*angle) / max(angle,.0001);
    if (amount < .0001) p.x = x*aspect;
    z = -1.05 * (1.0-cos(x*angle));
    p.y += .05 * amount * cos(x*3.14);
  } else {
    float squeeze = exp(-p.y*p.y*4.5);
    p.x *= 1.0 - .46 * amount * squeeze;
    p.y += .11 * amount * sin(p.y * 3.14);
    z = .32 * amount * cos(p.y*2.4);
  }
  return vec3(p,z);
}
void main() {
  vUV = uv;
  vec2 p = (uv-.5)*2.0 * vec2(aspect,1.0);
  vec2 source = (origin-.5)*2.0*vec2(aspect,1.0);
  float local = age-length(p-source)/1.15;
  vWave = study*crest(local,.12,.13);
  if (mode > .5 && mode < 1.5) vWave += study*.65*crest(local,.54,.12);
  vec3 pos = surface(p);
  vec3 dx = surface(p+vec2(.008,0.0))-pos;
  vec3 dy = surface(p+vec2(0.0,.008))-pos;
  vec3 normal = normalize(cross(dx,dy));
  vec3 light = normalize(vec3(-.4,.6,1.0));
  vLight = clamp(1.0 + .3 * (dot(normal,light)-light.z), .5,1.16);
  float perspective = 1.0/(1.0-pos.z*.38);
  float fit = study < .5 && mode > 1.5 && mode < 2.5 ? .83/(1.0+.22*amount) : .83;
  vec2 screen = vec2(pos.x/aspect,pos.y+pos.z*.20)*perspective*fit;
  gl_Position = vec4(screen,0.0,1.0);
}`;

const fragmentSource = `
precision mediump float;
uniform sampler2D page;
uniform float grid, amount;
varying vec2 vUV;
varying float vLight;
varying float vWave;
void main() {
  vec4 color = texture2D(page,vUV);
  vec2 cell = abs(fract(vUV*vec2(30.0,20.0))-.5);
  float line = smoothstep(.467,.497,max(cell.x,cell.y));
  vec3 rgb = color.rgb * mix(1.0,vLight,amount);
  rgb = mix(rgb, vec3(.26,.52,.45), line*grid*.26);
  rgb = mix(rgb, vec3(.81,.93,.67), clamp(vWave*amount*.17,0.0,.35));
  gl_FragColor = vec4(rgb,color.a);
}`;

function compile(type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader));
  }
  return shader;
}

function initGL() {
  gl = canvas.getContext('webgl', { alpha: true, antialias: true, preserveDrawingBuffer: true });
  if (!gl) throw new Error('WebGL unavailable');
  program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, vertexSource));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragmentSource));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  gl.useProgram(program);
  uniforms = Object.fromEntries(['aspect', 'amount', 'mode', 'grid', 'page', 'study', 'age', 'origin'].map(name => [name, gl.getUniformLocation(program, name)]));
  const vertices = [];
  const columns = 120, rows = 80;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < columns; x++) {
      const l = x / columns, r = (x + 1) / columns, b = y / rows, t = (y + 1) / rows;
      vertices.push(l,b, r,b, l,t, l,t, r,b, r,t);
    }
  }
  vertexCount = vertices.length / 2;
  vertexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW);
  const attr = gl.getAttribLocation(program, 'uv');
  gl.enableVertexAttribArray(attr);
  gl.vertexAttribPointer(attr, 2, gl.FLOAT, false, 0, 0);
  texture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  gl.clearColor(0, 0, 0, 0);
  gl.uniform1i(uniforms.page, 0);
}

// A self-contained fictional page texture: no page capture, dependencies, or network requests.
function drawPage() {
  const source = document.createElement('canvas');
  source.width = Math.round(width * 2);
  source.height = Math.round(height * 2);
  const c = source.getContext('2d');
  c.scale(source.width / 1100, source.height / 680);
  function box(x,y,w,h,r,fill) {
    c.fillStyle = fill;
    c.beginPath(); c.roundRect(x,y,w,h,r); c.fill();
  }
  function text(s,x,y,size=14,color='#344840',font='sans-serif') {
    c.fillStyle=color; c.font=`${size}px ${font}`; c.fillText(s,x,y);
  }
  box(0,0,1100,680,18,'#f0f1e9');
  box(0,0,1100,47,[18,18,0,0],'#dce2d5');
  ['#b1bda6','#bbc6b1','#c5cebd'].forEach((color,i)=>box(20+i*17,19,8,8,4,color));
  box(354,10,392,26,6,'#cfd8c7');
  text('studio.example',493,28,11,'#738268');
  c.strokeStyle='#c8d1be'; c.lineWidth=1;
  c.beginPath();c.moveTo(195,47);c.lineTo(195,680);c.stroke();
  text('folio.',27,103,36,'#35473a','Georgia');
  text('YOUR WORKSPACE',28,158,10,'#8a987e');
  box(17,177,161,34,5,'#dde5d4');
  text('◈  Overview',29,199,13,'#506747');
  ['Collections','Projects','Inspiration','Archive'].forEach((s,i)=>text(s,30,242+i*39,13,'#8e9b80'));
  c.strokeStyle='#d3dacb';c.beginPath();c.moveTo(28,418);c.lineTo(165,418);c.stroke();
  text('RECENT COLLECTIONS',28,453,9,'#94a085');
  ['Objects & spaces','Thoughts on form','The quieter things'].forEach((s,i)=>text(s,30,483+i*29,11,'#8a987d'));
  text('A PLACE FOR GOOD WORK',237,106,10,'#849575');
  text('Your next chapter.',235,162,46,'#314838','Georgia');
  text('Collect what matters. Make something meaningful.',238,193,14,'#849279');
  const buttonText=method==='apple'?'Continue with Apple':'Continue with a passkey';
  box(789,117,261,45,7,'#344e39');
  text(buttonText,815,145,14,'#e5eddb');
  c.strokeStyle='#cbd5c1'; c.beginPath();c.moveTo(237,224);c.lineTo(1050,224);c.stroke();
  text('CURATED FOR YOU',238,256,10,'#8a997b');
  text('01 — 03',995,256,10,'#8a997b');
  const cards=[{x:237,color:'#c1cbaa',label:'Objects with intention',sub:'COLLECTION / 12 ITEMS'}, {x:518,color:'#bbcbbd',label:'A different perspective',sub:'JOURNAL / 6 MIN READ'}, {x:798,color:'#d4c6ad',label:'Slow, considered living',sub:'COLLECTION / 24 ITEMS'}];
  cards.forEach((card,i)=>{
    box(card.x,279,252,224,7,card.color);
    c.save();c.beginPath();c.rect(card.x,279,252,224);c.clip();
    if(i===0){
      box(card.x+63,335,133,163,[66,66,4,4],'#a2b18e');
      box(card.x+88,354,82,149,[41,41,0,0],'#667e5b');
      box(card.x+10,473,235,30,0,'#d8dec6');
    } else if(i===1){
      c.fillStyle='#8fa99b';c.beginPath();c.ellipse(card.x+125,426,91,104,-.4,0,Math.PI*2);c.fill();
      c.fillStyle='#d9e4d6';c.beginPath();c.ellipse(card.x+127,395,52,82,-.4,0,Math.PI*2);c.fill();
      c.fillStyle='#688b7b';c.beginPath();c.ellipse(card.x+129,393,25,57,-.4,0,Math.PI*2);c.fill();
    } else {
      box(card.x+44,407,169,96,[70,70,0,0],'#b8a585');
      box(card.x+92,336,65,153,[30,30,12,12],'#e5d9c3');
      box(card.x+110,324,30,25,5,'#e5d9c3');
      box(card.x+8,486,240,30,0,'#c7b596');
    }
    c.restore();
    text(card.sub,card.x,532,9,'#8c9a7d');
    text(card.label,card.x,561,21,'#3e543f','Georgia');
    c.strokeStyle='#cfd8c4'; c.beginPath();c.moveTo(card.x,584);c.lineTo(card.x+252,584);c.stroke();
    text('Explore collection',card.x,610,11,'#849577');
    text('↗',card.x+235,610,14,'#738a66');
  });
  text('A calmer corner of the internet.',238,655,10,'#93a086');
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
}

function resize() {
  if (!gl || contextLost) return;
  const rect = canvas.getBoundingClientRect();
  width = Math.max(1, rect.width); height = Math.max(1, rect.height);
  const ratio = Math.min(devicePixelRatio || 1, 2);
  canvas.width = Math.round(width * ratio); canvas.height = Math.round(height * ratio);
  gl.viewport(0, 0, canvas.width, canvas.height);
  drawPage(); requestFrame();
}

const smooth = x => { x = Math.max(0, Math.min(1, x)); return x*x*(3-2*x); };
function status(message) { if ($('#phase').textContent !== message) $('#phase').textContent = message; }
function setPrompt(visible) {
  visible = visible && $('#show-prompt').checked;
  prompt.classList.toggle('visible', visible);
  prompt.inert = !visible;
}
function requestFrame() { if (!raf && !contextLost && !document.hidden) raf = requestAnimationFrame(render); }

function waveDuration() {
  const a=width/height;
  const farX=2*a*Math.max(origin[0],1-origin[0]);
  const farY=2*Math.max(origin[1],1-origin[1]);
  return Math.hypot(farX,farY)/1.15 + (mode===2 ? 2.4 : 1.65);
}

function updateOriginMarker(visible) {
  const marker=$('#origin-marker');
  if (!marker) return;
  marker.style.left=((origin[0]-.5)*.83+.5)*100+'%';
  marker.style.top=((.5-origin[1])*.83+.5)*100+'%';
  marker.classList.toggle('visible',visible && !$('#reduced').checked);
}

function render(now) {
  raf = 0;
  if (!gl || contextLost) return;
  const reduced = $('#reduced').checked;
  const speed = $('#slow').checked ? 2.5 : 1;
  if (phase === 'enter') {
    const elapsed = (now-started)/1000/speed;
    const duration=gravityStudy ? waveDuration() : 1.65;
    waveAge=elapsed;
    // The travelling arrival mask controls the bend locally, not a full-page opacity/scale ramp.
    amount = gravityStudy ? smooth(elapsed/.12) : smooth(elapsed/1.65);
    setPrompt(elapsed > .72 || reduced);
    if (gravityStudy) {
      updateOriginMarker(elapsed<.7);
      $('#wave-progress').style.width=Math.min(100,elapsed/duration*100)+'%';
    }
    if (elapsed >= duration || reduced) { phase='hold'; amount=1; status('Holding space · awaiting authentication'); }
  } else if (phase === 'release') {
    const elapsed = (now-releaseStart)/1000/speed;
    amount = releaseAmount*(1-smooth(elapsed/1.35));
    if (elapsed >= 1.35 || reduced) { phase='idle'; amount=0; status('Space restored · no sign-in performed'); }
  }
  stage.classList.toggle('reduced', reduced);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.uniform1f(uniforms.aspect, width/height);
  gl.uniform1f(uniforms.mode, mode);
  gl.uniform1f(uniforms.study, gravityStudy ? 1 : 0);
  gl.uniform1f(uniforms.age, waveAge);
  gl.uniform2f(uniforms.origin, origin[0], origin[1]);
  gl.uniform1f(uniforms.amount, reduced ? 0 : amount*Number($('#depth').value)/75);
  gl.uniform1f(uniforms.grid, $('#grid').checked ? 1 : 0);
  gl.drawArrays(gl.TRIANGLES, 0, vertexCount);
  // Expose only non-sensitive render diagnostics for the local prototype's browser checks.
  canvas.dataset.mode = String(mode);
  canvas.dataset.deformation = String(reduced ? 0 : amount*Number($('#depth').value)/75);
  canvas.dataset.phase = phase;
  if (gravityStudy) {
    canvas.dataset.origin=origin.join(',');
    canvas.dataset.waveAge=String(waveAge);
  }
  if (phase === 'enter' || phase === 'release') requestFrame();
}

function play() {
  if (!gl || contextLost) return;
  phase='enter'; started=performance.now(); amount=0; waveAge=0; setPrompt(false);
  if (gravityStudy) $('#wave-progress').style.width='0%';
  $('#release').disabled=false; status(gravityStudy ? 'Ripple travelling from click' : 'Deforming the page'); requestFrame();
}
function release() {
  if (!gl || contextLost) return;
  phase='release'; releaseStart=performance.now(); releaseAmount=amount; setPrompt(false);
  updateOriginMarker(false);
  $('#release').disabled=true; status('Releasing curvature'); requestFrame();
}
function select(next) {
  mode=next;
  const concept=concepts[mode];
  document.querySelectorAll('[data-mode]').forEach(button=>button.setAttribute('aria-pressed', String(Number(button.dataset.mode)===mode)));
  $('#stage-name').textContent=`0${mode+1} — ${concept.name.toUpperCase()}`;
  $('#note-title').textContent=concept.name;
  $('#description').textContent=concept.description;
  $('#geometry').textContent=concept.geometry;
  canvas.setAttribute('aria-label',`${concept.name}: ${concept.geometry}${gravityStudy ? ' Click to move the origin. Enter replays.' : ''}`);
  play();
}

document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>select(Number(button.dataset.mode))));
document.querySelectorAll('[data-method]').forEach(button=>button.addEventListener('click',()=>{
  method=button.dataset.method;
  document.querySelectorAll('[data-method]').forEach(other=>other.setAttribute('aria-pressed',String(other===button)));
  $('#prompt-title').textContent=method==='apple'?'Continue with Apple':'Sign in with a passkey';
  $('#symbol').innerHTML=method==='apple'
    ? '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16.7 3.1c-.1 1.5-1.2 3-2.7 3.4-.2-1.4.8-3 2.7-3.4ZM19.8 17.4c-.6 1.3-1 2-1.8 3-1 1.2-2.3 2.5-3.8 1.8-1.4-.6-2-.6-3.5 0-1.5.6-2.7-.5-3.7-1.7C4.2 17 3.8 12.4 5.6 9.8c1.3-1.9 3.4-2.2 5.1-1.5 1.3.5 1.8.5 3.1 0 1.5-.6 3.8-.4 5.2 1.3-3.3 1.8-2.8 6.3.8 7.8Z"/></svg>'
    : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="4.5"/><path d="m11.3 11.3 8.2 8.2m-3-3 2-2m-5 2 2-2"/></svg>';
  $('#auth-status').textContent=method==='apple'?'Apple Account · simulated':'Waiting for Touch ID · simulated';
  if (gl && !contextLost) drawPage();
  play();
}));
$('#replay').addEventListener('click',play);
if (gravityStudy) {
  canvas.addEventListener('click',event=>{
    const rect=canvas.getBoundingClientRect();
    const u=((event.clientX-rect.left)/rect.width-.5)/.83+.5;
    const v=.5-((event.clientY-rect.top)/rect.height-.5)/.83;
    if (u<0 || u>1 || v<0 || v>1) return;
    origin=[u,v];
    play();
  });
  canvas.addEventListener('keydown',event=>{
    if (event.key==='Enter' || event.key===' ') { event.preventDefault(); play(); }
  });
}
$('#release').addEventListener('click',release);
$('#cancel').addEventListener('click',release);
$('#depth').addEventListener('input',()=>{
  $('#depth-value').textContent=$('#depth').value+'%';
  $('#depth-readout').textContent='CURVATURE '+$('#depth').value.padStart(3,'0');
  requestFrame();
});
$('#grid').addEventListener('change',requestFrame);
$('#show-prompt').addEventListener('change',()=>setPrompt(phase==='hold' || (phase==='enter' && amount>.4)));
$('#slow').addEventListener('change',play);
$('#reduced').addEventListener('change',play);
reducedPreference.addEventListener('change',event=>{ $('#reduced').checked=event.matches; play(); });
document.addEventListener('keydown',event=>{ if(event.key==='Escape') release(); });
document.addEventListener('visibilitychange',()=>{ if(!document.hidden) requestFrame(); });
canvas.addEventListener('webglcontextlost',event=>{
  event.preventDefault(); contextLost=true; cancelAnimationFrame(raf); raf=0;
  setPrompt(false); status('Graphics paused · waiting for context recovery');
});
canvas.addEventListener('webglcontextrestored',()=>{ contextLost=false; boot(); });

function boot() {
  try {
    initGL(); resize(); select(mode);
    $('#fallback').hidden=true;
    $('#engine').textContent='WEBGL / 19,200 DEFORMABLE TRIANGLES';
  } catch(error) {
    gl=null; $('#fallback').hidden=false; $('#engine').textContent='WEBGL UNAVAILABLE';
    status('Graphics unavailable'); $('#replay').disabled=true; $('#release').disabled=true;
    console.error('Spatial mockup:',error);
  }
}
new ResizeObserver(resize).observe(stage);
boot();
