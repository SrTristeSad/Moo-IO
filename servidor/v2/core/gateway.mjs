// SPDX-License-Identifier: AGPL-3.0-only
// Caddy front door for multiple V2 rooms. Does not open ports or install Caddy.
// Every backend MUST be bound to loopback; no public access to game ports.
import { discoverRooms, checkRooms } from "./supervisor.mjs";

function validDnsLabel(input){
  return typeof input==="string" && input.length<=63 &&
    /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(input);
}
export function validateBaseDomain(value){
  if(typeof value!=="string"||value.length>190||value!==value.toLowerCase()||
    value.includes("://")||value.endsWith(".")||value.includes(":"))
    throw Error("Dominio invalido. Informe apenas o nome DNS em letras minusculas, sem https://, porta ou barra.");
  const labels=value.split(".");
  if(labels.length<2||labels.some(label=>!validDnsLabel(label))||
    labels[labels.length-1].length<2||/^[0-9]+$/.test(labels.at(-1))||
    labels[0]==="localhost"||labels.at(-1)==="local"||
    labels.at(-1)==="localhost")
    throw Error("Dominio DNS invalido; requer dominio publico e rotulos DNS validos.");
  return value;
}
export function buildGatewayPlan(entries,{domain}){
  validateBaseDomain(domain);
  if(!Array.isArray(entries)||entries.length===0)throw Error("Nenhuma sala configurada.");
  const hosts=new Set();
  return entries.map(({id,room})=>{
    if(!validDnsLabel(id)||id.startsWith("-"))
      throw Error("ID de sala inadequado para subdominio DNS: "+id+". Use letras minusculas, numeros e hifens.");
    if(!room||room.host!=="127.0.0.1"||room.network!=="lan")
      throw Error("Gateway publico exige sala '"+id+"' apenas em 127.0.0.1, rede lan. Nao publique LAN ou VPN no proxy.");
    if(!Number.isInteger(room.port)||room.port<1024||room.port>65534)
      throw Error("Porta de sala invalida: "+id);
    const hostname=id+"."+domain;
    if(hostname.length>253||hosts.has(hostname))throw Error("Dominio publico duplicado ou longo: "+hostname);
    hosts.add(hostname);
    return {id,hostname,upstream:"127.0.0.1:"+room.port,port:room.port};
  });
}
export async function gatewayPlan({rooms,domain}){
  const entries=await checkRooms(discoverRooms(rooms));
  return buildGatewayPlan(entries,{domain});
}
export function renderCaddyfile(plan,{identityHost=null,identityPort=8788}={}){
  if(!Array.isArray(plan)||!plan.length)throw Error("Plano de gateway vazio");
  // Do not interpolate any user-controlled Caddy directives. Hostname and port
  // are previously checked against strict DNS/numeric patterns.
  const all=[];
  all.push("# Moo-IO V2 - gerado automaticamente. NAO expor as portas internas.");
  all.push("# Caddy gerencia automaticamente HTTPS e WebSocket (WSS) em cada hostname.");
  all.push("# Configure DNS A/AAAA de cada hostname e libere 80/443 SOMENTE no gateway.");
  all.push("");
  for(const {hostname,upstream} of plan){
    // Validate even when called directly, outside buildGatewayPlan.
    const split=hostname.split(".");
    if(split.length<3||split.some(x=>!validDnsLabel(x))||!/^127\.0\.0\.1:[0-9]{4,5}$/.test(upstream))
      throw Error("Plano de gateway invalido; nao renderizar Caddyfile.");
    all.push(hostname+" {");
    all.push("    encode zstd gzip");
    all.push("    header {");
    all.push('        Strict-Transport-Security "max-age=31536000"');
    all.push('        X-Content-Type-Options "nosniff"');
    all.push("    }");
    all.push("    route {");
    // Defense in depth: backend also protects privileged endpoints.
    all.push("        @internal path /admin/* /mooio/shutdown /mooio/status");
    all.push("        respond @internal 404");
    all.push("        reverse_proxy "+upstream+" {");
    all.push("            header_up Host {host}");
    all.push("            header_up -Forwarded");
    // Use the actual Caddy TCP peer rather than user-controlled XFF headers.
    // A CDN in front of this gateway is NOT supported by this config.
    all.push("            header_up X-Forwarded-For {remote_host}");
    all.push("            header_up X-Real-IP {remote_host}");
    all.push("            header_up X-Forwarded-Host {host}");
    all.push("            header_up X-Forwarded-Proto https");
    all.push("        }");
    all.push("    }");
    all.push("}");
    all.push("");
  }
  if(identityHost!==null){
    const parts=identityHost.split(".");
    if(parts.length<3||parts.some(x=>!validDnsLabel(x))||
       !Number.isInteger(identityPort)||identityPort<1024||identityPort>65534||
       plan.some(x=>x.hostname===identityHost))
      throw Error("Hostname/porta do login publico invalidos ou duplicados");
    all.push("# Login via navegador: somente rotas publicas explicitamente permitidas.");
    all.push(identityHost+" {");
    all.push("    encode zstd gzip");
    all.push("    header {");
    all.push('        Strict-Transport-Security "max-age=31536000"');
    all.push('        X-Content-Type-Options "nosniff"');
    all.push("    }");
    all.push("    @auth_public path /login /login/submit /v1/authorize/start /v1/authorize/token /v1/session/revoke /health");
    all.push("    handle @auth_public {");
    all.push("        reverse_proxy 127.0.0.1:"+identityPort+" {");
    all.push("            header_up Host {host}");
    all.push("            header_up -Forwarded");
    all.push("            header_up X-Forwarded-For {remote_host}");
    all.push("            header_up X-Forwarded-Proto https");
    all.push("        }");
    all.push("    }");
    all.push("    respond 404");
    all.push("}");
    all.push("");
  }
  return all.join("\n");
}
