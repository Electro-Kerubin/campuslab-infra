// Publica un mensaje de ejemplo en el clúster de AWS, con el mismo formato que usa ms-campuslab-bookings.
//
//   ./send.sh email                  comando de email válido        -> cmd.direct  email.send
//   ./send.sh prep                   ticket de preparación válido   -> cmd.direct  prep.ticket
//   ./send.sh voucher-retiro         vale de retiro                 -> cmd.topic   voucher.retiro
//   ./send.sh voucher-devolucion     acta de devolución             -> cmd.topic   voucher.devolucion
//   ./send.sh email-invalido         email mal formado              -> DLQ (sin reintentos)
//   ./send.sh prep-invalido          falta bookingId                -> DLQ
//   ./send.sh voucher-invalido       falta el tipo                  -> DLQ
//   ./send.sh ilegible               JSON roto                      -> DLQ (lo rechaza el contenedor)
//   ./send.sh email --duplicado      el MISMO mensaje (mismo eventId) dos veces -> se procesa una sola vez
const fs = require('fs'), os = require('os'), path = require('path'), crypto = require('crypto');

const env = Object.fromEntries(fs.readFileSync(path.join(os.homedir(), '.campuslab-aws', 'rabbitmq.env'), 'utf8')
  .split(/\r?\n/).filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const API = `http://${process.env.RMQ_N1}:15672/api`;
const AUTH = 'Basic ' + Buffer.from(`${env.RABBITMQ_USER}:${env.RABBITMQ_PASS}`).toString('base64');

const envelope = (type, payload) => ({
  type, eventId: crypto.randomUUID(), traceId: crypto.randomUUID(), correlationId: crypto.randomUUID(),
  timestamp: new Date().toISOString(), payload,
});
const id = () => 1000 + Math.floor(Math.random() * 9000);
const email = (to) => envelope('email.send', { bookingId: id(), to, status: 'APROBADA', motivo: 'Tu reserva fue APROBADA' });
const prep = (p = {}) => envelope('prep.ticket', { bookingId: id(), resourceId: 1, startTime: '2026-10-28T09:00:00', studentEmail: 'alumno@duocuc.cl', ...p });
const voucher = (tipo, rk) => envelope(rk, { bookingId: id(), tipo, studentEmail: 'alumno@duocuc.cl' });

const casos = {
  'email': ['cmd.direct', 'email.send', () => email('alumno@duocuc.cl')],
  'prep': ['cmd.direct', 'prep.ticket', () => prep()],
  'voucher-retiro': ['cmd.topic', 'voucher.retiro', () => voucher('VALE_RETIRO', 'voucher.retiro')],
  'voucher-devolucion': ['cmd.topic', 'voucher.devolucion', () => voucher('ACTA_DEVOLUCION', 'voucher.devolucion')],
  'email-invalido': ['cmd.direct', 'email.send', () => email('esto-no-es-un-email')],
  'prep-invalido': ['cmd.direct', 'prep.ticket', () => { const m = prep(); delete m.payload.bookingId; return m; }],
  'voucher-invalido': ['cmd.direct', 'voucher.gen', () => envelope('voucher.gen', { bookingId: id() })],
  'ilegible': ['cmd.direct', 'email.send', () => '{esto no es json'],
};

const caso = casos[process.argv[2]];
if (!caso) { console.error('Uso: ./send.sh <' + Object.keys(casos).join('|') + '>'); process.exit(1); }

(async () => {
  const [exchange, routingKey, build] = caso;
  const body = build();
  const veces = process.argv[3] === '--duplicado' ? 2 : 1;   // misma carga y mismo eventId en cada envío
  for (let i = 1; i <= veces; i++) {
    const res = await fetch(`${API}/exchanges/%2F/${exchange}/publish`, {
      method: 'POST', headers: { Authorization: AUTH, 'Content-Type': 'application/json' },
      body: JSON.stringify({ properties: { content_type: 'application/json', delivery_mode: 2 }, routing_key: routingKey,
        payload: typeof body === 'string' ? body : JSON.stringify(body), payload_encoding: 'string' }),
    });
    const { routed } = await res.json();
    console.log(`${process.argv[2]}${veces > 1 ? ` (envío ${i}/${veces})` : ''}: publicado en ${exchange} con routing key "${routingKey}" -> ${routed ? 'ENRUTADO' : 'NO se enrutó'}`);
  }
  if (typeof body !== 'string') console.log(`  eventId=${body.eventId}`);
})().catch((e) => { console.error(e.message); process.exit(1); });
