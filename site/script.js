// NovaOS site: fake emergency-shell terminal + docs tabs
(function(){
  var out=document.getElementById('tout'),inp=document.getElementById('tin');
  function print(s){if(!out)return;out.textContent+=s+"\n";out.scrollTop=out.scrollHeight;}
  var files={"README.TXT":"NovaOS v0.1 -- hello from the web shell.","KERNEL.BIN":"<binary, 76KB>"};
  var mem={free:121634816,total:134217728};
  if(out){print("NovaOS Emergency Shell v0.1 (web simulation)");print("Type 'help'.");}
  function cmd(line){
    var p=line.trim().split(/\s+/),c=(p[0]||"").toLowerCase();
    if(!c)return"";
    if(c==="help")return"Commands: help clear info mem peek poke ls cat <file> fbinfo gui-restart reboot shutdown halt";
    if(c==="clear"){out.textContent="";return"";}
    if(c==="info")return"NovaOS v0.1 - x86_64 hobby OS - dual BIOS+UEFI - ASM only";
    if(c==="mem")return"Free RAM (bytes): "+mem.free+"\nTotal tracked (bytes): "+mem.total;
    if(c==="ls")return"Files (read-only FAT):\nKERNEL  BIN  76KB\nREADME  TXT   1KB";
    if(c==="fbinfo")return"Framebuffer @ 0xFD000000\nMode: 1280x1024x24 (VBE) / GOP (UEFI)";
    if(c==="gui-restart")return"Already in a GUI (this browser). Nice try.";
    if(c==="reboot")return"Rebooting... just kidding. This tab stays.";
    if(c==="shutdown"||c==="halt")return"System halted - you can close this tab any time.";
    if(c==="peek")return"peek: 0x"+(p[1]||"100000")+" = DE AD BE EF ... (simulated)";
    if(c==="poke")return"OK (simulated)";
    if(c==="cat"){var f=(p[1]||"").toUpperCase();return files[f]||("cat: "+p[1]+" not found");}
    return"Unknown command. Type 'help'.";
  }
  if(inp){inp.addEventListener('keydown',function(e){
    if(e.key==='Enter'){var v=inp.value;print("nova> "+v);var r=cmd(v);if(r)print(r);inp.value="";}
  });}
  var tabs=document.querySelectorAll('.tab');
  tabs.forEach(function(t){t.addEventListener('click',function(){
    tabs.forEach(function(x){x.classList.remove('active');});
    t.classList.add('active');
    document.querySelectorAll('.tabbody').forEach(function(b){b.classList.add('hidden');});
    document.getElementById('t-'+t.dataset.t).classList.remove('hidden');
  });});
})();
