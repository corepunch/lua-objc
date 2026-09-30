import { readFileSync, writeFileSync } from 'node:fs';

// Keep the iPad capture intact. Uniform scaling preserves the UI and the
// embedded 393 × 852 preview instead of redrawing or independently resizing it.
const screenshot = readFileSync(new URL('../web/studio-ipad.png', import.meta.url));
const source = { width: screenshot.readUInt32BE(16), height: screenshot.readUInt32BE(20) };
const tablet = { x: 88, y: 100, width: 1080, bezel: 24 };
tablet.height = tablet.width * source.height / source.width;
const phone = { x: 1282, width: 338, pointsWidth: 393, pointsHeight: 852, bezel: 10 };
phone.scale = phone.width / phone.pointsWidth;
phone.height = phone.pointsHeight * phone.scale;
phone.y = tablet.y + tablet.height + tablet.bezel - phone.height - phone.bezel;
const files = [
  ['init.lua', '+3'], ['Model.lua', '+86'], ['Controller.lua', '+54'],
  ['Window.etlua', '+48'], ['Today.etlua', '+41'], ['Stats.etlua', '+37'], ['Settings.etlua', '+22'],
];
const fileRows = files.map(([name, count], index) => {
  const y = 448 + index * 34;
  return `<use href="#file" x="35" y="${y - 15}"/><text class="code" x="64" y="${y}">${name}</text><text class="count" x="355" y="${y}">${count}</text>`;
}).join('\n');

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1680" height="1040" viewBox="0 0 1680 1040" role="img" aria-labelledby="title desc">
  <title id="title">Lua Studio on iPad, with an iPhone concept coming soon</title>
  <desc id="desc">The original iPad screenshot is displayed without cropping or stretching. A flat iPhone frame shows a proposed Assistant screen at 393 by 852 points.</desc>
  <defs>
    <clipPath id="ipad-screen"><rect x="${tablet.x}" y="${tablet.y}" width="${tablet.width}" height="${tablet.height}" rx="15"/></clipPath>
    <clipPath id="phone-screen"><rect width="393" height="852" rx="49"/></clipPath>
    <g id="file" fill="none" stroke="#7053d5" stroke-width="1.6" stroke-linejoin="round"><path d="M2 0h9l5 5v15H2Z M11 0v6h5 M5 11h8 M5 15h8"/></g>
    <g id="sparkle" fill="currentColor"><path d="M12 0c1.5 8.5 3.5 10.5 12 12-8.5 1.5-10.5 3.5-12 12C10.5 15.5 8.5 13.5 0 12 8.5 10.5 10.5 8.5 12 0Z"/></g>
    <style>
      text { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif; fill: #202025; }
      .device-label { font-size: 19px; font-weight: 600; }
      .device-note { font-size: 15px; fill: #777380; }
      .code { font-family: 'SF Mono', Menlo, monospace; font-size: 15px; }
      .count { fill: #249c54; font-size: 15px; text-anchor: end; }
    </style>
  </defs>
  <rect width="1680" height="1040" fill="#efedf4"/>
  <!-- A flat outline and the unmodified screenshot are the entire iPad. -->
  <rect x="${tablet.x - tablet.bezel}" y="${tablet.y - tablet.bezel}" width="${tablet.width + 2 * tablet.bezel}" height="${tablet.height + 2 * tablet.bezel}" rx="38" fill="#1c1c20" stroke="#85848c" stroke-width="2"/>
  <image x="${tablet.x}" y="${tablet.y}" width="${tablet.width}" height="${tablet.height}" preserveAspectRatio="xMidYMid meet" clip-path="url(#ipad-screen)" href="data:image/png;base64,${screenshot.toString('base64')}"/>
  <circle cx="76" cy="505" r="3" fill="#34343c"/>
  <text x="64" y="978" class="device-label">Studio on iPad</text>
  <text x="64" y="1005" class="device-note">Your workspace. Your code. A live native preview.</text>
  <!-- The phone concept is drawn in logical screen points, then scaled once
       as a whole. Body text is 17pt; file names are 15pt. -->
  <rect x="${phone.x - phone.bezel}" y="${phone.y - phone.bezel}" width="${phone.width + phone.bezel * 2}" height="${phone.height + phone.bezel * 2}" rx="51" fill="#1c1c20" stroke="#85848c" stroke-width="2"/>
  <g transform="translate(${phone.x} ${phone.y}) scale(${phone.scale})">
    <g clip-path="url(#phone-screen)">
      <rect width="393" height="852" fill="#fbfaff"/>
      <text x="34" y="37" font-size="15" font-weight="600">9:41</text>
      <rect x="134" y="11" width="125" height="36" rx="18" fill="#09090b"/>
      <g fill="#27272b"><rect x="302" y="30" width="3" height="5" rx="1"/><rect x="307" y="27" width="3" height="8" rx="1"/><rect x="312" y="23" width="3" height="12" rx="1"/><rect x="317" y="20" width="3" height="15" rx="1"/></g>
      <rect x="331" y="23" width="25" height="12" rx="3" fill="none" stroke="#86858b"/><rect x="334" y="26" width="19" height="6" rx="1" fill="#27272b"/><rect x="358" y="27" width="2" height="4" rx="1" fill="#86858b"/>
      <path d="m28 73-7 7 7 7" fill="none" stroke="#6550d8" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <text x="44" y="86" font-size="17" font-weight="600">Habit Tracker</text>
      <rect x="308" y="63" width="65" height="34" rx="17" fill="#6548e7"/>
      <path d="m321 74 9 6-9 6Z" fill="white"/><text x="335" y="86" style="fill:white" font-size="15" font-weight="600">Run</text>
      <rect x="20" y="112" width="353" height="33" rx="9" fill="#eae7f0"/>
      <rect x="22" y="114" width="116" height="29" rx="7" fill="white"/>
      <g font-size="13" text-anchor="middle"><text x="80" y="133" font-weight="600">Assistant</text><text x="196" y="133">Code</text><text x="314" y="133">Preview</text></g>
      <circle cx="34" cy="179" r="14" fill="#7850d9"/><use href="#sparkle" transform="translate(25 170) scale(.75)" color="white"/>
      <text x="56" y="178" font-size="15" font-weight="600">Assistant</text><text x="56" y="194" font-size="12" style="fill:#8a8691">openrouter/free</text>
      <rect x="62" y="216" width="311" height="86" rx="19" fill="#ede5fa"/>
      <text x="78" y="242" font-size="16"><tspan x="78">Build a habit tracker with</tspan><tspan x="78" dy="22">Today, Stats and Settings.</tspan><tspan x="78" dy="22">Save progress on this device.</tspan></text>
      <text x="20" y="337" font-size="17" font-weight="600">Your habit tracker is ready.</text>
      <text x="20" y="363" font-size="17" style="fill:#65616c">Run it to try your first check-in.</text>
      <rect x="20" y="389" width="353" height="290" rx="16" fill="#f0eef5"/>
      <text x="36" y="417" font-size="15" font-weight="600">7 files changed</text><text x="355" y="417" class="count">+291</text>
      ${fileRows}
      <circle cx="28" cy="703" r="7" fill="#4c9f70"/><path d="m25 703 2 2 4-4" stroke="white" fill="none" stroke-width="1.5"/>
      <text x="43" y="708" font-size="14" style="fill:#76717f">Preview updated</text>
      <rect x="20" y="755" width="353" height="51" rx="25" fill="white" stroke="#ded9e7"/>
      <path d="M43 774v14 M36 781h14" stroke="#57525f" stroke-width="2" stroke-linecap="round"/>
      <text x="64" y="787" font-size="17" style="fill:#a39cae">Describe a change…</text>
      <circle cx="348" cy="781" r="18" fill="#6548e7"/><path d="M348 790v-17 m-6 6 6-6 6 6" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <rect x="130" y="836" width="133" height="5" rx="2.5" fill="#232126"/>
    </g>
  </g>
  <text x="1272" y="978" class="device-label">Studio on iPhone</text>
  <text x="1272" y="1005" class="device-note">Coming soon · Concept preview</text>
</svg>`;

writeFileSync(new URL('../web/studio-builder.svg', import.meta.url), svg);
console.log(`iPad: ${source.width} × ${source.height} → ${tablet.width} × ${tablet.height}; iPhone: ${phone.pointsWidth} × ${phone.pointsHeight} → ${phone.width} × ${phone.height.toFixed(2)}. Both uniformly scaled.`);
