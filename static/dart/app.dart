import 'dart:html';
import 'dart:json' as JSON;
import 'dart:uri' as uri;

import 'package:js/js.dart' as js;

String getId() {
  var path = window.location.pathname;
  if (path == '/' || path.isEmpty) {
    return '';
  } else {
    return path.split('/')[1];
  }
}

void setId(String id) {
  window.history.pushState(null, '', '/$id');
}

void apiResponse(HttpRequest request) {
  query('#run').disabled = false;

  var data = JSON.parse(request.responseText);
  if (data.containsKey('error')) {
    window.alert(data['error']);
    return;
  }

  var id = data['id'];
  var iframe = query('#result-panel iframe');
  iframe.src = '/files/$id/';

  setId(id);
}

class _Document {
  Element editorElement;
  Element tabElement;
  var aceProxy; // TODO: What type is this?
  String filename;
  String filetype;

  _Document(this.editorElement, this.tabElement, this.aceProxy, this.filename, this.filetype);

  void makeActive() {
    editorElement.classes.add('active');
    tabElement.classes.add('active');
  }

  void makeInactive() {
    editorElement.classes.remove('active');
    tabElement.classes.remove('active');
  }

  /*Map<String, String> get contents() {
    var editorContents;
    js.scoped(() {
      //
    });
  }*/

}

class Editor {
  bool canCreateDocuments = true;
  bool canRenameDocuments = true;
  String requiredSuffix;

  Element _root;

  Element _tabBar;
  Element _editorContainer;
  Element _statusBar;
  Element _newButton;

  _Document _activeDocument;

  // Map of filenames to their documents.
  Map<String, _Document> _documents = new Map();

  // Map of filetypes to the ACE modes
  Map<String, String> _filetypeToMode = {
    'Javascript': 'ace/mode/javascript',
    'HTML': 'ace/mode/html',
    'YAML': 'ace/mode/yaml',
    'Dart': 'ace/mode/dart'
  };

  Editor(this._root) {
    // Create initial editor structure.
    
    // Tab bar.
    _tabBar = new DivElement();
    _tabBar.classes.add('tab-bar');
    _root.append(_tabBar);

    // Container for the ACE editors.
    _editorContainer = new DivElement();
    _editorContainer.classes.add('editors');
    _root.append(_editorContainer);

    // Status bar.
    _statusBar = new DivElement();
    _statusBar.classes.add('status');
    _root.append(_statusBar);

    // TODO: Pass this setting in.
    if (canCreateDocuments) {
      _newButton = new DivElement();
      _newButton.classes.add('new');
      _newButton.text = "NEW";
      _tabBar.append(_newButton);
    }

  }

  void createDocument(String filename, String content, String filetype) {
    // Tab.
    var tab = new DivElement();
    tab.classes.add('tab');
    tab.text = filename;
    tab.dataAttributes['filename'] = filename;
    _tabBar.append(tab);

    tab.onClick.listen((e) {
      var filename = e.currentTarget.dataAttributes['filename'];
      _activeDocument.makeInactive();
      _activeDocument = _documents[filename];
      _activeDocument.makeActive();
      _statusBar.text = _activeDocument.filetype;
    });

    // ACE editor.
    var aceElement = new DivElement();
    aceElement.classes.add('editor');
    _editorContainer.append(aceElement);

    // Setup ACE.
    var aceProxy;
    js.scoped(() {
      aceProxy = js.context.ace.edit(aceElement);
      //aceProxy.dartEditor.setTheme('ace/theme/espresso');
      aceProxy.getSession().setMode(_filetypeToMode[filetype]);
      aceProxy.setShowPrintMargin(false);
      aceProxy.getSession().setTabSize(2);
      aceProxy.setHighlightActiveLine(false);
      aceProxy.setValue(content);
      aceProxy.clearSelection();

      js.retain(aceProxy);
    });

    js.scoped(() {
      //window.alert(aceProxy.getValue());
    });

    // Bundle everything up into a _Document.
    var document = new _Document(aceElement, tab, aceProxy, filename, filetype);

    if (_documents.isEmpty) {
      _activeDocument = document;
      _activeDocument.makeActive();
      _statusBar.text = _activeDocument.filetype;
    }

    // Remember this document.
    _documents[filename] = document;

  }

  List<Map<String, String>> getDocumentsContents() {
    var retval = new List();
    _documents.forEach((filename, document) {
      var data = new Map();
      data['filename'] = filename;
      js.scoped(() {
        data['content'] = document.aceProxy.getValue();
      });
      retval.add(data);
    });
    return retval;
  }

}

main() {
  js.scoped(() {
    // TODO: Move the cursor to the right place in the templates.
  });
  
  // Grab the initial data from the JavaScript.
  var initialData;
  js.scoped(() {
    initialData = JSON.parse(js.context.initialData);
  });

  // Create the editors.
  var dartEditor = new Editor(query('#dart-code'));
  for (var file in initialData['dart']) {
    dartEditor.createDocument(file['filename'], file['content'], file['type']);
  }
  var htmlEditor = new Editor(query('#html-code'));
  for (var file in initialData['html']) {
    htmlEditor.createDocument(file['filename'], file['content'], file['type']);
  }

  // Prepare the 'run' button.
  var runButton = query('#run');
  runButton.on.click.add((e) { // TODO: use onClick.listen.
    // The data to send.
    var data = {
      'id': getId(),
      'dart': dartEditor.getDocumentsContents(),
      'html': htmlEditor.getDocumentsContents()
    };

    // Setup and send the API request.
    var request = new HttpRequest();
    request.open('POST', '/api/save');
    
    request.on.loadEnd.add((e) => apiResponse(request));

    var formData = new FormData();
    formData.append('data', JSON.stringify(data));

    request.send(formData);

    runButton.disabled = true;
  });
}
