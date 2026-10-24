// SPDX-License-Identifier: AGPL-3.0-only
// Shared V2 identity service, bound to loopback behind an explicitly configured
// HTTPS gateway. No credentials are ever submitted through the game client.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import {randomBytes,createHash,timingSafeEqual} from "node:crypto";
import {LocalCredentials,normalizeEmail} from "../../../windows/server/src/api/credentials.js";

const FLOW_TTL=5*60*1000;
const SESSION_TTL=7*24*60*60*1000;
const MAX_BODY=8192;
const VERIFIER=/^[A-Za-z0-9._~-]{43,128}$/;
const CHALLENGE=/^[A-Za-z0-9_-]{43}$/;
const FLOW_ID=/^[a-f0-9]{40}$/;
const TOKEN=/^[a-f0-9]{64}$/;
const MAX_FLOWS=1000;
const MAX_SESSIONS=3000;
function hash(s){return createHash("sha256").update(s).digest("hex");}
function equal(a,b){return typeof a==="string"&&typeof b==="string"&&
  Buffer.byteLength(a)===Buffer.byteLength(b)&&
  timingSafeEqual(Buffer.from(a),Buffer.from(b));}
function fail(status,message){const e=Error(message);e.status=status;throw e;}
function send(res,status,body){
  res.statusCode=status;
  res.setHeader("Cache-Control","no-store");
  res.setHeader("X-Content-Type-Options","nosniff");
  res.setHeader("Content-Type","application/json; charset=utf-8");
  res.end(JSON.stringify(body));
}
function escapeHTML(s){return String(s).replace(/[&<>"']/g,ch=>({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
})[ch]);}
function html(res,status,body,secure){
  res.statusCode=status;
  res.setHeader("Cache-Control","no-store");
  res.setHeader("Content-Type","text/html; charset=utf-8");
  res.setHeader("X-Frame-Options","DENY");
  res.setHeader("Referrer-Policy","no-referrer");
  res.setHeader("Content-Security-Policy","default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");
  if(secure)res.setHeader("Strict-Transport-Security","max-age=31536000");
  res.end('<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'+
    '<title>Moo-IO — Conta</title><style>body{background:#101a25;color:#edf8fc;font:16px system-ui;margin:0}'+
    'main{max-width:440px;margin:6vh auto;padding:30px;background:#1a2a37;border:1px solid #335468;border-radius:16px}'+
    'input,button{width:100%;box-sizing:border-box;padding:13px;margin:8px 0 16px;border:1px solid #406278;border-radius:8px;font:inherit}'+
    'input{background:#0c1924;color:white}button{background:#23d0af;color:#072b2d;font-weight:bold;cursor:pointer}'+
    'label{display:block;font-size:13px;color:#bdd2e0}p{color:#a7c0cf;line-height:1.5}</style>'+
    '<main><h1>Moo-IO</h1>'+body+'</main></html>');
}
function readBody(req,type){
  return new Promise((resolve,reject)=>{
    if(!String(req.headers["content-type"]||"").startsWith(type))
      return reject(Object.assign(Error("Tipo de conteudo invalido"),{status:415}));
    let total=0,buf="";
    req.on("data",data=>{
      total+=data.length;
      if(total>MAX_BODY){reject(Object.assign(Error("Requisicao muito grande"),{status:413}));req.destroy();}
      else buf+=data.toString("utf8");
    });
    req.on("end",()=>{
      try{resolve(type==="application/json"?JSON.parse(buf):Object.fromEntries(new URLSearchParams(buf)));}
      catch{reject(Object.assign(Error("Corpo invalido"),{status:400}));}
    });
    req.on("error",reject);
  });
}
function privateFolder(dir){
  fs.mkdirSync(dir,{recursive:true,mode:0o700});
  const stat=fs.lstatSync(dir);
  if(!stat.isDirectory()||stat.isSymbolicLink()||(process.platform!=="win32"&&(stat.mode&0o077)))
    throw Error("Diretorio de contas deve ser privado (0700)");
}
function secretIn(dir){
  const file=path.join(dir,"hub.secret");
  if(!fs.existsSync(file))fs.writeFileSync(file,randomBytes(32).toString("hex"),{flag:"wx",mode:0o600});
  const st=fs.lstatSync(file);
  if(!st.isFile()||st.isSymbolicLink()||st.size!==64||
    (process.platform!=="win32"&&(st.mode&0o077)))
    throw Error("Segredo interno invalido ou inseguro");
  const s=fs.readFileSync(file,"utf8");
  if(!TOKEN.test(s))throw Error("Segredo interno invalido");
  return s;
}
export function publicOrigin(value){
  if(typeof value!=="string")throw Error("AUTH_ORIGIN obrigatorio");
  const url=new URL(value);
  if(url.username||url.password||url.search||url.hash||url.pathname!=="/")
    throw Error("AUTH_ORIGIN deve ser somente esquema HTTPS e host");
  const local=url.protocol==="http:"&&["127.0.0.1","localhost"].includes(url.hostname);
  if(url.protocol!=="https:"&&!local)throw Error("Login publico exige HTTPS");
  return url.origin;
}
export async function createIdentityService({dataDir,origin,port=8788,host="127.0.0.1",allowRegistration=true,logger=()=>{}}){
  if(host!=="127.0.0.1"||!Number.isInteger(port)||port<1024||port>65534)
    throw Error("Identidade aceita somente bind em 127.0.0.1, porta 1024-65534");
  const publicUrl=publicOrigin(origin),secure=publicUrl.startsWith("https:");
  privateFolder(dataDir);
  const internal=secretIn(dataDir);
  const credentials=new LocalCredentials(dataDir);
  const sessionsFile=path.join(dataDir,"hub-sessions.json");
  let sessions={};
  if(fs.existsSync(sessionsFile)){
    const st=fs.lstatSync(sessionsFile);
    if(!st.isFile()||st.isSymbolicLink()||st.size>1024*1024||
       (process.platform!=="win32"&&(st.mode&0o077)))throw Error("Sessoes armazenadas de forma insegura");
    const parsed=JSON.parse(fs.readFileSync(sessionsFile,"utf8"));
    if(parsed?.schemaVersion!==1||typeof parsed.sessions!=="object"||!parsed.sessions||
      Array.isArray(parsed.sessions)||Object.keys(parsed.sessions).length>MAX_SESSIONS)
      throw Error("Sessoes invalidas");
    sessions=parsed.sessions;
  }
  function persist(){
    const file=sessionsFile+"."+randomBytes(6).toString("hex")+".tmp";
    fs.writeFileSync(file,JSON.stringify({schemaVersion:1,sessions}),{flag:"wx",mode:0o600});
    try{fs.renameSync(file,sessionsFile);}finally{if(fs.existsSync(file))fs.unlinkSync(file);}
  }
  const flows=new Map(),attempts=new Map();
  let serialized=Promise.resolve();
  const queue=fn=>{const next=serialized.then(fn);serialized=next.catch(()=>{});return next;};
  function rate(key,max){
    const now=Date.now(),prev=attempts.get(key);
    const x=prev&&now-prev.start<600000?prev:{start:now,hits:0};
    x.hits++;attempts.set(key,x);
    if(attempts.size>4000)attempts.clear();
    if(x.hits>max)fail(429,"Muitas tentativas; tente novamente depois.");
  }
  function clean(){
    const now=Date.now();
    for(const [key,flow] of flows)if(flow.until<now)flows.delete(key);
    let changed=false;
    for(const [key,session] of Object.entries(sessions))
      if(!session||session.until<=now){delete sessions[key];changed=true;}
    if(changed)persist();
  }
  function originAllowed(req){
    if(req.headers.origin!==publicUrl)fail(403,"Origem nao autorizada");
  }
  async function handle(req,res){
    try{
      const url=new URL(req.url,publicUrl);
      if(url.origin!==publicUrl)fail(400,"Destino invalido");
      if(req.headers.host!==new URL(publicUrl).host)fail(403,"Host nao autorizado");
      if(url.pathname==="/health"&&req.method==="GET")
        return send(res,200,{service:"Moo-IO V2 identity",ok:true});
      if(url.pathname==="/v1/authorize/start"&&req.method==="POST"){
        const body=await readBody(req,"application/json");
        if(!CHALLENGE.test(body.challenge))fail(400,"PKCE challenge invalido");
        rate("start:"+req.socket.remoteAddress,50);
        clean();
        if(flows.size>=MAX_FLOWS)fail(503,"Muitas autorizacoes pendentes");
        const id=randomBytes(20).toString("hex");
        flows.set(id,{challenge:body.challenge,until:Date.now()+FLOW_TTL,approved:null,csrf:null});
        return send(res,200,{id,verificationUri:publicUrl+"/login?id="+id,
          expiresIn:300,interval:2});
      }
      if(url.pathname==="/v1/authorize/token"&&req.method==="POST"){
        const body=await readBody(req,"application/json");
        if(!FLOW_ID.test(body.id)||!VERIFIER.test(body.verifier))fail(400,"Autorizacao invalida");
        const flow=flows.get(body.id);
        if(!flow||flow.until<Date.now())fail(410,"Autorizacao expirada");
        const expected=createHash("sha256").update(body.verifier,"ascii").digest("base64url");
        if(!equal(expected,flow.challenge))fail(403,"PKCE invalido");
        if(!flow.approved)return send(res,202,{status:"pending"});
        const email=flow.approved;
        flows.delete(body.id);
        clean();
        if(Object.keys(sessions).length>=MAX_SESSIONS)fail(503,"Limite de sessoes atingido");
        const token=randomBytes(32).toString("hex"),until=Date.now()+SESSION_TTL;
        sessions[hash(token)]={email,until};
        persist();
        return send(res,200,{token,tokenType:"Bearer",expiresAt:until});
      }
      if(url.pathname==="/v1/session/revoke"&&req.method==="POST"){
        const token=String(req.headers.authorization||"").replace(/^Bearer /,"");
        if(!TOKEN.test(token))fail(401,"Sessao invalida");
        if(sessions[hash(token)]){delete sessions[hash(token)];persist();}
        return send(res,200,{revoked:true});
      }
      if(url.pathname==="/internal/introspect"&&req.method==="POST"){
        const local=["127.0.0.1","::ffff:127.0.0.1","::1"].includes(req.socket.remoteAddress);
        if(!local||req.headers["x-forwarded-for"]||req.headers.forwarded||
           !equal(req.headers["x-mooio-internal-secret"],internal))
          fail(403,"Acesso interno recusado");
        const body=await readBody(req,"application/json");
        if(typeof body.token!=="string"||!TOKEN.test(body.token))
          return send(res,200,{active:false});
        const session=sessions[hash(body.token)];
        return send(res,200,session&&session.until>Date.now()&&credentials.users[session.email]?
          {active:true,email:session.email}:{active:false});
      }
      if(url.pathname==="/login"&&req.method==="GET"){
        const id=url.searchParams.get("id");
        if(!id||!FLOW_ID.test(id)||!flows.has(id)||flows.get(id).until<Date.now())
          return html(res,410,"<h2>Pedido expirado</h2><p>Volte ao jogo e solicite outro login.</p>",secure);
        const flow=flows.get(id);
        flow.csrf=randomBytes(24).toString("hex");
        res.setHeader("Set-Cookie","mooio_login_csrf="+flow.csrf+
          "; HttpOnly; SameSite=Strict; Path=/login; Max-Age=300"+(secure?"; Secure":""));
        const section=flow.approved?"<p>Conta autorizada. Volte ao Moo-IO.</p>":
          '<p>Entre ou crie uma conta para autorizar seu jogo. Sua senha não é enviada ao cliente.</p>'+
          '<form action="/login/submit" method="post">'+
          '<input type="hidden" name="id" value="'+id+'"><input type="hidden" name="csrf" value="'+flow.csrf+'">'+
          '<label>E-mail<input type="email" name="email" autocomplete="username" maxlength="120" required></label>'+
          '<label>Senha<input type="password" name="password" autocomplete="current-password" minlength="12" maxlength="128" required></label>'+
          '<button name="action" value="login">Entrar e autorizar</button>'+
          (allowRegistration?'<button name="action" value="register">Criar conta e autorizar</button>':'')+
          '</form><p>Use somente a página HTTPS do servidor em que confia.</p>';
        return html(res,200,section,secure);
      }
      if(url.pathname==="/login/submit"&&req.method==="POST"){
        originAllowed(req);
        const body=await readBody(req,"application/x-www-form-urlencoded");
        const flow=FLOW_ID.test(body.id||"")?flows.get(body.id):null;
        if(!flow||flow.until<Date.now()||flow.approved)fail(410,"Pedido expirado ou concluido");
        const match=/(?:^|;\s*)mooio_login_csrf=([a-f0-9]{48})(?:;|$)/.exec(req.headers.cookie||"");
        if(!match||!equal(match[1],flow.csrf)||!equal(body.csrf,flow.csrf))
          fail(403,"CSRF invalido");
        rate("login:"+req.socket.remoteAddress,20);
        const email=normalizeEmail(body.email);
        const password=body.password;
        if(!email||typeof password!=="string")fail(400,"Credenciais invalidas");
        if(body.action==="register"&&allowRegistration){
          await queue(async()=>{
            if(credentials.users[email])fail(400,"Conta existente; use Entrar");
            await credentials.set(email,password);
          });
        }else if(body.action==="login"){
          if(!await credentials.verify(email,password))fail(401,"Credenciais invalidas");
        }else fail(400,"Acao invalida");
        flow.approved=email;
        logger("Browser authorization approved (account identifier omitted)");
        return html(res,200,"<h2>Acesso autorizado</h2><p>Você já pode voltar ao Moo-IO. Esta página não envia sua senha ao jogo.</p>",secure);
      }
      fail(404,"Rota nao encontrada");
    }catch(error){
      if(res.destroyed||res.writableEnded)return;
      logger("Auth request denied: "+(error.status||500));
      return send(res,error.status||500,{error:error.status?error.message:"Falha interna"});
    }
  }
  const server=http.createServer((req,res)=>void handle(req,res));
  await new Promise((resolve,reject)=>{
    server.once("error",reject);
    server.listen(port,host,()=>{server.removeListener("error",reject);resolve();});
  });
  return {server,port,origin:publicUrl,secretFile:path.join(dataDir,"hub.secret"),
    close:()=>new Promise(resolve=>server.close(resolve))};
}
