const C="co-v11";
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(
  caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>clients.claim())));
self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET"||u.origin!==location.origin)return;
  e.respondWith(fetch(r).then(res=>{const c=res.clone();caches.open(C).then(x=>x.put(r,c));return res}).catch(()=>caches.match(r)));
});
self.addEventListener("push",e=>{
  let d={};try{d=e.data.json()}catch(_){d={body:e.data?e.data.text():""}}
  e.waitUntil(self.registration.showNotification(d.title||"بيوت",{body:d.body||"",icon:"icon-192.png",badge:"icon-192.png",data:{url:d.url||"pm.html"},dir:"rtl",lang:"ar"}));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();
  const u=new URL(e.notification.data?.url||"pm.html",self.registration.scope).href;
  e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{
    for(const c of l){if(c.url.startsWith(self.registration.scope)&&"focus" in c)return c.focus()}
    return clients.openWindow(u)}));
});
