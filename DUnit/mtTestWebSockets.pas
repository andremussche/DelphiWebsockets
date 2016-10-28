unit mtTestWebSockets;

interface

uses
  TestFramework,
  IdHTTPWebsocketClient, IdServerWebsocketContext, IdWebsocketServer,
  IdContext, IdCustomHTTPServer;

type
  TTextCallback = reference to procedure(aText: string);

  TTestWebSockets = class(TTestCase)
  private
    class var IndyHTTPWebsocketServer1: TIdWebsocketServer;
    class var IndyHTTPWebsocketClient1: TIdHTTPWebsocketClient;
  protected
    FLastWSMsg: string;
    FLastSocketIOMsg: string;
    procedure HandleHTTPServerCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure WebsocketTextMessage(const aData: string);
    procedure HandleWebsocketTextMessage(const AContext: TIdServerWSContext; const aText: string);
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreateObjects;

    procedure StartServer;

    procedure TestPlainHttp;
    procedure TestWebsocketMsg;

    procedure TestSocketIOMsg;
    procedure TestSocketIOCallback;
    procedure TestSocketIOError;

    procedure DestroyObjects;
  end;

  TBooleanFunction = reference to function: Boolean;
  function MaxWait(aProc: TBooleanFunction; aMaxWait_msec: Integer): Boolean;

implementation

uses
  Windows, Forms, DateUtils, SysUtils, Classes,
  IdSocketIOHandling, superobject, IdIOHandlerWebsocket;

function MaxWait(aProc: TBooleanFunction; aMaxWait_msec: Integer): Boolean;
var
  tStart: TDateTime;
begin
  tStart := Now;

  Result := aProc;
  while not Result and
        (MilliSecondsBetween(Now, tStart) <= aMaxWait_msec) do
  begin
    Sleep(10);
    if GetCurrentThreadId = MainThreadID then
      CheckSynchronize(10);
    Result := aProc;
  end;
end;

{ TTestWebSockets }

procedure TTestWebSockets.SetUp;
begin
  inherited;
end;

procedure TTestWebSockets.TearDown;
begin
  inherited;
end;

procedure TTestWebSockets.CreateObjects;
begin
  IndyHTTPWebsocketServer1 := TIdWebsocketServer.Create(nil);
  IndyHTTPWebsocketServer1.DefaultPort  := 8099;
  IndyHTTPWebsocketServer1.KeepAlive    := True;
  //IndyHTTPWebsocketServer1.DisableNagle := True;
  //SendClientAccessPolicyXml = captAllowAll
  //SendCrossOriginHeader = True

  IndyHTTPWebsocketClient1 := TIdHTTPWebsocketClient.Create(nil);
  IndyHTTPWebsocketClient1.Host  := 'localhost';
  IndyHTTPWebsocketClient1.Port  := 8099;
  IndyHTTPWebsocketClient1.SocketIOCompatible := True;
end;

procedure TTestWebSockets.DestroyObjects;
begin
  IndyHTTPWebsocketClient1.Free;
  IndyHTTPWebsocketServer1.Free;
end;

procedure TTestWebSockets.HandleHTTPServerCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var sfile: string;
begin
  if ARequestInfo.Document = '/index.html' then
    AResponseInfo.ContentText := 'dummy index.html'
  else
  begin
    sfile := ExtractFilePath(Application.ExeName) + ARequestInfo.Document;
    if FileExists(sfile) then
      AResponseInfo.ContentStream := TFileStream.Create(sfile, fmOpenRead);
  end;
end;

procedure TTestWebSockets.StartServer;
begin
  IndyHTTPWebsocketServer1.Active := True;
end;

procedure TTestWebSockets.TestPlainHttp;
var
  strm: TMemoryStream;
  s: string;
  client: TIdHTTPWebsocketClient;
begin
  client := TIdHTTPWebsocketClient.Create(nil);
  try
    client.Host  := 'localhost';
    client.Port  := 8099;
    client.SocketIOCompatible := False;  //plain http now
    IndyHTTPWebsocketServer1.OnCommandGet   := HandleHTTPServerCommandGet;
    IndyHTTPWebsocketServer1.OnCommandOther := HandleHTTPServerCommandGet;

    strm := TMemoryStream.Create;
    try
      client.Get('http://localhost:8099/index.html', strm);
      with TStreamReader.Create(strm) do
      begin
        strm.Position := 0;
        s := ReadToEnd;
        Free;
      end;

      CheckEquals('dummy index.html', s);
    finally
      strm.Free;
    end;
  finally
    client.Free;
  end;
end;

procedure TTestWebSockets.TestSocketIOCallback;
var
  received: string;
begin
  //* client to server */
  received := '';
  IndyHTTPWebsocketServer1.SocketIO.OnEvent('TEST_EVENT',
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: ISocketIOCallback)
    begin
      received := aArgument.ToJson;
    end);

  if not IndyHTTPWebsocketClient1.Connected then
  begin
    IndyHTTPWebsocketClient1.Connect;
    IndyHTTPWebsocketClient1.UpgradeToWebsocket;
  end;
  IndyHTTPWebsocketClient1.SocketIO.Emit('TEST_EVENT',
    SO('test event'), nil);

  MaxWait(
    function: Boolean
    begin
      Result := received <> '';
    end, 10 * 1000);
  received := StringReplace(received, #13#10, '', [rfReplaceAll]);
  CheckEqualsString('["test event"]', received);

  //* server to client */
  received := '';
  IndyHTTPWebsocketClient1.SocketIO.OnEvent('TEST_EVENT',
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: ISocketIOCallback)
    begin
      received := aArgument.ToJson;
    end);
  IndyHTTPWebsocketServer1.SocketIO.EmitEventToAll('TEST_EVENT',
    SO('test event'), nil);
  MaxWait(
    function: Boolean
    begin
      Result := received <> '';
    end, 10 * 1000);
  received := StringReplace(received, #13#10, '', [rfReplaceAll]);
  CheckEqualsString('["test event"]', received);
end;

procedure TTestWebSockets.TestSocketIOError;
begin
  //disconnect: mag geen AV's daarna geven!
  IndyHTTPWebsocketClient1.Disconnect(False);
  IndyHTTPWebsocketClient1.Connect;
  IndyHTTPWebsocketClient1.UpgradeToWebsocket;

  //* client to server */
  FLastSocketIOMsg := '';
  IndyHTTPWebsocketServer1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: ISocketIOCallback)
    begin
      Abort;
    end;
  IndyHTTPWebsocketClient1.SocketIO.Send('test message',
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
      FLastSocketIOMsg := aJSON.AsString;
    end);
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('[{"Error":{"Message":"Operation aborted","Type":"EAbort"}}]', FLastSocketIOMsg);

  FLastSocketIOMsg := '';
  IndyHTTPWebsocketClient1.SocketIO.Send('test message',
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
      Assert(False, 'should go to error handling callback');
      FLastSocketIOMsg := 'error';
    end,
    procedure(const ASocket: ISocketIOContext; const aErrorClass, aErrorMessage: string)
    begin
      FLastSocketIOMsg := aErrorMessage;
    end);
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('Operation aborted', FLastSocketIOMsg);
end;

procedure TTestWebSockets.TestSocketIOMsg;
begin
  //disconnect: mag geen AV's daarna geven!
  IndyHTTPWebsocketClient1.Disconnect(True);
  IndyHTTPWebsocketClient1.ResetChannel;
  IndyHTTPWebsocketClient1.SocketIOCompatible := True;
  IndyHTTPWebsocketClient1.Connect;
  IndyHTTPWebsocketClient1.UpgradeToWebsocket;

  //* client to server */
  FLastSocketIOMsg := '';
  IndyHTTPWebsocketServer1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: ISocketIOCallback)
    begin
      FLastSocketIOMsg := aText;
    end;
  IndyHTTPWebsocketClient1.SocketIO.Send('test message');
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('test message', FLastSocketIOMsg);

  //* server to client */
  FLastSocketIOMsg := '';
  IndyHTTPWebsocketClient1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: ISocketIOCallback)
    begin
      FLastSocketIOMsg := aText;
    end;
  if IndyHTTPWebsocketServer1.SocketIO.SendToAll('test message') = 0 then
    Check(False, 'nothing send');
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('test message', FLastSocketIOMsg);

  //disconnect: mag geen AV's daarna geven!
  IndyHTTPWebsocketClient1.Disconnect(False);
  IndyHTTPWebsocketClient1.Connect;
  IndyHTTPWebsocketClient1.UpgradeToWebsocket;
  IndyHTTPWebsocketClient1.SocketIO.Send('test message');
end;

procedure TTestWebSockets.TestWebsocketMsg;
var
  client: TIdHTTPWebsocketClient;
begin
  client := TIdHTTPWebsocketClient.Create(nil);
  try
    client.Host  := 'localhost';
    client.Port  := 8099;
    client.SocketIOCompatible := False;
    client.OnTextData         := WebsocketTextMessage;
    IndyHTTPWebsocketServer1.OnMessageText := HandleWebsocketTextMessage;

    //client.Connect;
    client.UpgradeToWebsocket;
    client.IOHandler.Write('websocket client to server');

    MaxWait(
      function: Boolean
      begin
        Result := FLastWSMsg <> '';
      end, 10 * 1000);
    CheckEquals('websocket server to client', FLastWSMsg);
  finally
    client.Free;
  end;
end;

procedure TTestWebSockets.HandleWebsocketTextMessage(
  const AContext: TIdServerWSContext; const aText: string);
begin
  if aText = 'websocket client to server' then
    AContext.IOHandler.Write('websocket server to client');
end;

procedure TTestWebSockets.WebsocketTextMessage(const aData: string);
begin
  FLastWSMsg := aData;
end;


end.

