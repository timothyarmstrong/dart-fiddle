import 'dart:async';
import 'dart:io';
import 'dart:json' as JSON;

String addslashes(String s) {
  return s.replaceAll(r'\', r'\\').replaceAll(r'"', r'\"').replaceAll(r"'", r"\'").replaceAll(r"/", r"\\/");
}

// PATH HANDLERS

// Handle API calls.
void handleApiCall(request, response) {
  response.outputStream.writeString("API Call");
  response.outputStream.close();
}

// Handle requests for the application.
void handleAppRequest(request, response) {
  // Get the ID.
  var id = '';

  var dartFilename, htmlFilename, pubspecFilename, iframeSource;
  if (id.isEmpty) {
    dartFilename = './templates/default_dart.txt';
    htmlFilename = './templates/default_html.txt';
    pubspecFilename = './templates/default_pubspec.txt';
    iframeSource = '/static/special/default.html';
  } else {
    dartFilename = './static/files/$id/main.dart';
    htmlFilename = './static/files/$id/index.html';
    pubspecFilename = './static/files/$id/pubspec.yaml'; 
    iframeSource = '/static/files/$id/';
  }

  // Fetch the files the we need.
  Future.wait([
    new File('./templates/app.html').readAsString(),
    new File(dartFilename).readAsString(),
    new File(htmlFilename).readAsString(),
    new File(pubspecFilename).readAsString()
  ]).then((files) {
    var appFile = files[0];
    var dartFile = files[1];
    var htmlFile = files[2];
    var pubspecFile = files[3];

    // TODO: Dynamic based on actual files, which is hard because they will be stored on another fileserver.
    // Probably will need a database holding what they are.
    var initialData = {
      'id': id,
      'dart': [
        {
          'filename': 'main.dart',
          'content': dartFile,
          'type': 'Dart'
        }
      ],
      'html': [
        {
          'filename': 'index.html',
          'content': htmlFile,
          'type': 'HTML'
        },
        {
          'filename': 'pubspec.yaml',
          'content': pubspecFile,
          'type': 'YAML'
        }
      ]
    };

    var serialized = addslashes(JSON.stringify(initialData));
    appFile = appFile.replaceAll(r'{{ initialData }}', serialized);
    appFile = appFile.replaceAll(r'{{ iframeSource }}', iframeSource);

    response.outputStream.writeString(appFile);
    response.outputStream.close();
  });
}

// Handle static file requests.
void handleStaticFileRequest(request, response) {
  var filetypeMap = {
    'css': 'text/css',
    'js': 'application/javascript',
    'dart': 'application/dart',
    'json': 'application/json'
  };

  // Filter the path.
  var path = new Path('./${request.path}').canonicalize();
  if (path.segments()[0] != 'static') { // TODO: potential NPE.
    print('no longer in static');
    send404(response);
  }
  // Send the file, if it exists.
  var file = new File.fromPath(path);
  file.exists().then((bool exists) {
    if (exists) {
      if (filetypeMap.containsKey(path.extension)) {
        response.headers.set(HttpHeaders.CONTENT_TYPE, filetypeMap[path.extension]);
      }
      file.openInputStream().pipe(response.outputStream);
    } else {
      print('file does not exist');
      send404(response);
    }
  });
}

// Error handling.
void send404(response) {
  // TODO: 404 code.
  response.statusCode = HttpStatus.NOT_FOUND;
  response.outputStream.writeString("404'd");
  response.outputStream.close();
}

main() {
  var server = new HttpServer();
  var port = int.parse(Platform.environment['PORT']);
  server.listen('0.0.0.0', port);
  print('Server started on port: ${port}');

  // Setup static request handler.
  server.addRequestHandler((request) {
    if (request.path.startsWith('/static/') && request.method == 'GET') {
      return true;
    }
    return false;
  }, handleStaticFileRequest);

  // Setup API request handler.
  server.addRequestHandler((request) {
    if (request.path == '/api/save' && request.method == 'POST') {
      return true;
    }
    return false;
  }, handleApiCall);

  // Setup requests for the application, either the root or including an ID.
  server.addRequestHandler((request) {
    var segments = new Path(request.path).segments();
    if (segments.length == 0 || (segments.length == 1 && new RegExp(r'^[a-z]{7}$').hasMatch(segments[0]))) {
      return true;
    }
    return false;
  }, handleAppRequest);

  // Handle all other requests.
  server.defaultRequestHandler = (HttpRequest request, HttpResponse response) {
    if (request.path == '/favicon.ico') {
      // TODO: Handle favicon request.
      print('This is a favicon request.');
    }

    send404(response);

    /* response.headers.set(HttpHeaders.CONTENT_TYPE, 'text/html');
    response.outputStream.writeString('Default request handler');
    response.outputStream.close(); */
  };
}
