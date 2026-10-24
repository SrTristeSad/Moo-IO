// SPDX-License-Identifier: AGPL-3.0-only
// Browser controls for the loopback-only server panel. No third-party scripts.
const $=id=>document.getElementById(id);
const state={csrf:null,rooms:[],mods:[],editing:null};
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
    append(buttons,configure,restart);
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
  $("editor-note").textContent=room?
    "Alterações de regras e mods exigem reiniciar esta sala. Porta e ID não podem mudar aqui.":
    "Salas novas entram em funcionamento após reiniciar o controlador.";
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
    if(session.authenticated){
      showDashboard();
      state.mods=(await api("/api/mods")).mods||[];
      await refresh();
    }else showLogin();
  }catch(error){showLogin();notify(error.message,true);}
}
$("login-form").addEventListener("submit",async event=>{
  event.preventDefault();
  const submit=event.currentTarget.querySelector("button");
  submit.disabled=true;
  try{
    const data=await api("/api/login","POST",{password:$("password").value});
    $("password").value="";
    state.csrf=data.csrf;
    state.mods=(await api("/api/mods")).mods||[];
    showDashboard();
    await refresh();
  }catch(error){notify(error.message,true);}
  finally{submit.disabled=false;}
});
$("logout").addEventListener("click",async()=>{
  try{await api("/api/logout","POST",{});state.csrf=null;showLogin();}
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
      bots:Number($("room-bots").value),mods
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
