// tests/run.sh: runs the flame graph page's script in node against a tiny DOM stub and counts what it draws
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const data = html.split('<script id="data" type="application/json">')[1].split('</script>')[0];
const script = html.split('<script>')[1].split('</script>')[0];
let rects = 0, texts = 0;
function el(tag) {
  return { tag, children: [], attrs: {}, textContent: '', value: '', clientWidth: 1200,
    appendChild(c) { this.children.push(c); if (c.tag === 'rect') rects++; if (c.tag === 'text') texts++; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); },
    get firstChild() { return this.children[0]; },
    setAttribute(k, v) { this.attrs[k] = v; }, addEventListener() {} };
}
const els = { data: { textContent: data }, g: el('svg'), info: el('div'), kind: el('select'), q: el('input'), t: el('h1'), reset: el('button') };
els.kind.appendChild = function (o) { this.children.push(o); if (!this.value) this.value = o.value; };
global.document = { getElementById: id => els[id], createElement: t => el(t), createElementNS: (ns, t) => el(t) };
global.window = { addEventListener() {} };
eval(script);
console.log('kinds', els.kind.children.map(o => o.value).join(','), 'rects', rects, 'texts', texts, 'height', els.g.attrs.height);
