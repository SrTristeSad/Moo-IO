// SPDX-License-Identifier: AGPL-3.0-only
// Browser controls for the loopback-only server panel. No third-party scripts.
const $=id=>document.getElementById(id);
const state={csrf:null,rooms:[],mods:[],editing:null,role:null};
let timer=null,toastTimer=null;
function notify(message,isError=false){
  const el=$("notice");
  el.textContent=String(message);
  el.classList.toggle("error",isError);
  el.classList.remove("hidden");
  clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>el.classList.add("hidden"),6500);
}
async function api(url,method="GET",body=null){
  const options={method,credentials:"same-origin",headers:{"Accept":"application/json"}};
  if(body!==null){options.headers["Content-Type"]="application/json";options.body=JSON.stringify(body);}
  if(method!=="GET"&&url!=="/api/login")options.headers["X-CSRF-Token"]=state.csrf||"";
  const response=await fetch(url,options);
  let data;
  try{data=await response.json();}catch{throw Error("Resposta invalida do servidor");}
  if(!response.ok){
    if(response.status===401&&url!=="/api/login")showLogin();
    throw Error(data.error||"Requisicao nao concluida");
  }
  return data;
}
function showLogin(){
  $("login").classList.remove("hidden");
  $("dashboard").classList.add("hidden");
  $("logout").classList.add("hidden");
  clearInterval(timer);timer=null;
}
function showDashboard(){
  $("new-room").classList.toggle("hidden",state.role!=="owner");
  $("login").classList.add("hidden");
  $("dashboard").classList.remove("hidden");
  $("logout").classList.remove("hidden");
  if(!timer)timer=setInterval(()=>void refresh(),15000);
}
function element(tag,text,cls){
  const el=document.createElement(tag);
  if(text!==undefined&&text!==null)el.textContent=String(text);
  if(cls)el.className=cls;
  return el;
}
function append(parent,...nodes){nodes.forEach(node=>parent.appendChild(node));return parent;}
function summary(room){
  return [room.host+":"+room.port,room.players+"/"+room.capacity+" jogadores",
    room.preset==="traditional"?"Tradicional":"Personalizada",
    room.mods.length+" mods",room.bots+" bots"];
}
function renderRooms(){
  const list=$("rooms");
  list.replaceChildren();
  if(!state.rooms.length){
    const empty=element("div","Nenhuma sala criada. Clique em “Criar sala” para começar.","card room");
    list.append(empty);
    return;
  }
  for(const room of state.rooms){
    const card=element("article",null,"card room");
    const info=element("div"),head=element("div",null,"room-top");
    append(head,element("strong",room.name),element("span",room.online?"ONLINE":"OFFLINE","pill"+(room.online?"":" off")));
    const meta=element("div",null,"meta");
    for(const label of summary(room))append(meta,element("span",label));
    append(info,head,meta);
    if(room.reason&&!room.online)append(info,element("div",room.reason,"room-error"));
    const buttons=element("div",null,"room-buttons");
    const configure=element("button","Configurar","subtle");
    configure.type="button";
    configure.addEventListener("click",()=>editRoom(room));
    const restart=element("button","Reiniciar sala","subtle");
    restart.type="button";
    restart.addEventListener("click",async()=>{
      if(!confirm("Reiniciar apenas “"+room.name+"”? Jogadores desta sala serão desconectados."))return;
      restart.disabled=true;
      try{
        const data=await api("/api/rooms/"+encodeURIComponent(room.id)+"/restart","POST",{});
        notify("Sala "+room.id+": "+(data.result?.status||"reiniciada")+". Outras salas preservadas.");
        await refresh();
      }catch(error){notify(error.message,true);}
      finally{restart.disabled=false;}
    });
    if(!room.online){
      const start=element("button","Iniciar sala","primary");
      start.type="button";
      start.addEventListener("click",async()=>{
        start.disabled=true;
        try{
          const data=await api("/api/rooms/"+encodeURIComponent(room.id)+"/start","POST",{});
          notify("Sala "+room.id+": "+(data.result?.status||"iniciando")+".");
          await refresh();
        }catch(error){notify(error.message,true);}
        finally{start.disabled=false;}
      });
      buttons.append(start);
    }
    const stop=element("button","Encerrar sala","subtle");
    stop.type="button";
    stop.addEventListener("click",async()=>{
      if(!confirm("Encerrar somente “"+room.name+"”? Os jogadores desta sala serão desconectados e a sala NÃO reiniciará automaticamente."))return;
      stop.disabled=true;
      try{
        const result=await api("/api/rooms/"+encodeURIComponent(room.id)+"/stop","POST",{});
        notify("Sala "+room.id+": "+result.result.status+". As outras salas continuam.");
        await refresh();
      }catch(error){notify(error.message,true);}
      finally{stop.disabled=false;}
    });
    const playersButton=element("button","Jogadores","subtle");
    playersButton.type="button";
    playersButton.addEventListener("click",async()=>{
      playersButton.disabled=true;
      try{
        const data=await api("/api/rooms/"+encodeURIComponent(room.id)+"/players");
        const old=card.querySelector(".player-list");
        if(old){old.remove();return;}
        const container=element("div",null,"player-list");
        const users=Array.isArray(data.players)?data.players:[];
        if(!users.length)container.append(element("span","Nenhum jogador conectado."));
        for(const user of users){
          const line=element("div",null,"player-row");
          const role={admin:"Administrador",mod:"Moderador",player:"Jogador",guest:"Convidado"}[user.role]||"Jogador";
          const name=element("span",user.name+" · "+role+" · "+user.id.slice(0,8));
          line.append(name);
          if(state.role!=="viewer"&&user.role!=="mod"&&user.role!=="admin"){
            const kick=element("button","Expulsar","subtle");
            kick.type="button";
            kick.addEventListener("click",async()=>{
              if(!confirm("Expulsar “"+user.name+"” somente desta partida?"))return;
              kick.disabled=true;
              try{
                await api("/api/rooms/"+encodeURIComponent(room.id)+"/kick","POST",{playerId:user.id});
                notify("Sessao "+user.id.slice(0,8)+" expulsa de "+room.name+".");
                container.remove();
                await refresh();
              }catch(error){notify(error.message,true);kick.disabled=false;}
            });
            line.append(kick);
            const ban=element("button","Banir","subtle");
            ban.type="button";
            ban.addEventListener("click",async()=>{
              const chosen=prompt("Duração: 5, 15, 60, 360, 1440 ou 10080 minutos","60");
              if(chosen===null)return;
              const minutes=Number(chosen);
              if(![5,15,60,360,1440,10080].includes(minutes)){
                notify("Duração não permitida",true);return;
              }
              const reason=prompt("Motivo (opcional, até 120 caracteres)","") ;
              if(reason===null)return;
              if(reason.length>120){notify("Motivo muito longo",true);return;}
              if(!confirm("Banir "+user.name+" por "+minutes+" minutos nesta sala?"))return;
              try{
                const result=await api("/api/rooms/"+encodeURIComponent(room.id)+"/ban","POST",
                  {playerId:user.id,minutes,reason});
                notify("Banimento ativo até "+new Date(result.result.until).toLocaleString("pt-BR"));
                container.remove();await refresh();
              }catch(error){notify(error.message,true);}
            });
            line.append(ban);
          }
          container.append(line);
        }
        info.append(container);
      }catch(error){notify(error.message,true);}
      finally{playersButton.disabled=false;}
    });
    const events=element("button","Eventos","subtle");
    events.type="button";
    events.addEventListener("click",async()=>{
      events.disabled=true;
      try{
        const result=await api("/api/rooms/"+encodeURIComponent(room.id)+"/events");
        const names={
          started:"Sala iniciada",restarting:"Reinicio solicitado",stopped:"Parada pelo administrador",
          crashed:"Processo encerrou inesperadamente",watchdog:"Watchdog detectou falha",
          disabled:"Desativada apos repetidas falhas"
        };
        const lines=(result.events||[]).map(row=>row.at+"  "+(names[row.kind]||"Evento"));
        const viewer=element("pre",lines.join("\n")||"Nenhum evento recente.","event-log");
        const old=card.querySelector(".event-log");
        if(old)old.remove();
        else info.append(viewer);
      }catch(error){notify(error.message,true);}
      finally{events.disabled=false;}
    });
    if(state.role==="owner")append(buttons,configure,restart,stop);
    append(buttons,playersButton);
    if(state.role==="owner")buttons.append(events);
    const modBtn=element("button","Moderação","subtle");
    modBtn.type="button";
    modBtn.addEventListener("click",async()=>{
      modBtn.disabled=true;
      try{
        const [activity,active]=await Promise.all([
          api("/api/rooms/"+encodeURIComponent(room.id)+"/history"),
          state.role==="viewer"?Promise.resolve({bans:[]}):api("/api/rooms/"+encodeURIComponent(room.id)+"/bans")
        ]);
        const old=card.querySelector(".moderation-list");
        if(old){old.remove();return;}
        const box=element("div",null,"moderation-list");
        box.append(element("strong","Histórico recente"));
        for(const e of (activity.history||[]).slice(0,50)){
          box.append(element("div",e.at+" · "+e.action+" · "+e.name+
            (e.minutes?" ("+e.minutes+" min)":"")+(e.reason?" · "+e.reason:""),"moderation-row"));
        }
        if(state.role!=="viewer"){
          box.append(element("strong","Banimentos ativos"));
          for(const b of active.bans||[]){
            const line=element("div",null,"moderation-row");
            line.append(element("span",b.name+" · até "+new Date(b.until).toLocaleString("pt-BR")));
            const remove=element("button","Revogar","subtle");
            remove.type="button";
            remove.addEventListener("click",async()=>{
              if(!confirm("Revogar o banimento temporário de "+b.name+"?"))return;
              try{
                await api("/api/rooms/"+encodeURIComponent(room.id)+"/unban","POST",{banId:b.id});
                notify("Banimento revogado");box.remove();
              }catch(error){notify(error.message,true);}
            });
            line.append(remove);box.append(line);
          }
        }
        info.append(box);
      }catch(error){notify(error.message,true);}
      finally{modBtn.disabled=false;}
    });
    buttons.append(modBtn);
    append(card,info,buttons);
    list.append(card);
  }
}
function renderMods(){
  const target=$("mod-options");
  target.replaceChildren();
  if(!state.mods.length){target.append(element("p","Nenhum mod instalado no servidor."));return;}
  const selected=new Set(state.editing?.mods||[]);
  for(const mod of state.mods){
    const label=element("label",null,"mod-option");
    const checkbox=element("input");checkbox.type="checkbox";checkbox.value=mod.id;
    checkbox.checked=selected.has(mod.id);
    checkbox.disabled=$("room-preset").value!=="custom";
    const text=element("div");
    append(text,element("strong",mod.name||mod.id),element("small",mod.description||mod.id));
    append(label,checkbox,text);
    target.append(label);
  }
}
function editRoom(room=null){
  state.editing=room;
  $("editor-title").textContent=room?"Editar "+room.name:"Criar nova sala";
  $("room-id").value=room?.id||"";
  $("room-id").disabled=!!room;
  $("room-name").value=room?.name||"";
  $("room-port").value=room?.port||8080;
  $("room-port").disabled=!!room;
  $("room-preset").value=room?.preset||"traditional";
  $("room-capacity").value=room?.capacity||40;
  $("room-bots").value=room?.bots||0;
  $("room-public-access").checked=room?.publicAccess===true;
  $("editor-note").textContent=room?
    "Alterações de regras e mods exigem reiniciar esta sala. Porta e ID não podem mudar aqui.":
    "A sala será iniciada automaticamente se o controlador estiver ativo.";
  renderMods();
  $("editor").classList.remove("hidden");
  $("editor").scrollIntoView({behavior:"smooth",block:"start"});
}
async function refresh(){
  if($("dashboard").classList.contains("hidden"))return;
  try{
    const data=await api("/api/overview");
    state.rooms=data.rooms;
    $("stat-all").textContent=data.totals.rooms;
    $("stat-online").textContent=data.totals.online;
    $("stat-players").textContent=data.totals.players;
    $("stat-slots").textContent=data.totals.capacity;
    renderRooms();
  }catch(error){notify(error.message,true);}
}
async function initialize(){
  try{
    const session=await api("/api/session");
    state.csrf=session.csrf;
    state.role=session.role;
    if(session.authenticated){
      showDashboard();
      state.mods=state.role==="owner"?(await api("/api/mods")).mods||[]:[];
      await refresh();
    }else showLogin();
  }catch(error){showLogin();notify(error.message,true);}
}
$("login-form").addEventListener("submit",async event=>{
  event.preventDefault();
  const submit=event.currentTarget.querySelector("button");
  submit.disabled=true;
  try{
    const data=await api("/api/login","POST",{password:$("password").value,...($("email").value?{email:$("email").value}:{})});
    $("password").value="";
    state.csrf=data.csrf;
    state.role=data.role;
    state.mods=state.role==="owner"?(await api("/api/mods")).mods||[]:[];
    showDashboard();
    await refresh();
  }catch(error){notify(error.message,true);}
  finally{submit.disabled=false;}
});
$("logout").addEventListener("click",async()=>{
  try{await api("/api/logout","POST",{});state.csrf=null;state.role=null;showLogin();}
  catch(error){notify(error.message,true);}
});
$("refresh").addEventListener("click",()=>void refresh());
$("new-room").addEventListener("click",()=>editRoom());
$("close-editor").addEventListener("click",()=>$("editor").classList.add("hidden"));
$("room-preset").addEventListener("change",()=>renderMods());
$("room-form").addEventListener("submit",async event=>{
  event.preventDefault();
  const button=event.currentTarget.querySelector('button[type="submit"]');
  button.disabled=true;
  try{
    const preset=$("room-preset").value;
    const mods=preset==="custom"?
      [...$("mod-options").querySelectorAll('input[type="checkbox"]:checked')].map(input=>input.value):[];
    const data={
      name:$("room-name").value.trim(),preset,
      capacity:Number($("room-capacity").value),
      bots:Number($("room-bots").value),publicAccess:$("room-public-access").checked,mods
    };
    let result;
    if(state.editing)result=await api("/api/rooms/"+encodeURIComponent(state.editing.id),"PUT",data);
    else result=await api("/api/rooms","POST",{
      ...data,id:$("room-id").value,port:Number($("room-port").value)
    });
    $("editor").classList.add("hidden");
    notify(result.notice);
    await refresh();
  }catch(error){notify(error.message,true);}
  finally{button.disabled=false;}
});
void initialize();
