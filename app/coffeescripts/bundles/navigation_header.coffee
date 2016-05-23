require [
  'react',
  'jsx/navigation_header/Navigation',
], (React, Navigation) ->

  window.onload = ->
    $('.support_url').attr 'target', '_blank'
    return

  Nav = React.createElement(Navigation)
  React.render(Nav, document.getElementById('global_nav_tray_container'))

