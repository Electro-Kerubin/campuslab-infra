// Demostración de la validación de entrada de mq-admin: manda peticiones inválidas y comprueba que responden 400/415/422 y que el broker no cambia.
// Uso: ./run-demo-validacion.sh  (necesita ./start-mq-admin.sh en marcha).
const fs = require('fs'), os = require('os'), path = require('path');
const T = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.campuslab-aws', 'demo-tokens.json'), 'utf8'));
const env = Object.fromEntries(fs.readFileSync(path.join(os.homedir(), '.campuslab-aws/rabbitmq.env'), 'utf8')
  .split(/\r?\n/).filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const ADM = 'http://127.0.0.1:8085/api/mq', RMQ = `http://${process.env.RMQ_N1}:15672/api`;
const basic = 'Basic ' + Buffer.from(`${env.RABBITMQ_USER}:${env.RABBITMQ_PASS}`).toString('base64');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, bad = 0;
const check = (n, c, d = '') => { c ? (ok++, console.log('  PASS  ' + n)) : (bad++, console.log('  FAIL  ' + n + '  ' + d)); };

const raw = async (method, p, body, ctype = 'application/json') => {
  const r = await fetch(ADM + p, { method, headers: { Authorization: 'Bearer ' + T.admin, 'Content-Type': ctype }, body });
  const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch { /* no es JSON */ }
  return { s: r.status, j, t };
};
const post = (p, obj) => raw('POST', p, JSON.stringify(obj));
const names = async () => {
  const [q, e] = await Promise.all(['queues', 'exchanges'].map((k) => fetch(`${RMQ}/${k}/%2F`, { headers: { Authorization: basic } }).then((r) => r.json())));
  return { queues: q.map((x) => x.name).sort(), exchanges: e.map((x) => x.name).sort() };
};
const fields = (r) => JSON.stringify(r.j?.errors ?? r.j?.fieldErrors ?? r.j?.message ?? r.t).slice(0, 150);

(async () => {
  // base mínima para que las pruebas de "DLX inexistente" y "binding" tengan algo real contra qué compararse
  await post('/exchanges', { name: 'val.dead', type: 'DIRECT' });
  const before = await names();

  console.log('\n[1] Colas con datos inválidos -> 400 (nada llega al broker)');
  const colas = [
    ['nombre vacío', { name: '' }],
    ['nombre solo espacios', { name: '   ' }],
    ['sin nombre', {}],
    ['nombre con espacio', { name: 'q con espacio' }],
    ['nombre con caracteres peligrosos (/ # *)', { name: 'q/a#b*' }],
    ['nombre que empieza con símbolo', { name: '.cola' }],
    ['nombre de 256 caracteres', { name: 'a'.repeat(256) }],
    ['prefijo reservado amq.', { name: 'amq.mia' }],
    ['TTL = 0', { name: 'q.val.ttl0', messageTtlMs: 0 }],
    ['TTL negativo', { name: 'q.val.ttlneg', messageTtlMs: -1 }],
    ['maxLength = 0', { name: 'q.val.max0', maxLength: 0 }],
    ['maxLength negativo', { name: 'q.val.maxneg', maxLength: -10 }],
    ['routing key de DLX sin DLX', { name: 'q.val.rk', deadLetterRoutingKey: 'x.dlq' }],
    ['DLX con caracteres inválidos', { name: 'q.val.dlxbad', deadLetterExchange: 'mal nombre!' }],
    ['tipo de cola inexistente', { name: 'q.val.tipo', type: 'MIRRORED' }],
    ['quorum con autoDelete', { name: 'q.val.qa', type: 'QUORUM', autoDelete: true }],
    ['quorum no durable', { name: 'q.val.qd', type: 'QUORUM', durable: false }],
    ['TTL como texto', { name: 'q.val.ttltxt', messageTtlMs: 'mucho' }],
  ];
  for (const [desc, body] of colas) { const r = await post('/queues', body); check(`${desc} -> ${r.s}`, r.s === 400, `${r.s} ${r.t.slice(0, 120)}`); }
  const r422 = await post('/queues', { name: 'q.val.dlx', deadLetterExchange: 'no.existe' });
  check(`DLX inexistente -> ${r422.s} (422)`, r422.s === 422, r422.t);

  console.log('\n[2] Exchanges inválidos -> 400');
  const ex = [['nombre vacío', { name: '', type: 'DIRECT' }], ['sin tipo', { name: 'e.sin.tipo' }], ['tipo inexistente', { name: 'e.val', type: 'MAGICO' }],
    ['nombre con espacios', { name: 'mal nombre', type: 'TOPIC' }], ['prefijo amq.', { name: 'amq.x', type: 'DIRECT' }], ['256 caracteres', { name: 'e'.repeat(256), type: 'DIRECT' }]];
  for (const [desc, body] of ex) { const r = await post('/exchanges', body); check(`${desc} -> ${r.s}`, r.s === 400, `${r.s} ${r.t.slice(0, 120)}`); }
  check('borrar un exchange amq.* -> 400', (await raw('DELETE', '/exchanges/amq.direct')).s === 400);

  console.log('\n[3] Bindings inválidos -> 400');
  const bi = [['sin cola', { exchange: 'val.dead', routingKey: 'a' }], ['sin exchange', { queue: 'q.x', routingKey: 'a' }],
    ['cola vacía', { queue: '', exchange: 'val.dead', routingKey: 'a' }], ['exchange vacío', { queue: 'q.x', exchange: ' ', routingKey: 'a' }]];
  for (const [desc, body] of bi) { const r = await post('/bindings', body); check(`${desc} -> ${r.s}`, r.s === 400, `${r.s} ${r.t.slice(0, 120)}`); }
  check('desenlazar sin parámetros -> 400', (await raw('DELETE', '/bindings')).s === 400);

  console.log('\n[4] Cuerpos mal formados');
  check('JSON roto -> 400', (await raw('POST', '/queues', '{"name": ')).s === 400);
  check('cuerpo vacío -> 400', (await raw('POST', '/queues', '')).s === 400);
  check('tipo de contenido incorrecto -> 415', (await raw('POST', '/queues', 'name=q', 'text/plain')).s === 415);

  console.log('\n[5] El detalle del error indica el campo');
  const d = await post('/queues', { name: '', messageTtlMs: -5 });
  console.log('        ' + d.t.slice(0, 260));
  check('la respuesta nombra los campos inválidos (name y messageTtlMs)', /name/.test(d.t) && /messageTtlMs/.test(d.t), d.t);

  await sleep(1500);
  const after = await names();
  console.log('\n[6] El broker no cambió');
  check('mismas colas antes y después', JSON.stringify(before.queues) === JSON.stringify(after.queues), JSON.stringify(after.queues));
  const extra = after.exchanges.filter((e) => !before.exchanges.includes(e));
  check('ningún exchange nuevo', extra.length === 0, JSON.stringify(extra));

  await raw('DELETE', '/exchanges/val.dead');
  console.log(`\nRESULTADO: ${ok} PASS, ${bad} FAIL`); process.exit(bad ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
