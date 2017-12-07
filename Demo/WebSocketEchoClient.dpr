program WebSocketEchoClient;

uses
  Vcl.Forms,
  WebSocket.Form.EchoClient in 'WebSocket.Form.EchoClient.pas' {Form3},
  IdHTTPWebsocketClient in '..\IdHTTPWebsocketClient.pas',
  IdIIOHandlerWebsocket in '..\IdIIOHandlerWebsocket.pas',
  IdIOHandlerWebsocket in '..\IdIOHandlerWebsocket.pas',
  IdWebSocketTypes in '..\IdWebSocketTypes.pas',
  IdSocketIOHandling in '..\IdSocketIOHandling.pas',
  IdServerBaseHandling in '..\IdServerBaseHandling.pas',
  IdServerWebsocketContext in '..\IdServerWebsocketContext.pas',
  IdServerSocketIOHandling in '..\IdServerSocketIOHandling.pas',
  IdWebSocketConsts in '..\IdWebSocketConsts.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm3, Form3);
  Application.Run;
end.
