/**
 * This class handles the pairing of status updates with the responses waiting
 * for them. When responses come in, they are handed to this class who holds onto
 * them until there is a status update to send it back with.
 */

 // TODO: Handle time-outs so that stuff doesn't get stuck in the buffer 
 // forever.

//import 'dart:io';
//import 'dart:json' as JSON;

part of dartfiddle;

class Status {
  // The message to be sent to the client.
  String message;

  // The step number of this status. We need to send this to the client to make
  // sure that it doesn't display out-of-order statuses.
  int step;

  // True if this step is the last step.
  bool last;

  Status(this.message, this.step, this.last);
}

class StatusResponseManager {
  var _responses = new Map<String, List>();
  var _statuses = new Map<String, Status>();

  void addResponse(HttpResponse response, String token) {
    // First check if we have a status waiting.
    if (_statuses.containsKey(token)) {
      _sendResponse(response, _statuses[token]);
      _statuses.remove(token);
      return;
    }

    // No status waiting, so buffer this response.
    if (!_responses.containsKey(token)) {
      _responses[token] = new List<HttpResponse>();
    }
    _responses[token].add(response);
  }

  void addStatus(Status status, String token) {
    // First check if we can send the response immediately.
    if (_responses.containsKey(token)) {
      var response = _responses[token].removeAt(0);
      // If we just removed the last response, we can clean up the buffer.
      if (_responses[token].isEmpty) {
        _responses.remove(token);
      }
      _sendResponse(response, status);
    }

    // There are no responses waiting, so buffer this status. We may be
    // overwriting a previous status, but that's fine because we wouldn't want
    // to send a stale status anyway.
    _statuses[token] = status;
  }

  void _sendResponse(HttpResponse response, Status status) {
    var data = {
      'status': status.message,
      'step': status.step,
      'last': status.last
    };
    response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
    response.outputStream.writeString(JSON.stringify(data));
    response.outputStream.close();
  }
}
