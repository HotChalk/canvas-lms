require [
  'react',
  'react-dom',
  'jsx/navigation_header/Navigation',
  'navigation_header_common'
], (React, ReactDOM, Navigation) ->

  Nav = React.createElement(Navigation)
  ReactDOM.render(Nav, document.getElementById('global_nav_tray_container'))

