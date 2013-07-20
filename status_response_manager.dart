/**
 * This class handles the pairing of status updates with the responses waiting
 * for them. When responses come in, they are handed to this class who holds
 * onto them until there is a status update to send it back with.
 */

 // TODO: Requests can't be held for more than 30 seconds. Make a timer running
 // every 10 seconds, getting rid of requests 20 or more seconds old.

part of dartfiddle;

class Status {
  // The message to be sent to the client.
  String message;

  // The step number of this status. We need to send this to the client to make
  // sure that it doesn't display out-of-order statuses.
  int step;

  // True if everything is ready for Dartium to run the application (but dart2js
  // might not have been run yet).
  bool dartiumDone;

  // True if this step is the last step.
  bool last;

  Status({this.message, this.step, this.dartiumDone: false, this.last: false});
}

class StatusResponseManager {
  var _responses = new Map<String, List>();
  var _statuses = new Map<String, Status>();

  // This function should be called when a request is made and it should hang
  // until there is a status to send it back with.
  void addResponse(HttpResponse response, String token) {
    // First check if we have a status waiting.
    if (_statuses.containsKey(token)) {
      _sendResponse(response, _statuses[token], token);
      _statuses.remove(token);
      return;
    }

    // No status waiting, so buffer this response.
    if (!_responses.containsKey(token)) {
      _responses[token] = new List<HttpResponse>();
    }
    _responses[token].add(response);
  }

  // This function should be called whenever there is a status update.
  void addStatus(Status status, String token) {
    // First check if we can send the response immediately.
    if (_responses.containsKey(token)) {
      var response = _responses[token].removeAt(0);
      // If we just removed the last response, we can clean up the buffer.
      if (_responses[token].isEmpty) {
        _responses.remove(token);
      }
      _sendResponse(response, status, token);
      return;
    }

    // There are no responses waiting, so buffer this status. We may be
    // overwriting a previous status, but that's fine because we wouldn't want
    // to send a stale status anyway.
    _statuses[token] = status;
  }

  void _sendResponse(HttpResponse response, Status status, String token) {
    var data = {
      'status': status.message,
      'step': status.step,
      'last': status.last,
      'token': token,
      'dartium_done': status.dartiumDone
    };
    response.headers.set(HttpHeaders.CONTENT_TYPE, 'application/json');
    response.write(JSON.stringify(data));
    response.close();
  }
}
