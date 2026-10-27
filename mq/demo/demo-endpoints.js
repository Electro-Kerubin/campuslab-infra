// Demostración de los endpoints de ms-campuslab-mq-admin contra el clúster de AWS: exchanges direct/topic, colas, bindings, enrutamiento y borrado.
// Uso: ./run-demo-endpoints.sh  (necesita ./start-mq-admin.sh en marcha). Crea y borra sus propios recursos demo.*; no toca la topología de la aplicación.
const fs = require('fs'), os = require('os'), path = require('path');
const T = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.campuslab-aws', 'demo-tokens.json'), 'utf8'));
const env = Object.fromEntries(fs.readFileSync(path.join(os.homedir(), '.campuslab-aws/rabbitmq.env'), 'utf8')
  .split(/\r?\n/).filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const ADM = 'http://127.0.0.1:8085/api/mq', RMQ = `http://${process.env.RMQ_N1}:15672/api`;
const basic = 'Basic ' + Buffer.from(`${env.RABBITMQ_USER}:${env.RABBITMQ_PASS}`).toString('base64');
let ok = 0, bad = 0;
const check = (n, c, d = '') => { c ? (ok++, console.log('  PASS  ' + n)) : (bad++, console.log('  FAIL  ' + n + '  ' + d)); };
const adm = async (m, p, who, b) => {
  const r = await fetch(ADM + p, { method: m, headers: { ...(who ? { Authorization: 'Bearer ' + T[who] } : {}), 'Content-Type': 'application/json' }, body: b ? JSON.stringify(b) : undefined });
  const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch { /* sin cuerpo */ }
  return { s: r.status, j, t, loc: r.headers.get('location') };
};
const publish = async (ex, rk) => {
  const r = await fetch(`${RMQ}/exchanges/%2F/${ex}/publish`, { method: 'POST', headers: { Authorization: basic, 'Content-Type': 'application/json' },
    body: JSON.stringify({ properties: { delivery_mode: 2 }, routing_key: rk, payload: 'x', payload_encoding: 'string' }) });
  return (await r.json()).routed;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const depth = async (q) => { await sleep(300); const r = await adm('GET', '/queues/' + q, 'admin'); return r.j; };

(async () => {
  console.log('\n[1] Seguridad');
  check('sin token -> 401', (await adm('POST', '/queues', null, { name: 'q.x' })).s === 401);
  check('rol TECNICO -> 403', (await adm('POST', '/queues', 'tecnico', { name: 'q.x' })).s === 403);

  console.log('\n[2] Exchanges: direct y topic');
  let r = await adm('POST', '/exchanges', 'admin', { name: 'demo.cmd.direct', type: 'DIRECT' }); check('POST /exchanges DIRECT -> 201 + Location', r.s === 201 && !!r.loc, r.t);
  r = await adm('POST', '/exchanges', 'admin', { name: 'demo.cmd.topic', type: 'TOPIC' }); check('POST /exchanges TOPIC -> 201', r.s === 201, r.t);
  r = await adm('POST', '/exchanges', 'admin', { name: 'demo.dead', type: 'DIRECT' }); check('POST /exchanges dead letter -> 201', r.s === 201, r.t);
  check('exchange repetido -> 409', (await adm('POST', '/exchanges', 'admin', { name: 'demo.cmd.direct', type: 'DIRECT' })).s === 409);
  check('nombre reservado amq.* -> 400', (await adm('POST', '/exchanges', 'admin', { name: 'amq.mio', type: 'DIRECT' })).s === 400);
  check('tipo inexistente -> 400', (await adm('POST', '/exchanges', 'admin', { name: 'demo.x', type: 'MAGICO' })).s === 400);
  const ex = await (await fetch(`${RMQ}/exchanges/%2F`, { headers: { Authorization: basic } })).json();
  const tipo = (n) => ex.find((e) => e.name === n)?.type;
  check('en el broker: demo.cmd.direct es direct y demo.cmd.topic es topic', tipo('demo.cmd.direct') === 'direct' && tipo('demo.cmd.topic') === 'topic', `${tipo('demo.cmd.direct')}/${tipo('demo.cmd.topic')}`);

  console.log('\n[3] Colas');
  const q = (name, rk) => ({ name, messageTtlMs: 60000, maxLength: 1000, deadLetterExchange: 'demo.dead', deadLetterRoutingKey: rk });
  for (const [n, rk] of [['q.demo.email', 'email.dlq'], ['q.demo.prep', 'prep.dlq'], ['q.demo.voucher', 'voucher.dlq'], ['q.demo.actas', 'actas.dlq']]) {
    r = await adm('POST', '/queues', 'admin', q(n, rk)); check(`POST /queues ${n} -> 201`, r.s === 201, r.t);
  }
  check('cola con DLX inexistente -> 422', (await adm('POST', '/queues', 'admin', { name: 'q.demo.mala', deadLetterExchange: 'no.existe' })).s === 422);
  check('cola repetida -> 409', (await adm('POST', '/queues', 'admin', q('q.demo.email', 'email.dlq'))).s === 409);
  check('TTL negativo -> 400', (await adm('POST', '/queues', 'admin', { name: 'q.demo.neg', messageTtlMs: -5 })).s === 400);
  const qs = await (await fetch(`${RMQ}/queues/%2F/q.demo.email`, { headers: { Authorization: basic } })).json();
  check('en el broker: durable, TTL y DLX configurados', qs.durable && qs.arguments['x-message-ttl'] === 60000 && qs.arguments['x-dead-letter-exchange'] === 'demo.dead', JSON.stringify(qs.arguments));

  console.log('\n[4] Bindings: direct (clave exacta) vs topic (patrón)');
  const bind = (queue, exchange, routingKey) => adm('POST', '/bindings', 'admin', { queue, exchange, routingKey });
  for (const [qq, e, k] of [['q.demo.email', 'demo.cmd.direct', 'email.send'], ['q.demo.prep', 'demo.cmd.topic', 'prep.#'], ['q.demo.voucher', 'demo.cmd.topic', 'voucher.*'], ['q.demo.actas', 'demo.cmd.topic', 'voucher.devolucion']]) {
    r = await bind(qq, e, k); check(`POST /bindings ${qq} <- ${e} [${k}] -> 201`, r.s === 201, r.t);
  }
  check('binding a cola inexistente -> 404', (await bind('q.no.existe', 'demo.cmd.direct', 'a')).s === 404);

  console.log('\n[5] Matriz de enrutamiento (se publica y se mide cada cola con GET /queues/{name})');
  const casos = [
    ['demo.cmd.direct', 'email.send', true],          // direct: clave exacta
    ['demo.cmd.direct', 'email.otra', false],         // direct: otra clave no coincide
    ['demo.cmd.topic', 'prep.ticket', true],          // prep.# cubre una palabra...
    ['demo.cmd.topic', 'prep.sala.urgente', true],    // ...y varias
    ['demo.cmd.topic', 'voucher.retiro', true],       // voucher.* = exactamente una palabra
    ['demo.cmd.topic', 'voucher.devolucion', true],   // una clave, DOS colas (voucher.* y voucher.devolucion)
    ['demo.cmd.topic', 'voucher.a.b', false],         // * no cubre dos palabras
    ['demo.cmd.topic', 'email.send', false],          // el topic no tiene binding de email
  ];
  for (const [e, k, esperado] of casos) { const routed = await publish(e, k); check(`${e.replace('demo.cmd.', '')}  ${k}  -> routed=${routed}`, routed === esperado); }
  await sleep(1500);
  const esperadas = { 'q.demo.email': 1, 'q.demo.prep': 2, 'q.demo.voucher': 2, 'q.demo.actas': 1 };
  for (const [n, c] of Object.entries(esperadas)) { const d = await depth(n); console.log('        GET /queues/' + n + ' ->', JSON.stringify(d)); check(`${n}: ${c} mensaje(s)`, JSON.stringify(d).includes(`:${c}`) , JSON.stringify(d)); }

  console.log('\n[6] Desenlazar, vaciar y eliminar');
  r = await adm('DELETE', '/bindings?queue=q.demo.actas&exchange=demo.cmd.topic&routingKey=voucher.devolucion', 'admin'); check('DELETE /bindings -> 204', r.s === 204, r.t);
  check('tras desenlazar, voucher.devolucion llega solo a voucher', (await publish('demo.cmd.topic', 'voucher.devolucion')) === true);
  r = await adm('DELETE', '/queues/q.demo.prep/messages', 'admin'); check('DELETE /queues/{name}/messages -> 200', r.s === 200, r.t); console.log('        ', r.t);
  for (const n of ['q.demo.email', 'q.demo.prep', 'q.demo.voucher', 'q.demo.actas']) { r = await adm('DELETE', '/queues/' + n, 'admin'); check(`DELETE /queues/${n} -> 204`, r.s === 204, r.t); }
  check('DELETE de cola inexistente -> 404', (await adm('DELETE', '/queues/q.demo.email', 'admin')).s === 404);
  for (const n of ['demo.cmd.direct', 'demo.cmd.topic', 'demo.dead']) { r = await adm('DELETE', '/exchanges/' + n, 'admin'); check(`DELETE /exchanges/${n} -> 204`, r.s === 204, r.t); }
  console.log(`\nRESULTADO: ${ok} PASS, ${bad} FAIL`); process.exit(bad ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
