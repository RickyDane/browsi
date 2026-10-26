'use strict';

const $ = selector => document.querySelector(selector);
const digitalStudy = document.body.dataset.study === 'digital';
const gravityStudy = document.body.dataset.study === 'gravity' || digitalStudy;
const concepts = digitalStudy ? [
  { name: 'Radial Lattice', description: 'A fine square lattice unfurls behind the Undertow wave. Quiet intersection points give it a precise, digital character without turning it into visual noise.', geometry: 'The click emits a circular reveal front. Grid lines and tiny nodes appear behind it, follow the travelling warp, and then rest on the flattened page until the demo dialog closes.' },
  { name: 'Folded Tiles', description: 'Individual wireframe cells open like tiny hinged panels. A more tactile, architectural interpretation of an unfolding digital layer.', geometry: 'Each cell opens from a narrow central seam to a complete square when the wave reaches it. The staggered hinges become an ordered field of separated tiles during authentication.' },
  { name: 'Circuit Bloom', description: 'A network of right-angle paths branches from the click. Small junction nodes make the page feel temporarily connected to a digital authentication plane.', geometry: 'A stepped, Manhattan-distance reveal grows through the network. Sparse elbows and illuminated nodes replace a uniform grid; the completed circuitry stays still while the dialog is open.' },
  { name: 'Hex Field', description: 'A fine honeycomb tessellation grows over the page. More organic than a square grid, but still distinctly computational.', geometry: 'Hexagonal cells assemble outward from the click, with a brighter leading edge. The mesh bends with Deep Undertow, settles flat, and remains as a quiet authentication texture.' },
  { name: 'Scan Weave', description: 'Horizontal scanlines unfold first; vertical threads weave through them a moment later. Two directional passes build one persistent digital fabric.', geometry: 'Rows expand vertically away from the click, followed by columns spreading horizontally. Their crossings form bright, precise stitches; the woven grid remains until dismissal.' },
  { name: 'Dotted Atmosphere', description: 'A quiet field of small slate dots over a soft blue, lilac, and teal wash. Inspired by the Beyond Over staging background: no connecting lines, no flickering symbols.', geometry: 'The dots use the reference’s 22-pixel spacing and 1.4-pixel radius. They gently grow into view as Deep Undertow passes, then remain completely still until the demo dialog closes.' },
  { name: 'Native Cipher', description: 'White cipher-dot clusters over a fine background grid. One brief click-origin impact sends a single travelling warp across the page—no second ripple.', geometry: 'The native 12-point cipher cells, three-by-three subdots, and five-point grid remain. A single impulse reveals the white dots; the impact rebounds, and the overlay stays still until dismissal.' }
] : gravityStudy ? [
  { name: 'Quiet Tide', description: 'One restrained impulse starts at your click. A smooth ripple carries the curvature outward, leaving no lasting dent at the source.', geometry: 'A narrow crest and a soft trough travel together. Each point briefly bends as they pass, then returns to its original position—even while the wave is still crossing the page.' },
  { name: 'Twin Ripple', description: 'A second, smaller ripple follows the first. A subtle double beat makes the interaction feel deliberate without leaving the page pressed down.', geometry: 'Two separated geometric crests travel outward from the same click. The second follows 420 milliseconds later; both dissipate, restoring a completely flat page.' },
  { name: 'Elastic Wake', description: 'The website behaves like a flexible membrane. The wave leaves a small, damped rebound behind it before the page becomes still.', geometry: 'Each point begins moving only when the wave reaches it. A local spring-like oscillation decays independently behind the travelling front.' },
  { name: 'Raised Rim', description: 'A more sculptural impulse. A pronounced lip rises ahead of a travelling depression, making the curvature unmistakable without pinning the impact point down.', geometry: 'A positive crest pushes the mesh upward and outward, followed by a temporary trough. Both move away from the click; the surface immediately begins recovering behind them.' },
  { name: 'Deep Undertow', description: 'First a light ripple, then a deeper passing pull. The two-stage pulse gives the wave more weight, but the impact point still recovers.', geometry: 'A broad second trough follows 620 milliseconds behind the first impulse. It travels across the page instead of forming a permanent basin; every point returns to flat.' }
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
let mode = digitalStudy ? ({ '#dots': 5, '#cipher': 6 }[location.hash] ?? 0) : 0;
let method = 'passkey';
let phase = 'idle';
let started = 0;
let releaseStart = 0;
let releaseAmount = 0;
let overlayAmount = 0;
let releaseOverlayAmount = 0;
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
  float cutoff = 1.0-smoothstep(2.0,3.0,abs(x));
  return exp(-x*x) * cutoff * smoothstep(0.0,.055,local) * smoothstep(0.0,.18,age);
}
float impulse(float local) {
  // Each point recovers locally; the source does not remain pinned until the wave ends.
  return smoothstep(0.0,.19,local) * (1.0-smoothstep(.34,1.10,local));
}
vec3 gravitySurface(vec2 p) {
  vec2 center = (origin-.5)*2.0*vec2(aspect,1.0);
  vec2 q = p-center;
  float r = length(q);
  float local = age-r/1.15;
  float arrived = smoothstep(0.0,.34,local);
  float pulse = impulse(local);
  float basin = exp(-dot(q,q)*.64);
  float wave = .14*crest(local,.12,.13);
  float sink = .98*pulse;
  if (mode > .5 && mode < 1.5) {
    wave += .10*crest(local,.54,.12);
  } else if (mode > 1.5 && mode < 2.5) {
    float decay = exp(-max(0.0,local)*1.8) * (1.0-smoothstep(1.2,2.2,local));
    wave += .23*arrived*basin*sin(max(0.0,local)*10.0)*decay;
  } else if (mode > 2.5 && mode < 3.5) {
    wave = .34*crest(local,.14,.19);
    p += q/max(r,.02)*wave*.11*amount;
    sink = 1.06*pulse;
  } else if (mode > 3.5) {
    float second = impulse(local-.62);
    sink = .44*pulse+.68*second;
    wave -= .17*crest(local,.85,.27);
  }
  p -= q*(.13*amount*pulse*basin);
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
uniform float digital, overlayMode, overlayAlpha, age, aspect, surfaceHeight;
uniform vec2 origin;
varying vec2 vUV;
varying float vLight;
varying float vWave;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float cipherHash(vec2 p) {
  // Preserve the native shader's fractional hash without mediump rounding it to zero.
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  highp vec2 hp = p;
  return fract(sin(dot(hp,vec2(127.1,311.7)))*43758.5453);
  #else
  vec3 q = fract(vec3(p.xyx)*.1031);
  q += dot(q,q.yzx+3.33);
  return fract((q.x+q.y)*q.z);
  #endif
}
float thin(float d, float w) { return 1.0-smoothstep(w,w+.025,abs(d)); }
vec2 digitalField() {
  vec2 metric = vec2(aspect,1.0);
  vec2 p = vUV*metric*18.0;
  vec2 id = floor(p);
  vec2 f = fract(p)-.5;
  float t = max(0.0,age-.40);
  float r = length((vUV-origin)*metric)*2.0;
  float reveal = smoothstep(0.0,.4,t-r/1.15);
  float lines = max(thin(.5-abs(f.x),.012),thin(.5-abs(f.y),.012));
  float node = 1.0-smoothstep(.045,.075,length(fract(p+.5)-.5));
  float ink = max(lines*.65,node*.9);
  if (overlayMode > .5 && overlayMode < 1.5) {
    p = vUV*metric*10.0;
    id = floor(p); f = fract(p)-.5;
    vec2 center = (id+.5)/(metric*10.0);
    float arrival = length((center-origin)*metric)*2.0/1.15;
    float opened = smoothstep(0.0,.65,t-arrival-hash(id)*.16);
    float hinge = .43*sin(opened*1.5707963);
    float horizontal = thin(abs(f.y)-hinge,.009)*step(abs(f.x),.43);
    float vertical = thin(abs(f.x)-.43,.009)*step(abs(f.y),hinge);
    ink = max(horizontal,vertical)*.85*opened;
    reveal = opened;
  } else if (overlayMode > 1.5 && overlayMode < 2.5) {
    float manhattan = dot(abs((vUV-origin)*metric),vec2(1.0))*2.0;
    reveal = smoothstep(0.0,.4,t-manhattan/1.65);
    float horizontal = thin(f.y,.012)*step(f.x,.15);
    float vertical = thin(f.x-.15,.012)*step(-.02,f.y)*step(.35,hash(id));
    float junction = 1.0-smoothstep(.055,.085,length(f-vec2(.15,0.0)));
    ink = max(max(horizontal,vertical)*.8,junction);
  } else if (overlayMode > 2.5 && overlayMode < 3.5) {
    vec2 hp = vUV*metric*19.0;
    vec2 cellSize = vec2(1.7320508,3.0);
    vec2 a = mod(hp,cellSize)-cellSize*.5;
    vec2 b = mod(hp+cellSize*.5,cellSize)-cellSize*.5;
    vec2 h = dot(a,a)<dot(b,b) ? a : b;
    float edge = max(abs(h.x),abs(h.x)*.5+abs(h.y)*.8660254);
    ink = thin(edge-.8660254,.015)*.85;
    float rim = exp(-pow((t-r/1.15-.12)/.16,2.0));
    ink = min(1.0,ink*(1.0+rim));
  } else if (overlayMode > 3.5 && overlayMode < 4.5) {
    float rows = smoothstep(0.0,.45,t-abs(vUV.y-origin.y)*2.0/.8);
    float columns = smoothstep(0.0,.45,t-.65-abs(vUV.x-origin.x)*aspect*2.0/1.15);
    float horizontal = thin(.5-abs(f.y),.012)*rows;
    float vertical = thin(.5-abs(f.x),.012)*columns;
    ink = max(horizontal*.65,vertical*.65);
    ink = max(ink,node*rows*columns);
    reveal = max(rows,columns);
    return vec2(ink,reveal);
  } else if (overlayMode > 4.5 && overlayMode < 5.5) {
    // Reference: 22px grid, 1.4px slate dots. Use CSS pixels, not backing-store pixels.
    vec2 pixelSize = metric*surfaceHeight*.83;
    vec2 dots = vUV*pixelSize/22.0;
    vec2 center = (floor(dots)+.5)*22.0/pixelSize;
    float arrival = length((center-origin)*metric)*2.0/1.15;
    float opened = smoothstep(0.0,.35,t-arrival);
    float distanceToDot = length((fract(dots)-.5)*22.0);
    ink = (1.0-smoothstep(max(0.0,1.4*opened-.25),1.4*opened+.25,distanceToDot))*opened;
    return vec2(ink,reveal);
  } else if (overlayMode > 5.5) {
    // Match Browsi/UI/Effects/Ripple.metal: 12pt cells containing 3×3 cipher dots.
    vec2 position = vUV*metric*surfaceHeight*.83;
    vec2 cellID = floor(position/12.0);
    vec2 lp = fract(position/12.0)*3.0;
    vec2 sub = floor(lp);
    float arrival = r/1.15;
    float tick = floor(min(t,arrival+.9)*3.0+cipherHash(cellID)*10.0);
    float bit = step(.45,cipherHash(cellID*1.31+sub*7.17+tick));
    float dotMask = 1.0-smoothstep(.26,.36,length(fract(lp)-.5));
    vec2 fine = abs(fract(position/5.0)-.5)*5.0;
    float edge = 1.0-smoothstep(0.0,.9,2.5-max(fine.x,fine.y));
    float front = exp(-pow((t-arrival-.2)/.26,2.0));
    ink = bit*dotMask*(.55+.4*front)+edge*.10;
    return vec2(min(1.0,ink)*reveal,reveal);
  }
  return vec2(ink*reveal,reveal);
}
void main() {
  vec4 color = texture2D(page,vUV);
  vec2 cell = abs(fract(vUV*vec2(30.0,20.0))-.5);
  float line = smoothstep(.467,.497,max(cell.x,cell.y));
  vec3 rgb = color.rgb * mix(1.0,vLight,amount);
  rgb = mix(rgb, vec3(.26,.52,.45), line*grid*.26);
  rgb = mix(rgb, vec3(.81,.93,.67), clamp(vWave*amount*.17,0.0,.35));
  if (digital > .5) {
    vec2 field = digitalField();
    if (overlayMode > 5.5) {
      rgb = mix(rgb,vec3(.045,.055,.085),field.y*overlayAlpha*.30);
      rgb = mix(rgb,vec3(1.0),field.x*overlayAlpha*.72);
    } else if (overlayMode > 4.5) {
      float blue = exp(-dot((vUV-vec2(.4,.85))*vec2(1.2,1.0),(vUV-vec2(.4,.85))*vec2(1.2,1.0))*5.0);
      float lilac = exp(-dot(vUV-vec2(.9,.4),vUV-vec2(.9,.4))*6.0);
      float teal = exp(-dot(vUV-vec2(.1,.1),vUV-vec2(.1,.1))*6.0);
      vec3 wash = vec3(.94,.96,.98);
      wash = mix(wash,vec3(.79,.88,.98),blue*.65);
      wash = mix(wash,vec3(.88,.85,.97),lilac*.45);
      wash = mix(wash,vec3(.80,.93,.92),teal*.40);
      rgb = mix(rgb,wash,field.y*overlayAlpha*.46);
      rgb = mix(rgb,vec3(.39216,.45490,.54510),field.x*overlayAlpha*.32);
    } else {
      rgb = mix(rgb,vec3(.025,.075,.06),field.y*overlayAlpha*.38);
      rgb = mix(rgb,vec3(.22,.76,.61),field.x*overlayAlpha*.70);
    }
  }
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
  uniforms = Object.fromEntries(['aspect', 'amount', 'mode', 'grid', 'page', 'study', 'age', 'origin', 'digital', 'overlayMode', 'overlayAlpha', 'surfaceHeight'].map(name => [name, gl.getUniformLocation(program, name)]));
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
  const propagation = Math.hypot(farX,farY)/1.15;
  const weave = Math.max(farY/.8,farX/1.15+.65)+1.0;
  return Math.max(propagation+2.3,digitalStudy ? weave : 0);
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
  // The digital studies run 35% shorter; Slow remains available for inspecting the surface.
  const speed = $('#slow').checked ? 2.5 : digitalStudy ? .65 : 1;
  if (phase === 'enter') {
    const elapsed = (now-started)/1000/speed;
    const duration=gravityStudy ? waveDuration() : 1.65;
    waveAge=elapsed;
    // The travelling arrival mask controls the bend locally, not a full-page opacity/scale ramp.
    amount = gravityStudy ? smooth(elapsed/.12) : smooth(elapsed/1.65);
    overlayAmount = smooth((elapsed-.40)/.4);
    setPrompt(elapsed > .72 || reduced);
    if (gravityStudy) {
      updateOriginMarker(elapsed<.7);
      $('#wave-progress').style.width=Math.min(100,elapsed/duration*100)+'%';
    }
    if (elapsed >= duration || reduced) {
      phase='hold'; amount=gravityStudy ? 0 : 1;
      overlayAmount=1;
      if (gravityStudy) $('#wave-progress').style.width='100%';
      status(digitalStudy ? 'Grid holding · close the dialog to clear' : gravityStudy ? 'Page settled · awaiting authentication' : 'Holding space · awaiting authentication');
    }
  } else if (phase === 'release') {
    const elapsed = (now-releaseStart)/1000/speed;
    amount = releaseAmount*(1-smooth(elapsed/1.35));
    overlayAmount=releaseOverlayAmount*(1-smooth(elapsed/.75));
    if (elapsed >= 1.35 || reduced) { phase='idle'; amount=0; overlayAmount=0; status('Space restored · no sign-in performed'); }
  }
  stage.classList.toggle('reduced', reduced);
  gl.clear(gl.COLOR_BUFFER_BIT);
  gl.uniform1f(uniforms.aspect, width/height);
  gl.uniform1f(uniforms.surfaceHeight, height);
  // Native Cipher uses one impulse; keep Deep Undertow's delayed second pulse in the other studies.
  gl.uniform1f(uniforms.mode, digitalStudy ? (mode===6 ? 0 : 4) : mode);
  gl.uniform1f(uniforms.digital, digitalStudy ? 1 : 0);
  gl.uniform1f(uniforms.overlayMode, mode);
  gl.uniform1f(uniforms.overlayAlpha, $('#grid').checked ? overlayAmount : 0);
  gl.uniform1f(uniforms.study, gravityStudy ? 1 : 0);
  gl.uniform1f(uniforms.age, reduced ? 100 : waveAge);
  gl.uniform2f(uniforms.origin, origin[0], origin[1]);
  gl.uniform1f(uniforms.amount, reduced ? 0 : amount*Number($('#depth').value)/75);
  gl.uniform1f(uniforms.grid, !digitalStudy && $('#grid').checked ? 1 : 0);
  gl.drawArrays(gl.TRIANGLES, 0, vertexCount);
  // Expose only non-sensitive render diagnostics for the local prototype's browser checks.
  canvas.dataset.mode = String(mode);
  canvas.dataset.deformation = String(reduced ? 0 : amount*Number($('#depth').value)/75);
  canvas.dataset.phase = phase;
  if (digitalStudy) {
    canvas.dataset.overlay=String($('#grid').checked ? overlayAmount : 0);
    canvas.dataset.geometry=mode===6 ? 'Single impact' : 'Deep Undertow';
  }
  if (gravityStudy) {
    canvas.dataset.origin=origin.join(',');
    canvas.dataset.waveAge=String(waveAge);
  }
  if (phase === 'enter' || phase === 'release') requestFrame();
}

function play() {
  if (!gl || contextLost) return;
  phase='enter'; started=performance.now(); amount=0; waveAge=0; overlayAmount=0; setPrompt(false);
  if (gravityStudy) $('#wave-progress').style.width='0%';
  $('#release').disabled=false; status(gravityStudy ? 'Ripple travelling from click' : 'Deforming the page'); requestFrame();
}
function release() {
  if (!gl || contextLost) return;
  phase='release'; releaseStart=performance.now(); releaseAmount=amount; releaseOverlayAmount=overlayAmount; setPrompt(false);
  updateOriginMarker(false);
  $('#release').disabled=true; status('Releasing curvature'); requestFrame();
}
function select(next) {
  mode=next;
  if (digitalStudy) {
    $('#depth').value=mode===6 ? '10' : '75';
    $('#depth-value').textContent=$('#depth').value+'%';
    $('#depth-readout').textContent='CURVATURE '+$('#depth').value.padStart(3,'0');
  }
  if (digitalStudy) history.replaceState(null,'',mode===5 ? '#dots' : mode===6 ? '#cipher' : '#grid-'+(mode+1));
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
if (digitalStudy) window.addEventListener('hashchange',()=>{
  const next = { '#dots': 5, '#cipher': 6 }[location.hash];
  if (next !== undefined && next !== mode) select(next);
});
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
