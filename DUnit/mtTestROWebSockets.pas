unit mtTestROWebSockets;

interface

uses
  TestFramework, NewLibrary_Intf,
  uROIndyHTTPWebsocketChannel, uROHTTPWebsocketServer,
  uROJSONMessage, uRORemoteService, IdHTTPWebsocketClient,
  IdServerWebsocketContext;

type
  TTextCallback = reference to procedure(aText: string);

  TTestROWebSockets = class(TTestCase)
  private
    class var ROIndyHTTPWebsocketServer1: TROIndyHTTPWebsocketServer;
    class var ROIndyHTTPWebsocketChannel1: TROIndyHTTPWebsocketChannel;
    class var ROJSONMessage1: TROJSONMessage;
    class var RORemoteService1: TRORemoteService;
  protected
    FLastSocketIOMsg: string;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure CreateObjects;

    procedure StartRO;
    procedure TestSum;
    procedure TestIntermediateProgress;

    procedure DestroyObjects;
  end;

implementation

uses
  NewService_Impl, SysUtils, IdSocketIOHandling, superobject;

{ TTestROWebSockets }

procedure TTestROWebSockets.SetUp;
begin
  inherited;
end;

//procedure TTestROWebSockets.SocketIOMsgClient(
//  const AClient: TIdHTTPWebsocketClient; const aText: string; aMsgNr: Integer);
//begin
//  FLastSocketIOMsg := aText;
//  if Assigned(FOnSocketIOMsg) then
//    FOnSocketIOMsg(aText);
//end;

//procedure TTestROWebSockets.SocketIOMsgServer(
//  const AContext: TIdServerWSContext; const aText: string; aMsgNr: Integer;
//  aHasCallback: Boolean);
//begin
//  FLastSocketIOMsg := aText;
//  if aHasCallback then
//    AContext.IOHandler.WriteSocketIOResult(aMsgNr, '', aText);
//end;

procedure TTestROWebSockets.TearDown;
begin
  inherited;
end;

procedure TTestROWebSockets.CreateObjects;
begin
  ROIndyHTTPWebsocketServer1 := TROIndyHTTPWebsocketServer.Create(nil);
  ROIndyHTTPWebsocketServer1.Port := 8099;
  ROIndyHTTPWebsocketServer1.KeepAlive := True;
  ROIndyHTTPWebsocketServer1.DisableNagle := True;
  //SendClientAccessPolicyXml = captAllowAll
  //SendCrossOriginHeader = True

  ROIndyHTTPWebsocketChannel1 := TROIndyHTTPWebsocketChannel.Create(nil);
  ROIndyHTTPWebsocketChannel1.Port := 8099;
  ROIndyHTTPWebsocketChannel1.Host := '127.0.0.1';
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIOCompatible := True;

  ROJSONMessage1   := TROJSONMessage.Create(nil);

  ROIndyHTTPWebsocketServer1.Dispatchers.Add;
  ROIndyHTTPWebsocketServer1.Dispatchers[0].Message := ROJSONMessage1;
  ROIndyHTTPWebsocketServer1.Dispatchers[0].Enabled := True;

  RORemoteService1 := TRORemoteService.Create(nil);
  RORemoteService1.Channel := ROIndyHTTPWebsocketChannel1;
  RORemoteService1.Message := ROJSONMessage1;
end;

procedure TTestROWebSockets.DestroyObjects;
begin
  ROIndyHTTPWebsocketServer1.Free;

  RORemoteService1.Free;
  ROIndyHTTPWebsocketChannel1.Free;
  ROJSONMessage1.Free;
end;

procedure TTestROWebSockets.StartRO;
begin
  ROIndyHTTPWebsocketServer1.Active := True;
  ROIndyHTTPWebsocketChannel1.IndyClient.Connect;
end;

procedure TTestROWebSockets.TestIntermediateProgress;
var
  iresult: Integer;
  iprevious: Integer;
begin
//  ROIndyHTTPWebsocketChannel1.IndyClient.OnSocketIOMsg := SocketIOMsgClient;
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
    var icount: Integer;
    begin
      FLastSocketIOMsg := aText;

      icount := StrToInt(aText);
      //elke keer moet counter met 1 opgehoogd worden!
      //see NewService_Impl
      CheckEquals(iprevious+1, icount);
      iprevious := icount;
    end;

  FLastSocketIOMsg := '';
  iprevious        := 0;
//  FOnSocketIOMsg   :=
//    procedure(aText: string)
//    var icount: Integer;
//    begin
//      icount := StrToInt(aText);
//      elke keer moet counter met 1 opgehoogd worden!
//      see NewService_Impl
//      CheckEquals(iprevious+1, icount);
//      iprevious := icount;
//    end;

  iresult := (RORemoteService1 as INewService).LongDurationIntermediateSocketIOResults(
                 2*1000, 100);
  //result = counter, dus moet overeenkomen met laatste callback
  CheckEquals(iprevious, iresult);
end;

procedure TTestROWebSockets.TestSocketIOCallback;
var
  received: string;
begin
  //* client to server */
  received := '';
  ROIndyHTTPWebsocketServer1.SocketIO.OnEvent('TEST_EVENT',
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: TSocketIOCallbackObj)
    begin
      received := aArgument.ToJson;
    end);

  if not ROIndyHTTPWebsocketChannel1.IndyClient.Connected then
  begin
    ROIndyHTTPWebsocketChannel1.IndyClient.Connect;
    ROIndyHTTPWebsocketChannel1.IndyClient.UpgradeToWebsocket;
  end;
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.Emit('TEST_EVENT',
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
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.OnEvent('TEST_EVENT',
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallbackObj: TSocketIOCallbackObj)
    begin
      received := aArgument.ToJson;
    end);
  ROIndyHTTPWebsocketServer1.SocketIO.EmitEventToAll('TEST_EVENT',
    SO('test event'), nil);
  MaxWait(
    function: Boolean
    begin
      Result := received <> '';
    end, 10 * 1000);
  received := StringReplace(received, #13#10, '', [rfReplaceAll]);
  CheckEqualsString('["test event"]', received);
end;

procedure TTestROWebSockets.TestSocketIOError;
begin
  //disconnect: mag geen AV's daarna geven!
  ROIndyHTTPWebsocketChannel1.IndyClient.Disconnect(False);
  ROIndyHTTPWebsocketChannel1.IndyClient.Connect;
  ROIndyHTTPWebsocketChannel1.IndyClient.UpgradeToWebsocket;

  //* client to server */
  FLastSocketIOMsg := '';
  ROIndyHTTPWebsocketServer1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
    begin
      Abort;
    end;
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.Send('test message',
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
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.Send('test message',
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

procedure TTestROWebSockets.TestSocketIOMsg;
begin
  //disconnect: mag geen AV's daarna geven!
  ROIndyHTTPWebsocketChannel1.IndyClient.Disconnect(False);
  ROIndyHTTPWebsocketChannel1.IndyClient.Connect;
  ROIndyHTTPWebsocketChannel1.IndyClient.UpgradeToWebsocket;

  //* client to server */
  FLastSocketIOMsg := '';
  ROIndyHTTPWebsocketServer1.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
    begin
      FLastSocketIOMsg := aText;
    end;
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.Send('test message');
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('test message', FLastSocketIOMsg);

  //* server to client */
  FLastSocketIOMsg := '';
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.OnSocketIOMsg :=
    procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: TSocketIOCallbackObj)
    begin
      FLastSocketIOMsg := aText;
    end;
  if ROIndyHTTPWebsocketServer1.SocketIO.SendToAll('test message') = 0 then
    Check(False, 'nothing send');
  MaxWait(
    function: Boolean
    begin
      Result := FLastSocketIOMsg <> '';
    end, 10 * 1000);
  CheckEquals('test message', FLastSocketIOMsg);

  //disconnect: mag geen AV's daarna geven!
  ROIndyHTTPWebsocketChannel1.IndyClient.Disconnect(False);
  ROIndyHTTPWebsocketChannel1.IndyClient.Connect;
  ROIndyHTTPWebsocketChannel1.IndyClient.UpgradeToWebsocket;
  ROIndyHTTPWebsocketChannel1.IndyClient.SocketIO.Send('test message');
end;

procedure TTestROWebSockets.TestSum;
var
  iresult: Integer;
begin
  iresult := (RORemoteService1 as INewService).Sum(1,2);
  CheckEquals(1+2, iresult);
end;

end.

