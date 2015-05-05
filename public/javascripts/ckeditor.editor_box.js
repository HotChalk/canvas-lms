// CKEditor-jQuery EditorBox plugin
// Called on a jQuery selector (should be a single object only)
// to initialize a CKEditor editor box in the place of the
// selected textarea: $("#edit").editorBox().  The textarea
// must have a unique id in order to function properly.
// editorBox():
// Initializes the object.  All other methods should
// only be called on an already-initialized box.
// editorBox('focus', [keepTrying])
//   Passes focus to the selected editor box.  Returns
//   true/false depending on whether the focus attempt was
//   successful.  If the editor box has not completely initialized
//   yet, then the focus will fail.  If keepTrying
//   is defined and true, the method will keep trying until
//   the focus attempt succeeds.
// editorBox('destroy')
//   Removes the CKEditor instance from the textarea.
// editorBox('toggle')
//   Toggles the CKEditor instance.  Switches back and forth between
//   the textarea and the CKEditor WYSIWYG.
// editorBox('get_code')
//   Returns the plaintext code contained in the textarea or WYSIGWYG.
// editorBox('set_code', code)
//   Sets the plaintext code content for the editor box.  Replaces ALL
//   content with the string value of code.
// editorBox('insert_code', code)
//   Inserts the string value of code at the current selection point.
// editorBox('create_link', options)
//   Creates an anchor link at the current selection point.  If anything
//   is selected, makes the selection a link, otherwise creates a link.
//   options.url is used for the href of the link, and options.title
//   will be the body of the link if no text is currently selected.

define([
  'i18nObj',
  'jquery',
  'compiled/editor/editorAccessibility', /* editorAccessibility */
  'INST', // for IE detection; need to handle links in a special way
  //'ckeditor-all', // CKEditor
  'jqueryui/draggable' /* /\.draggable/ */,
  'jquery.instructure_misc_plugins' /* /\.indicate/ */,
  'vendor/jquery.scrollTo' /* /\.scrollTo/ */,
  'vendor/jquery.ba-tinypubsub'
], function(I18nObj, $, EditorAccessibility, INST) {

  // Find the URL of the RequireJS script, which we will use to infer the correct
  // base URL for CKEDITOR
  var basePath = '';
  var tags = document.getElementsByTagName('script');
  for (var i = 0; i < tags.length; i++) {
    var index = tags[i].src.lastIndexOf('/vendor/require.js');
    if (index >= 0) {
      basePath = tags[i].src.slice(0, index);
      basePath = basePath.substr(basePath.lastIndexOf('/'));
      break;
    }
  }

  // Set CKEDITOR_BASEPATH global variable
  window.CKEDITOR_BASEPATH = basePath + '/ckeditor/';

  var enableBookmarking = !!INST.browser.ie;
  $(document).ready(function() {
    enableBookmarking = !!INST.browser.ie;
  });

  function EditorBoxList() {
    this._textareas = {};
    this._editors = {};
    this._editor_boxes = {};
  }

  $.extend(EditorBoxList.prototype, {
    _addEditorBox: function(id, box) {
      $.publish('editorBox/add', id, box);
      this._editor_boxes[id] = box;
      this._editors[id] = CKEDITOR.instances[id];
      this._textareas[id] = $("textarea#" + id);
    },
    _removeEditorBox: function(id) {
      delete this._editor_boxes[id];
      delete this._editors[id];
      delete this._textareas[id];
      $.publish('editorBox/remove', id);
      if ($.isEmptyObject(this._editors)) $.publish('editorBox/removeAll');
    },
    _getTextArea: function(id) {
      if(!this._textareas[id]) {
        this._textareas[id] = $("textarea#" + id);
      }
      return this._textareas[id];
    },
    _getEditor: function(id) {
      var textArea = this._editors[id];
      if(textArea){        
        var real_text_area = $(document).find("#"+textArea.name);
        var cke = real_text_area.siblings(".cke");
        if(real_text_area.length > 0 && cke.length == 0){
          return null;
        }
      }
      if(!this._editors[id]) {
        this._editors[id] = CKEDITOR.instances[id];
      }
      return this._editors[id];
    },
    _getEditorBox: function(id) {
      return this._editor_boxes[id];
    }
  });

  var $instructureEditorBoxList = new EditorBoxList();

  function EditorBox(id, search_url, submit_url, content_url, options) {
    options = $.extend({}, options);

    var $textarea = $("#" + id);
    $textarea.data('enable_bookmarking', enableBookmarking);
    var width = $textarea.width();
    if(width == 0) {
      width = $textarea.closest(":visible").width();
    }

    var extra_buttons = [];
    for(var idx in INST.editorButtons) {
      extra_buttons.push("instructure_external_button_" + INST.editorButtons[idx].id);
    }

    var toolbar = [
      {name: 'document', items: ['Print', 'Templates']},
      {name: 'clipboard', items: ['Cut', 'Copy', 'Paste', '-', 'Undo', 'Redo']},
      {name: 'editing', items: ['Find', 'Replace', '-', 'SelectAll', '-', 'Scayt']},
      {name: 'basicstyles', items: ['Bold', 'Italic', 'Underline', 'Strike', 'Subscript', 'Superscript', '-', 'RemoveFormat']},
      {name: 'paragraph', items: ['NumberedList', 'BulletedList', '-', 'Outdent', 'Indent', '-', 'Blockquote', '-', 'JustifyLeft', 'JustifyCenter', 'JustifyRight', 'JustifyBlock']},
      {name: 'links', items: ['instructure_links', 'Unlink']},
      {name: 'insert', items: ['Table', 'HorizontalRule', 'Smiley', 'SpecialChar', 'EqnEditor', 'instructure_image']},
      {name: 'styles', items: ['Styles', 'Format', 'Font', 'FontSize']},
      {name: 'colors', items: ['TextColor', 'BGColor']},
      {name: 'tools', items: ['Maximize', 'ShowBlocks']},
      {name: 'others', items: extra_buttons}
    ];

    var ckOptions = $.extend({
      allowedContent: true,
      startupFocus: options.focus,
      toolbar: toolbar,
      pasteFromWordRemoveFontStyles: false,
      pasteFromWordRemoveStyles: false,
      extraPlugins: 'instructure_external_tools,instructure_links,instructure_image',
      removePlugins: 'image,liststyle,tabletools,contextmenu',
      removeButtons: '',
      contentsCss: [
          '/stylesheets/static/baseline.reset.css',
          '/stylesheets/static/baseline.base.css',
          '/stylesheets/static/baseline.table.css',
          '/stylesheets/static/baseline.type.css',
          '/stylesheets/static/baseline.dialog.css',
          CKEDITOR.getUrl('contents.css')],
      on: {
        focus: function(evt) {
          var $editor = $(evt.editor.element);
          $(document).triggerHandler('editor_box_focus', $editor);
          $.publish('editorBox/focus', $editor);
        }
      }
    }, options.tinyOptions || {});

    CKEDITOR.replace($textarea[0], ckOptions);

    this._textarea =  $textarea;
    this._editor = null;
    this._id = id;
    this._searchURL = search_url;
    this._submitURL = submit_url;
    this._contentURL = content_url;
    $instructureEditorBoxList._addEditorBox(id, this);
  }

// --------------------------------------------------------------------

  var editorBoxIdCounter = 1;

  $.fn.editorBox = function(options, more_options) {
    var args = arguments;
    if(this.length > 1) {
      return this.each(function() {
        var $this = $(this);
        $this.editorBox.apply($this, args);
      });
    }

    var id = this.attr('id');
    if(typeof(options) == "string" && options != "create") {
      if(options == "get_code") {
        return this._getContentCode(more_options);
      } else if(options == "set_code") {
        this._setContentCode(more_options);
      } else if(options == "insert_code") {
        this._insertHTML(more_options);
      } else if(options == "create_link") {
        this._linkSelection(more_options);
      } else if(options == "focus") {
        return this._editorFocus(more_options);
      } else if(options == "toggle") {
        this._toggleView();
      } else if(options == "execute") {
        var arr = [];
        for(var idx = 1; idx < arguments.length; idx++) {
          arr.push(arguments[idx]);
        }
        return $.fn._execCommand.apply(this, arr);
      } else if(options == "destroy") {
        this._removeEditor(more_options);
      } else if(options == "is_dirty") {
        return $instructureEditorBoxList._getEditor(id).checkDirty();
      } else if(options == 'exists?') {
        return !!$instructureEditorBoxList._getEditor(id);
      }
      return this;
    }
    this.data('rich_text', true);
    if(!id) {
      id = 'editor_box_unique_id_' + editorBoxIdCounter++;
      this.attr('id', id);
    }
    if($instructureEditorBoxList._getEditor(id)) {
      this._setContentCode(this.val());
      return this;
    }
    var search_url = "";
    if(options && options.search_url) {
      search_url = options.search_url;
    }
    var box = new EditorBox(id, search_url, "", "", options);
    return this;
  };

  $.fn._execCommand = function() {
    var id = $(this).attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if(editor && editor.execCommand) {
      editor.execCommand.apply(editor, arguments);
    }
    return this;
  };

  $.fn._justGetCode = function() {
    var id = this.attr('id') || '';
    var content = '';
    try {
      content = $instructureEditorBoxList._getEditor(id).getData();
    } catch(e) {}
    return content;
  };

  $.fn._getContentCode = function(update) {
    if(update == true) {
      var content = this._justGetCode(); //""
      this._setContentCode(content);
    }
    return this._justGetCode();
  };

  $.fn._getSearchURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._searchURL;
  };

  $.fn._getSubmitURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._submitURL;
  };

  $.fn._getContentURL = function() {
    return $instructureEditorBoxList._getEditorBox(this.attr('id'))._contentURL;
  };

  $.fn._toggleView = function() {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if (editor) {
      editor.setMode(editor.mode === 'source' ? 'wysiwyg' : 'source');
    }
  };

  $.fn._removeEditor = function() {
    var id = this.attr('id');
    this.data('rich_text', false);
    var editor = $instructureEditorBoxList._getEditor(id);
    if (editor) {
      editor.destroy();
      $instructureEditorBoxList._removeEditorBox(id);
    }
  };

  $.fn._setContentCode = function(val) {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if (editor) {
      editor.setData(val, {
        callback: function() {
          $instructureEditorBoxList._getEditor(id).updateElement();
        }
      });
    }
  };

  $.fn._insertHTML = function(html) {
    var id = this.attr('id');
    var editor = $instructureEditorBoxList._getEditor(id);
    if (editor) {
      editor.insertHtml(html, 'unfiltered_html');
    }
  };

  $.fn._editorFocus = function() {
    var $element = this,
        id = $element.attr('id'),
        editor = $instructureEditorBoxList._getEditor(id);
    if(!editor ) {
      return false;
    }
    editor.focus();
    $.publish('editorBox/focus', $element);
    return true;
  };

  $.fn._linkSelection = function(options) {
    if(typeof(options) == "string") {
      options = {url: options};
    }
    var title = options.title;
    var url = options.url || "";
    if(url.match(/@/) && !url.match(/\//) && !url.match(/^mailto:/)) {
      url = "mailto:" + url;
    } else if(!url.match(/^\w+:\/\//) && !url.match(/^mailto:/) && !url.match(/^\//)) {
      url = "http://" + url;
    }
    var classes = options.classes || "";
    var defaultText = options.text || options.title || "Link";
    var target = options.target || null;
    var id = $(this).attr('id');
    if(url.indexOf("@") != -1) {
      options.file = false;
      options.image = false;
      if(url.indexOf("mailto:") != 0) {
        url = "mailto:" + url;
      }
    } else if (url.indexOf("/") == -1) {
      title = url;
      url = url.replace(/\s/g, "");
      url = location.href + url;
    }
    if(options.file) {
      classes += "instructure_file_link ";
    }
    if(options.scribdable) {
      classes += "instructure_scribd_file ";
    }
    var link_id = '';
    if(options.kaltura_entry_id && options.kaltura_media_type) {
      link_id = "media_comment_" + options.kaltura_entry_id;
      if(options.kaltura_media_type == 'video') {
        classes += "instructure_video_link ";
      } else {
        classes += "instructure_audio_link ";
      }
    }
    if(options.image) {
      classes += "instructure_image_thumbnail ";
    }
    classes = $.unique(classes.split(/\s+/)).join(" ");
    var selectionText = "";
    var editor = $instructureEditorBoxList._getEditor(id);
    if(enableBookmarking && this.data('last_bookmark')) {
      editor.getSelection().selectBookmarks(this.data('last_bookmark'));
    }
    var selection = editor.getSelection();
    var anchor = selection.getSelectedElement();
    while(anchor && anchor.getName() != 'A' && anchor.getName() != 'BODY' && anchor.getParent()) {
      anchor = anchor.getParent();
    }
    if(anchor && anchor.getName() != 'A') { anchor = null; }

    var selectedContent = selection.getSelectedText();
    if(!selectedContent || selectedContent == "") {
      if(anchor) {
        $(anchor).attr({
          href: url,
          title: title || '',
          id: link_id,
          'class': classes,
          target: target
        });
      } else {
        selectionText = defaultText;
        var $div = $("<div/>");
        $div.append($("<a/>", {id: link_id, target: target, title: title, href: url, 'class': classes}).text(selectionText));
        editor.insertHtml($div.html(), 'unfiltered_html');
      }
    } else {
      var $div = $("<div/>");
      $div.append($("<a/>", {target: (target || ''), title: (title || ''), href: url, 'class': classes, 'id': link_id}).text(selectedContent));
      editor.insertHtml($div.html(), 'unfiltered_html');
    }
  };

});
