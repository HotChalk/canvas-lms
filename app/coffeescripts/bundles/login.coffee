document.getElementById('submit_button').disabled = true

window.onload = ->
  document.getElementById('submit_button').disabled = false
  return

require ['login']
