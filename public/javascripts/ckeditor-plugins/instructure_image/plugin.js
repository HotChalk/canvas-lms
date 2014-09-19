(function() {
  var htmlEscape = require('str/htmlEscape');
  CKEDITOR.plugins.add('instructure_image', {
    icons: 'instructure_image',
    hidpi: true,
    init: function(editor) {
      editor.addCommand('instructureImage', {
        exec: function(api) {
          var selectedNode = null;
          if (api.getSelection() && api.getSelection().getSelectedElement()) {
            selectedNode = $(api.getSelection().getSelectedElement().$);
          }
          require(['compiled/views/ckeditor/InsertUpdateImageView'], function(InsertUpdateImageView){
            new InsertUpdateImageView(api, selectedNode);
          });
        }
      });
      editor.ui.addButton('instructure_image', {
        label: 'Embed Image',
        command: 'instructureImage',
        toolbar: 'insert'
      });
      editor.on('doubleclick', function(evt) {
        var element = evt.data.element;
        if (element.is('img') && !element.data('cke-realelement') && !element.isReadOnly()) {
          editor.execCommand('instructureImage');
        }
      });
    }
  });
})();

