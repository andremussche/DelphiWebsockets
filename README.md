# DelphiWebsockets
Websockets and Socket.io for Delphi

See below for an event driven async example of an socket.io server and client:
```delphi
uses
  IdWebsocketServer, IdHTTPWebsocketClient, superobject, IdSocketIOHandling;

var
  server: TIdWebsocketServer;
  client: TIdHTTPWebsocketClient;

const
  C_CLIENT_EVENT = 'CLIENT_TO_SERVER_EVENT_TEST';
  C_SERVER_EVENT = 'SERVER_TO_CLIENT_EVENT_TEST';

procedure ShowMessageInMainthread(const aMsg: string) ;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      ShowMessage(aMsg);
    end);
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  server := TIdWebsocketServer.Create(Self);
  server.DefaultPort := 12345;
  server.SocketIO.OnEvent(C_CLIENT_EVENT,
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallback: ISocketIOCallback)
    begin
      //show request (threadsafe)
      ShowMessageInMainthread('REQUEST: ' + aArgument[0].AsJSon);
      //send callback (only if specified!)
      if aCallback <> nil then
        aCallback.SendResponse( SO(['succes', True]).AsJSon );
    end);
  server.Active      := True;

  client := TIdHTTPWebsocketClient.Create(Self);
  client.Port := 12345;
  client.Host := 'localhost';
  client.SocketIOCompatible := True;
  client.SocketIO.OnEvent(C_SERVER_EVENT,
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallback: ISocketIOCallback)
    begin
      ShowMessageInMainthread('Data PUSHED from server: ' + aArgument[0].AsJSon);
      //server wants a response?
      if aCallback <> nil then
        aCallback.SendResponse('thank for the push!');
    end);
  client.Connect;
  client.SocketIO.Emit(C_CLIENT_EVENT, SO([ 'request', 'some data']),
    //provide callback
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
      //show response (threadsafe)
      ShowMessageInMainthread('RESPONSE: ' + aJSON.AsJSon);
    end);

  //start timer so server pushes (!) data to all clients
  Timer1.Interval := 5 * 1000; //5s
  Timer1.Enabled  := True;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := false;
  server.SocketIO.EmitEventToAll(C_SERVER_EVENT, SO(['data', 'pushed from server']),
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
        //show response (threadsafe)
        TThread.Synchronize(nil,
          procedure
          begin
            ShowMessage('RESPONSE from a client: ' + aJSON.AsJSon);
          end);
    end);
end;
```
