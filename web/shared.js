const c = document.getElementById('clock');
if (c) {
  const tick = () => {
    const d = new Date();
    c.textContent = d.toLocaleDateString(undefined, { weekday:'long', month:'long', day:'numeric' })
      + ' — ' + d.toLocaleTimeString(undefined, { hour:'numeric', minute:'2-digit' });
  };
  tick();
  setInterval(tick, 30000);
}
