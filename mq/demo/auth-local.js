// Emisor de tokens SOLO para la demostración: sirve las claves públicas en http://127.0.0.1:18999/jwks y deja tokens
// firmados (RS256) en ~/.campuslab-aws/demo-tokens.json. mq-admin los valida igual que validaría los de Azure AD;
// lo único que cambia es de dónde obtiene la clave pública (SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI).
//
//   node auth-local.js            # queda sirviendo en el puerto 18999
//   node auth-local.js --print admin   # imprime el token ADMIN del archivo (para pegarlo en Swagger o en curl)
const crypto = require('crypto');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const FILE = path.join(os.homedir(), '.campuslab-aws', 'demo-tokens.json');

if (process.argv[2] === '--print') {
  const tokens = JSON.parse(fs.readFileSync(FILE, 'utf8'));
  console.log(tokens[process.argv[3] || 'admin']);
  process.exit(0);
}

const TENANT = process.env.TENANT_ID || 'demo';
const ISSUER = `https://login.microsoftonline.com/${TENANT}/v2.0`;
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'demo-key', alg: 'RS256', use: 'sig' };
const b64 = (o) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

function token(email, roles) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'RS256', kid: 'demo-key', typ: 'JWT' });
  const body = b64({ iss: ISSUER, sub: email, aud: 'demo', iat: now, nbf: now - 60, exp: now + 4 * 3600, roles, email, name: email.split('@')[0] });
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${head}.${body}`), privateKey).toString('base64url');
  return `${head}.${body}.${sig}`;
}

// El archivo de tokens se escribe SOLO cuando el servidor logra quedar escuchando: si el puerto está ocupado por una
// instancia anterior, no se pisa el archivo con claves que nadie sirve.
const server = http.createServer((req, res) => {
  if (req.url === '/jwks') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ keys: [jwk] })); }
  else { res.statusCode = 404; res.end(); }
});
server.on('error', (err) => {
  console.error(err.code === 'EADDRINUSE'
    ? 'El puerto 18999 ya está ocupado (otra instancia del emisor). Ejecuta ./stop-demo.sh y vuelve a intentar.'
    : err.message);
  process.exit(1);
});
server.listen(18999, '127.0.0.1', () => {
  fs.mkdirSync(path.dirname(FILE), { recursive: true });
  fs.writeFileSync(FILE, JSON.stringify({
    admin: token('admin.demo@duocuc.cl', ['ADMIN']),
    tecnico: token('tecnico.demo@duocuc.cl', ['TECNICO']),
  }, null, 2));
  console.log(`Emisor de tokens de demo listo (tenant "${TENANT}", tokens válidos 4 h) en ${FILE}`);
});
