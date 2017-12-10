program WebSocketEchoServer;

uses
  Vcl.Forms,
  WebSocket.Form.EchoServer in 'WebSocket.Form.EchoServer.pas' {frmWebSocketEchoServer},
  IdWebsocketServer in '..\IdWebsocketServer.pas',
  IdIOHandlerWebsocket in '..\IdIOHandlerWebsocket.pas',
  IdIIOHandlerWebsocket in '..\IdIIOHandlerWebsocket.pas',
  IdServerIOHandlerWebsocket in '..\IdServerIOHandlerWebsocket.pas',
  IdServerWebsocketContext in '..\IdServerWebsocketContext.pas',
  IdServerBaseHandling in '..\IdServerBaseHandling.pas',
  IdServerSocketIOHandling in '..\IdServerSocketIOHandling.pas',
  IdSocketIOHandling in '..\IdSocketIOHandling.pas',
  IdHTTPWebsocketClient in '..\IdHTTPWebsocketClient.pas',
  IdWebSocketConsts in '..\IdWebSocketConsts.pas',
  IdServerWebsocketHandling in '..\IdServerWebsocketHandling.pas',
  IdWebSocketTypes in '..\IdWebSocketTypes.pas',
  IdWebsocketServerSSL in '..\IdWebsocketServerSSL.pas',
  IdServerIOHandlerWebsocketSSL in '..\IdServerIOHandlerWebsocketSSL.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmWebSocketEchoServer, frmWebSocketEchoServer);
  Application.Run;
end.
