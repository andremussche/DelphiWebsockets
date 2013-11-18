unit mtTestWebSockets;

interface

uses
  TestFramework,
  IdHTTPWebsocketClient, IdServerWebsocketContext, IdWebsocketServer;

type
  TTextCallback = reference to procedure(aText: string);

  TTestWebSockets = class(TTestCase)
  private
    class var IndyHTTPWebsocketServer1: TIdWebsocketServer;
    class var IndyHTTPWebsocketClient1: TIdHTTPWebsocketClient;
  protected
    FLastSocketIOMsg: string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreateObjects;

    procedure StartServer;

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
  IdSocketIOHandling, superobject;

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

procedure TTestWebSockets.StartServer;
begin
  IndyHTTPWebsocketServer1.Active := True;
end;

procedure TTestWebSockets.TestSocketIOCallback;
var
  received: string;
begin
  //* client to server */
  received := '';
  IndyHTTPWebsocketServer1.SocketIO.OnEvent('TEST_EVENT',
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: TSocketIOCallbackObj)
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
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: TSocketIOCallbackObj)
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
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
    begin
      Abort;
    end;
  IndyHTTPWebsocketClient1.SocketIO.Send('test message',
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: TSocketIOCallbackObj)
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
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: TSocketIOCallbackObj)
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
  IndyHTTPWebsocketClient1.Disconnect(False);
  IndyHTTPWebsocketClient1.Connect;
  IndyHTTPWebsocketClient1.UpgradeToWebsocket;

  //* client to server */
  FLastSocketIOMsg := '';
  IndyHTTPWebsocketServer1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
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
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
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

end.

