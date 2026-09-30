const trigger = document.querySelector('[data-film-trigger]');

trigger.addEventListener('click', (event) => {
  // Modified clicks keep the link's ordinary open-in-a-new-tab behavior.
  if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  const player = document.createElement('iframe');
  player.src = 'https://www.youtube-nocookie.com/embed/6BVgClx1r_A?autoplay=1&playsinline=1';
  player.title = 'Diskmap — See what fills your Mac';
  player.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
  player.allowFullscreen = true;
  player.referrerPolicy = 'strict-origin-when-cross-origin';
  document.querySelector('[data-film-player]').replaceChildren(player);
  player.focus();
});
