unit IdHTTPWebsocketClient;

interface

uses
  Classes,
  IdHTTP, IdHashSHA1, IdIOHandler,
  IdIOHandlerWebsocket, ExtCtrls, IdWinsock2, Generics.Collections, SyncObjs,
  IdSocketIOHandling;

type
  TDataBinEvent    = procedure(const aData: TStream) of object;
  TDataStringEvent = procedure(const aData: string) of object;

  TIdHTTPWebsocketClient = class;
  TSocketIOMsg = procedure(const AClient: TIdHTTPWebsocketClient; const aText: string; aMsgNr: Integer) of object;

  TIdSocketIOHandling_Ext = class(TIdSocketIOHandling)
  end;

  TIdHTTPWebsocketClient = class(TIdHTTP)
  private
    FWSResourceName: string;
    FHash: TIdHashSHA1;
    FOnData: TDataBinEvent;
    FOnTextData: TDataStringEvent;
    function  GetIOHandlerWS: TIdIOHandlerWebsocket;
    procedure SetIOHandlerWS(const Value: TIdIOHandlerWebsocket);
    procedure SetOnData(const Value: TDataBinEvent);
    procedure SetOnTextData(const Value: TDataStringEvent);
  protected
    FSocketIOCompatible: Boolean;
    FSocketIOHandshakeResponse: string;
    FSocketIO: TIdSocketIOHandling_Ext;
    FSocketIOContext: ISocketIOContext;
    FHeartBeat: TTimer;
    procedure HeartBeatTimer(Sender: TObject);
    function  GetSocketIO: TIdSocketIOHandling;
  protected
    procedure InternalUpgradeToWebsocket(aRaiseException: Boolean; out aFailedReason: string);virtual;
    function  MakeImplicitClientHandler: TIdIOHandler; override;
  public
    procedure AsyncDispatchEvent(const aEvent: TStream); overload; virtual;
    procedure AsyncDispatchEvent(const aEvent: string); overload; virtual;
    procedure ResetChannel;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    function  TryUpgradeToWebsocket: Boolean;
    procedure UpgradeToWebsocket;
    procedure Disconnect(ANotifyPeer: Boolean); override;

    property  IOHandler: TIdIOHandlerWebsocket read GetIOHandlerWS write SetIOHandlerWS;
    property  OnBinData : TDataBinEvent read FOnData write SetOnData;
    property  OnTextData: TDataStringEvent read FOnTextData write SetOnTextData;

    //https://github.com/LearnBoost/socket.io-spec
    property  SocketIOCompatible: Boolean read FSocketIOCompatible write FSocketIOCompatible;
    property  SocketIO: TIdSocketIOHandling read GetSocketIO;
  published
    property  Host;
    property  Port;
    property  WSResourceName: string read FWSResourceName write FWSResourceName;
  end;

//  on error
  TIdHTTPSocketIOClient_old = class(TIdHTTPWebsocketClient)
  private
    FOnConnected: TNotifyEvent;
    FOnDisConnected: TNotifyEvent;
    FOnSocketIOMsg: TSocketIOMsg;
    FOnSocketIOEvent: TSocketIOMsg;
    FOnSocketIOJson: TSocketIOMsg;
  protected
    FHeartBeat: TTimer;
    procedure HeartBeatTimer(Sender: TObject);

    procedure InternalUpgradeToWebsocket(aRaiseException: Boolean; out aFailedReason: string);override;
  public
    procedure AsyncDispatchEvent(const aEvent: string); override;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure AutoConnect;

    property  SocketIOHandshakeResponse: string read FSocketIOHandshakeResponse;
    property  OnConnected: TNotifyEvent read FOnConnected write FOnConnected;
    property  OnDisConnected: TNotifyEvent read FOnDisConnected write FOnDisConnected;

//    procedure ProcessSocketIORequest(const strmRequest: TStream);
    property  OnSocketIOMsg  : TSocketIOMsg read FOnSocketIOMsg write FOnSocketIOMsg;
    property  OnSocketIOJson : TSocketIOMsg read FOnSocketIOJson write FOnSocketIOJson;
    property  OnSocketIOEvent: TSocketIOMsg read FOnSocketIOEvent write FOnSocketIOEvent;
  end;

  TIdWebsocketMultiReadThread = class(TThread)
  private
    class var FInstance: TIdWebsocketMultiReadThread;
  protected
    FTempHandle: THandle;
    FPendingBreak: Boolean;
    Freadset, Fexceptionset: TFDSet;
    Finterval: TTimeVal;
    procedure InitSpecialEventSocket;
    procedure ResetSpecialEventSocket;
    procedure BreakSelectWait;
  protected
    FChannels: TThreadList;
    procedure ReadFromAllChannels;

    procedure Execute; override;
  public
    procedure  AfterConstruction;override;
    destructor Destroy; override;

    procedure Terminate;

    procedure AddClient   (aChannel: TIdHTTPWebsocketClient);
    procedure RemoveClient(aChannel: TIdHTTPWebsocketClient);

    class function  Instance: TIdWebsocketMultiReadThread;
    class procedure RemoveInstance;
  end;

  //async post data
  TIdWebsocketDispatchThread = class(TThread)
  private
    class var FInstance: TIdWebsocketDispatchThread;
  protected
    FEvent: TEvent;
    FEvents, FProcessing: TList<TThreadProcedure>;
    procedure Execute; override;
  public
    procedure  AfterConstruction;override;
    destructor Destroy; override;

    procedure Terminate;

    procedure QueueEvent(aEvent: TThreadProcedure);

    class function Instance: TIdWebsocketDispatchThread;
  end;

implementation

uses
  IdCoderMIME, SysUtils, Math, IdException, IdStackConsts, IdStack,
  IdStackBSDBase, IdGlobal, Windows, StrUtils, mcBaseNamedThread,
  mcFinalizationHelper;

//type
//  TAnonymousThread = class(TThread)
//  protected
//    FThreadProc: TThreadProcedure;
//    procedure Execute; override;
//  public
//    constructor Create(AThreadProc: TThreadProcedure);
//  end;

//procedure CreateAnonymousThread(AThreadProc: TThreadProcedure);
//begin
//  TAnonymousThread.Create(AThreadProc);
//end;

{ TAnonymousThread }

//constructor TAnonymousThread.Create(AThreadProc: TThreadProcedure);
//begin
//  FThreadProc := AThreadProc;
//  FreeOnTerminate := True;
//  inherited Create(False {direct start});
//end;
//
//procedure TAnonymousThread.Execute;
//begin
//  if Assigned(FThreadProc) then
//    FThreadProc();
//end;

{ TIdHTTPWebsocketClient }

procedure TIdHTTPWebsocketClient.AfterConstruction;
begin
  inherited;
  FHash := TIdHashSHA1.Create;

  IOHandler := TIdIOHandlerWebsocket.Create(nil);
  ManagedIOHandler := True;

  FSocketIO  := TIdSocketIOHandling_Ext.Create;
  FHeartBeat := TTimer.Create(nil);
  FHeartBeat.Enabled := False;
  FHeartBeat.OnTimer := HeartBeatTimer;
end;

procedure TIdHTTPWebsocketClient.AsyncDispatchEvent(const aEvent: TStream);
var
  strmevent: TMemoryStream;
begin
  if not Assigned(OnBinData) then Exit;

  strmevent := TMemoryStream.Create;
  strmevent.CopyFrom(aEvent, aEvent.Size);

  //events during dispatch? channel is busy so offload event dispatching to different thread!
  TIdWebsocketDispatchThread.Instance.QueueEvent(
    procedure
    begin
      if Assigned(OnBinData) then
        OnBinData(strmevent);
      strmevent.Free;
    end);
end;

procedure TIdHTTPWebsocketClient.AsyncDispatchEvent(const aEvent: string);
begin
  if FSocketIOCompatible then
    FSocketIO.ProcessSocketIORequest(FSocketIOContext as TSocketIOContext, aEvent)
  else
  begin
    if not Assigned(OnTextData) then Exit;
    //events during dispatch? channel is busy so offload event dispatching to different thread!
    TIdWebsocketDispatchThread.Instance.QueueEvent(
      procedure
      begin
        if Assigned(OnTextData) then
          OnTextData(aEvent);
      end);
  end;
end;

destructor TIdHTTPWebsocketClient.Destroy;
var tmr: TObject;
begin
  tmr := FHeartBeat;
  FHeartBeat := nil;
  TThread.Queue(nil,    //otherwise free in other thread than created
    procedure
    begin
      //FHeartBeat.Free;
      tmr.Free;
    end);

  TIdWebsocketMultiReadThread.Instance.RemoveClient(Self);
  FSocketIO.Free;
  FHash.Free;
  inherited;
end;

procedure TIdHTTPWebsocketClient.DisConnect(ANotifyPeer: Boolean);
begin
  TIdWebsocketMultiReadThread.Instance.RemoveClient(Self);

  if ANotifyPeer and SocketIOCompatible then
    FSocketIO.WriteDisConnect(FSocketIOContext as TSocketIOContext)
  else
    FSocketIO.FreeConnection(FSocketIOContext as TSocketIOContext);
//  IInterface(FSocketIOContext)._Release;
  FSocketIOContext := nil;

  if IOHandler <> nil then
  begin
    IOHandler.Lock;
    try
      IOHandler.IsWebsocket := False;

      inherited DisConnect(ANotifyPeer);
      //clear buffer, other still "connected"
      IOHandler.InputBuffer.Clear;

      //IOHandler.Free;
      //IOHandler := TIdIOHandlerWebsocket.Create(nil);
    finally
      IOHandler.Unlock;
    end;
  end;
end;

function TIdHTTPWebsocketClient.GetIOHandlerWS: TIdIOHandlerWebsocket;
begin
//  if inherited IOHandler is TIdIOHandlerWebsocket then
    Result := inherited IOHandler as TIdIOHandlerWebsocket
//  else
//    Assert(False);
end;

function TIdHTTPWebsocketClient.GetSocketIO: TIdSocketIOHandling;
begin
  Result := FSocketIO;
end;

procedure TIdHTTPWebsocketClient.HeartBeatTimer(Sender: TObject);
begin
  FHeartBeat.Enabled := False;
  FSocketIO.Lock;
  try
    try
      if (IOHandler <> nil) and
         not IOHandler.ClosedGracefully and
         IOHandler.Connected and
         (FSocketIOContext <> nil) then
      begin
        FSocketIO.WritePing(FSocketIOContext as TSocketIOContext);  //heartbeat socket.io message
      end
      //retry re-connect
      else
      try
        //clear inputbuffer, otherwise it can't connect :(
        if (IOHandler <> nil) and
           not IOHandler.InputBufferIsEmpty
        then
          IOHandler.DiscardAll;

        Self.Connect;
        TryUpgradeToWebsocket;
      except
        //skip, just retried
      end;
    except
      //clear inputbuffer, otherwise it stays connected :(
      if (IOHandler <> nil) and
         not IOHandler.InputBufferIsEmpty
      then
        IOHandler.DiscardAll;

      if Assigned(OnDisConnected) then
        OnDisConnected(Self);
      try
        raise EIdException.Create('Connection lost from ' + Format('ws://%s:%d/%s', [Host, Port, WSResourceName]));
      except
        //eat, no error popup!
      end;
    end;
  finally
    FSocketIO.UnLock;
    FHeartBeat.Enabled := True;  //always enable: in case of disconnect it will re-connect
  end;
end;

function TIdHTTPWebsocketClient.TryUpgradeToWebsocket: Boolean;
var
  sError: string;
begin
  InternalUpgradeToWebsocket(False{no raise}, sError);
  Result := (sError = '');
end;

procedure TIdHTTPWebsocketClient.UpgradeToWebsocket;
var
  sError: string;
begin
  InternalUpgradeToWebsocket(True{raise}, sError);
end;

procedure TIdHTTPWebsocketClient.InternalUpgradeToWebsocket(aRaiseException: Boolean; out aFailedReason: string);
var
  sURL: string;
  strmResponse: TMemoryStream;
  i: Integer;
  sKey, sResponseKey: string;
  sSocketioextended: string;
begin
  Assert(not IOHandler.IsWebsocket);

  strmResponse := TMemoryStream.Create;
  try
    //special socket.io handling, see https://github.com/LearnBoost/socket.io-spec
    if SocketIOCompatible then
    begin
      Request.Clear;
      Request.Connection := 'keep-alive';
      sURL := Format('http://%s:%d/socket.io/1/', [Host, Port]);
      strmResponse.Clear;

      //get initial handshake
      Post(sURL, strmResponse, strmResponse);
      if ResponseCode = 200 {OK} then
      begin
        //if not Connected then  //reconnect
        //  Self.Connect;
        strmResponse.Position := 0;
        //The body of the response should contain the session id (sid) given to the client,
        //followed by the heartbeat timeout, the connection closing timeout, and the list of supported transports separated by :
        //4d4f185e96a7b:15:10:websocket,xhr-polling
        with TStreamReader.Create(strmResponse) do
        try
          FSocketIOHandshakeResponse := ReadToEnd;
        finally
          Free;
        end;
        sKey := Copy(FSocketIOHandshakeResponse, 1, Pos(':', FSocketIOHandshakeResponse)-1);
        sSocketioextended := 'socket.io/1/websocket/' + sKey;
        WSResourceName := sSocketioextended;
      end
      else
      begin
        aFailedReason := Format('Initial socket.io handshake failed: "%d: %s"',[ResponseCode, ResponseText]);
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason);
      end;
    end;

    Request.Clear;
    strmResponse.Clear;
  //http://www.websocket.org/aboutwebsocket.html
  (* GET ws://echo.websocket.org/?encoding=text HTTP/1.1
     Origin: http://websocket.org
     Cookie: __utma=99as
     Connection: Upgrade
     Host: echo.websocket.org
     Sec-WebSocket-Key: uRovscZjNol/umbTt5uKmw==
     Upgrade: websocket
     Sec-WebSocket-Version: 13 *)

    //Connection: Upgrade
    Request.Connection := 'Upgrade';
    //Upgrade: websocket
    Request.CustomHeaders.Add('Upgrade: websocket');

    //Sec-WebSocket-Key
    sKey := '';
    for i := 1 to 16 do
      sKey := sKey + Char(Random(127-32) + 32);
    //base64 encoded
    sKey := TIdEncoderMIME.EncodeString(sKey);
    Request.CustomHeaders.AddValue('Sec-WebSocket-Key', sKey);
    //Sec-WebSocket-Version: 13
    Request.CustomHeaders.AddValue('Sec-WebSocket-Version', '13');

    Request.Host := Format('Host: %s:%d',[Host,Port]);
    //ws://host:port/<resourcename>
    //about resourcename, see: http://dev.w3.org/html5/websockets/ "Parsing WebSocket URLs"
    //sURL := Format('ws://%s:%d/%s', [Host, Port, WSResourceName]);
    sURL := Format('http://%s:%d/%s', [Host, Port, WSResourceName]);
    ReadTimeout := Max(2 * 1000, ReadTimeout);

    { voorbeeld:
    GET http://localhost:9222/devtools/page/642D7227-148E-47C2-B97A-E00850E3AFA3 HTTP/1.1
    Upgrade: websocket
    Connection: Upgrade
    Host: localhost:9222
    Origin: http://localhost:9222
    Pragma: no-cache
    Cache-Control: no-cache
    Sec-WebSocket-Key: HIqoAdZkxnWWH9dnVPyW7w==
    Sec-WebSocket-Version: 13
    Sec-WebSocket-Extensions: x-webkit-deflate-frame
    User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/27.0.1453.116 Safari/537.36
    Cookie: __utma=1.2040118404.1366961318.1366961318.1366961318.1; __utmc=1; __utmz=1.1366961318.1.1.utmcsr=(direct)|utmccn=(direct)|utmcmd=(none); deviceorder=0123456789101112; MultiTouchEnabled=false; device=3; network_type=0
    }
    if SocketIOCompatible then
    begin
      Response.Clear;
      Response.ResponseCode := 0;
      Request.URL    := sURL;
      Request.Method := Id_HTTPMethodGet;
      Request.Source := nil;
      Response.ContentStream := strmResponse;
      PrepareRequest(Request);

      //connect and upgrade
      ConnectToHost(Request, Response);

      //check upgrade succesfull
      CheckForGracefulDisconnect(True);
      CheckConnected;
      Assert(Self.Connected);
      if Response.ResponseCode <> 200{ok} then
      begin
        aFailedReason := Format('Error while upgrading: "%d: %s"',[ResponseCode, ResponseText]);
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason)
        else
          Exit;
      end;

      Response.Clear;
      if IOHandler.CheckForDataOnSource(ReadTimeout) then
        Response.ResponseText := IOHandler.InputBufferAsString();
      //for now: timer in mainthread?
      TThread.Queue(nil,
        procedure
        begin
          FHeartBeat.Interval := 5 * 1000;
          FHeartBeat.Enabled  := True;
        end);
    end
    else
    begin
      Get(sURL, strmResponse, [101]);

      //http://www.websocket.org/aboutwebsocket.html
      (* HTTP/1.1 101 WebSocket Protocol Handshake
         Date: Fri, 10 Feb 2012 17:38:18 GMT
         Connection: Upgrade
         Server: Kaazing Gateway
         Upgrade: WebSocket
         Access-Control-Allow-Origin: http://websocket.org
         Access-Control-Allow-Credentials: true
         Sec-WebSocket-Accept: rLHCkw/SKsO9GAH/ZSFhBATDKrU=
         Access-Control-Allow-Headers: content-type *)

      //'HTTP/1.1 101 Switching Protocols'
      if ResponseCode <> 101 then
      begin
        aFailedReason := Format('Error while upgrading: "%d: %s"',[ResponseCode, ResponseText]);
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason);
      end;
      //connection: upgrade
      if not SameText(Response.Connection, 'upgrade') then
      begin
        aFailedReason := Format('Connection not upgraded: "%s"',[Response.Connection]);
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason);
      end;
      //upgrade: websocket
      if not SameText(Response.RawHeaders.Values['upgrade'], 'websocket') then
      begin
        aFailedReason := Format('Not upgraded to websocket: "%s"',[Response.RawHeaders.Values['upgrade']]);
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason);
      end;
      //check handshake key
      sResponseKey := Trim(sKey) +                                         //... "minus any leading and trailing whitespace"
                      '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';              //special GUID
      sResponseKey := TIdEncoderMIME.EncodeBytes(                          //Base64
                           FHash.HashString(sResponseKey) );               //SHA1
      if not SameText(Response.RawHeaders.Values['sec-websocket-accept'], sResponseKey) then
      begin
        aFailedReason := 'Invalid key handshake';
        if aRaiseException then
          raise EIdWebSocketHandleError.Create(aFailedReason);
      end;
    end;

    //upgrade succesful
    IOHandler.IsWebsocket := True;
    aFailedReason := '';

    //always read the data! (e.g. RO use override of AsyncDispatchEvent to process data)
    //if Assigned(OnBinData) or Assigned(OnTextData) then
    TIdWebsocketMultiReadThread.Instance.AddClient(Self);

    if SocketIOCompatible then
    begin
//      if FSocketIOContext = nil then
//      begin
        FSocketIOContext := TSocketIOContext.Create(Self);
//        IInterface(FSocketIOContext)._AddRef;
//      end
//      else
//        FSocketIOContext.Create(Self); //update with new iohandler etc
      FSocketIO.WriteConnect(FSocketIOContext as TSocketIOContext);
    end;
  finally
    Request.Clear;
    strmResponse.Free;
  end;
end;

function TIdHTTPWebsocketClient.MakeImplicitClientHandler: TIdIOHandler;
begin
  Result := TIdIOHandlerWebsocket.Create(nil);
end;

procedure TIdHTTPWebsocketClient.ResetChannel;
//var
//  ws: TIdIOHandlerWebsocket;
begin
  TIdWebsocketMultiReadThread.Instance.RemoveClient(Self);

  if IOHandler <> nil then
  begin
    IOHandler.InputBuffer.Clear;
    //close/disconnect internal socket
    //ws := IndyClient.IOHandler as TIdIOHandlerWebsocket;
    //ws.Close;  done in disconnect below
  end;
  Disconnect(False);
end;

procedure TIdHTTPWebsocketClient.SetIOHandlerWS(
  const Value: TIdIOHandlerWebsocket);
begin
  SetIOHandler(Value);
end;

procedure TIdHTTPWebsocketClient.SetOnData(const Value: TDataBinEvent);
begin
//  if not Assigned(Value) and not Assigned(FOnTextData) then
//    TIdWebsocketMultiReadThread.Instance.RemoveClient(Self);

  FOnData := Value;

  if Assigned(Value) and
     (Self.IOHandler as TIdIOHandlerWebsocket).IsWebsocket
  then
    TIdWebsocketMultiReadThread.Instance.AddClient(Self);
end;

procedure TIdHTTPWebsocketClient.SetOnTextData(const Value: TDataStringEvent);
begin
//  if not Assigned(Value) and not Assigned(FOnData) then
//    TIdWebsocketMultiReadThread.Instance.RemoveClient(Self);

  FOnTextData := Value;

  if Assigned(Value) and
     (Self.IOHandler as TIdIOHandlerWebsocket).IsWebsocket
  then
    TIdWebsocketMultiReadThread.Instance.AddClient(Self);
end;

{ TIdHTTPSocketIOClient }

procedure TIdHTTPSocketIOClient_old.AfterConstruction;
begin
  inherited;
  SocketIOCompatible := True;

  FHeartBeat := TTimer.Create(nil);
  FHeartBeat.Enabled := False;
  FHeartBeat.OnTimer := HeartBeatTimer;
end;

procedure TIdHTTPSocketIOClient_old.AsyncDispatchEvent(const aEvent: string);
begin
  //https://github.com/LearnBoost/socket.io-spec
  if StartsStr('1:', aEvent) then  //connect
    Exit;
  if aEvent = '2::' then  //ping, heartbeat
    Exit;
  inherited AsyncDispatchEvent(aEvent);
end;

procedure TIdHTTPSocketIOClient_old.AutoConnect;
begin
  //for now: timer in mainthread?
  TThread.Queue(nil,
    procedure
    begin
      FHeartBeat.Interval := 5 * 1000;
      FHeartBeat.Enabled  := True;
    end);
end;

destructor TIdHTTPSocketIOClient_old.Destroy;
var tmr: TObject;
begin
  tmr := FHeartBeat;
  TThread.Queue(nil,    //otherwise free in other thread than created
    procedure
    begin
      //FHeartBeat.Free;
      tmr.Free;
    end);
  inherited;
end;

procedure TIdHTTPSocketIOClient_old.HeartBeatTimer(Sender: TObject);
begin
  FHeartBeat.Enabled := False;
  try
    try
      if (IOHandler <> nil) and
         not IOHandler.ClosedGracefully and
         IOHandler.Connected then
      begin
        IOHandler.Write('2:::');  //heartbeat socket.io message
      end
      //retry connect
      else
      try
        //clear inputbuffer, otherwise it can't connect :(
        if (IOHandler <> nil) and
           not IOHandler.InputBufferIsEmpty
        then
          IOHandler.DiscardAll;

        Self.Connect;
        TryUpgradeToWebsocket;
      except
        //skip, just retried
      end;
    except
      //clear inputbuffer, otherwise it stays connected :(
      if (IOHandler <> nil) and
         not IOHandler.InputBufferIsEmpty
      then
        IOHandler.DiscardAll;

      if Assigned(OnDisConnected) then
        OnDisConnected(Self);
      try
        raise EIdException.Create('Connection lost from ' + Format('ws://%s:%d/%s', [Host, Port, WSResourceName]));
      except
        //eat, no error popup!
      end;
    end;
  finally
    FHeartBeat.Enabled := True;  //always enable: in case of disconnect it will re-connect
  end;
end;

procedure TIdHTTPSocketIOClient_old.InternalUpgradeToWebsocket(
  aRaiseException: Boolean; out aFailedReason: string);
var
  stimeout: string;
begin
  inherited InternalUpgradeToWebsocket(aRaiseException, aFailedReason);

  if (aFailedReason = '') and
     (IOHandler as TIdIOHandlerWebsocket).IsWebsocket then
  begin
    stimeout := Copy(SocketIOHandshakeResponse, Pos(':', SocketIOHandshakeResponse)+1, Length(SocketIOHandshakeResponse));
    stimeout := Copy(stimeout, 1, Pos(':', stimeout)-1);
    if stimeout <> '' then
    begin
      //if (FHeartBeat.Interval > 0) then
        //for now: timer in mainthread?
        TThread.Queue(nil,
          procedure
          begin
            FHeartBeat.Interval := StrToIntDef(stimeout, 15) * 1000;
            if FHeartBeat.Interval >= 15000 then
              //FHeartBeat.Interval := FHeartBeat.Interval - 5000
              FHeartBeat.Interval := 5000
            else if FHeartBeat.Interval >= 5000 then
              FHeartBeat.Interval := FHeartBeat.Interval - 2000;

            FHeartBeat.Enabled := (FHeartBeat.Interval > 0);
          end);
    end;

    if Assigned(OnConnected) then
      OnConnected(Self);
  end;
end;

(*)
procedure TIdHTTPSocketIOClient_old.ProcessSocketIORequest(
  const strmRequest: TStream);

  function __ReadToEnd: string;
  var
    utf8: TBytes;
    ilength: Integer;
  begin
    Result := '';
    ilength := strmRequest.Size - strmRequest.Position;
    SetLength(utf8, ilength);
    strmRequest.Read(utf8[0], ilength);
    Result := TEncoding.UTF8.GetString(utf8);
  end;

  function __GetSocketIOPart(const aData: string; aIndex: Integer): string;
  var ipos: Integer;
    i: Integer;
  begin
    //'5::/chat:{"name":"hi!"}'
    //0 = 5
    //1 =
    //2 = /chat
    //3 = {"name":"hi!"}
    ipos := 0;
    for i := 0 to aIndex-1 do
      ipos := PosEx(':', aData, ipos+1);
    if ipos >= 0 then
    begin
      Result := Copy(aData, ipos+1, Length(aData));
      if aIndex < 3 then                      // /chat:{"name":"hi!"}'
      begin
        ipos   := PosEx(':', Result, 1);      // :{"name":"hi!"}'
        if ipos > 0 then
          Result := Copy(Result, 1, ipos-1);  // /chat
      end;
    end;
  end;

var
  str, smsg, schannel, sdata: string;
  imsg: Integer;
//  bCallback: Boolean;
begin
  str := __ReadToEnd;
  if str = '' then Exit;

  //5:1+:/chat:test
  smsg      := __GetSocketIOPart(str, 1);
  imsg      := 0;
//  bCallback := False;
  if smsg <> '' then                                       // 1+
  begin
    imsg    := StrToIntDef(ReplaceStr(smsg,'+',''), 0);    // 1
//    bCallback := (Pos('+', smsg) > 1);  //trailing +, e.g.    1+
  end;
  schannel  := __GetSocketIOPart(str, 2);                  // /chat
  sdata     := __GetSocketIOPart(str, 3);                  // test

  //(0) Disconnect
  if StartsStr('0:', str) then
  begin
    schannel := __GetSocketIOPart(str, 2);
    if schannel <> '' then
      //todo: close channel
    else
      Self.Disconnect;
  end
  //(1) Connect
  //'1::' [path] [query]
  else if StartsStr('1:', str) then
  begin
    //todo: add channel/room to authorized channel/room list
    Self.IOHandler.Write(str);  //write same connect back, e.g. 1::/chat
  end
  //(2) Heartbeat
  else if StartsStr('2:', str) then
  begin
    Self.IOHandler.Write(str);  //write same connect back, e.g. 2::
  end
  //(3) Message (https://github.com/LearnBoost/socket.io-spec#3-message)
  //'3:' [message id ('+')] ':' [message endpoint] ':' [data]
  //3::/chat:hi
  else if StartsStr('3:', str) then
  begin
    if Assigned(OnSocketIOMsg) then
      OnSocketIOMsg(Self, sdata, imsg);
  end
  //(4) JSON Message
  //'4:' [message id ('+')] ':' [message endpoint] ':' [json]
  //4:1::{"a":"b"}
  else if StartsStr('4:', str) then
  begin
    if Assigned(OnSocketIOJson) then
      OnSocketIOJson(Self, sdata, imsg);
  end
  //(5) Event
  //'5:' [message id ('+')] ':' [message endpoint] ':' [json encoded event]
  //5::/chat:{"name":"my other event","args":[{"my":"data"}]}
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  else if StartsStr('5:', str) then
  begin
    if Assigned(OnSocketIOEvent) then
      OnSocketIOEvent(Self, sdata, imsg);
  end
  //(6) ACK
  //6::/news:1+["callback"]
  //6:::1+["Response"]
  //(7) Error
  //(8) Noop
  else if StartsStr('8:', str) then
  begin
    //nothing
  end
  else
    raise Exception.CreateFmt('Unsupported data: "%s"', [str]);
end;
*)

{ TIdWebsocketMultiReadThread }

procedure TIdWebsocketMultiReadThread.AddClient(
  aChannel: TIdHTTPWebsocketClient);
var l: TList;
begin
  Assert( (aChannel.IOHandler as TIdIOHandlerWebsocket).IsWebsocket, 'Channel is not a websocket');

  l := FChannels.LockList;
  try
    //already exists?
    if l.IndexOf(aChannel) >= 0 then Exit;
    
    Assert(l.Count < 64, 'Max 64 connections can be handled by one read thread!');  //due to restrictions of the "select" API
    l.Add(aChannel);

    //trigger the "select" wait
    BreakSelectWait;
  finally
    FChannels.UnlockList;
  end;
end;

procedure TIdWebsocketMultiReadThread.AfterConstruction;
begin
  inherited;
  FChannels := TThreadList.Create;
  FillChar(Freadset, SizeOf(Freadset), 0);
  FillChar(Fexceptionset, SizeOf(Fexceptionset), 0);

  InitSpecialEventSocket;
end;

procedure TIdWebsocketMultiReadThread.BreakSelectWait;
var
  iResult: Integer;
  LAddr: TSockAddrIn6;
begin
  FillChar(LAddr, SizeOf(LAddr), 0);
  //Id_IPv4
  with PSOCKADDR(@LAddr)^ do
  begin
    sin_family := Id_PF_INET4;
    //dummy address and port
    (GStack as TIdStackBSDBase).TranslateStringToTInAddr('0.0.0.0', sin_addr, Id_IPv4);
    sin_port := htons(1);
  end;

  FPendingBreak := True;

  //connect to non-existing address to stop "select" from waiting
  //Note: this is some kind of "hack" because there is no nice way to stop it
  //The only(?) other possibility is to make a "socket pair" and send a byte to it,
  //but this requires a dynamic server socket (which can trigger a firewall
  //exception/question popup in WindowsXP+)
  iResult := IdWinsock2.connect(FTempHandle, PSOCKADDR(@LAddr), SIZE_TSOCKADDRIN);
  //non blocking socket, so will always result in "would block"!
  if (iResult <> Id_SOCKET_ERROR) or
     ( (GStack <> nil) and (GStack.WSGetLastError <> WSAEWOULDBLOCK) )
  then
    GStack.CheckForSocketError(iResult);
end;

destructor TIdWebsocketMultiReadThread.Destroy;
begin
  IdWinsock2.closesocket(FTempHandle);
  FChannels.Free;
  inherited;
end;

procedure TIdWebsocketMultiReadThread.Execute;
begin
  Self.NameThreadForDebugging(AnsiString(Self.ClassName));

  while not Terminated do
  begin
    try
      while not Terminated do
        ReadFromAllChannels;
    except
      //continue
    end;
  end;
end;

procedure TIdWebsocketMultiReadThread.InitSpecialEventSocket;
var
  param: Cardinal;
  iResult: Integer;
begin
  if GStack = nil then Exit; //finalized?
  
  //alloc socket
  FTempHandle := GStack.NewSocketHandle(Id_SOCK_STREAM, Id_IPPROTO_IP, Id_IPv4, False);
  Assert(FTempHandle <> Id_INVALID_SOCKET);
  //non block mode
  param   := 1; // enable NON blocking mode
  iResult := ioctlsocket(FTempHandle, FIONBIO, param);
  GStack.CheckForSocketError(iResult);
end;

class function TIdWebsocketMultiReadThread.Instance: TIdWebsocketMultiReadThread;
begin
  if (FInstance = nil) and
     not TFinalizationHelper.ApplicationIsTerminating then
  begin
    FInstance := TIdWebsocketMultiReadThread.Create(True);
    FInstance.Start;
  end;
  Result := FInstance;
end;

procedure TIdWebsocketMultiReadThread.ReadFromAllChannels;
var
  l: TList;
  chn: TIdHTTPWebsocketClient;
  iCount,
  i: Integer;
  iResult: NativeInt;
  strmEvent: TMemoryStream;
  swstext: utf8string;
  ws: TIdIOHandlerWebsocket;
  wscode: TWSDataCode;
begin
  l := FChannels.LockList;
  try
    iCount := 0;
    Freadset.fd_count := iCount;

    for i := 0 to l.Count - 1 do
    begin
      chn := TIdHTTPWebsocketClient(l.Items[i]);
      //valid?
      if //not chn.Busy and    also take busy channels (will be ignored later), otherwise we have to break/reset for each RO function execution
         (chn.Socket.Binding.Handle > 0) and
         (chn.Socket.Binding.Handle <> INVALID_SOCKET) then
      begin
        Freadset.fd_count         := iCount+1;
        Freadset.fd_array[iCount] := chn.Socket.Binding.Handle;
        Inc(iCount);
      end;
    end;

    if FPendingBreak then
      ResetSpecialEventSocket;
  finally
    FChannels.UnlockList;
  end;

  //special helper socket to be able to stop "select" from waiting
  Fexceptionset.fd_count    := 1;
  Fexceptionset.fd_array[0] := FTempHandle;

  //wait 15s till some data
  Finterval.tv_sec  := 15; //15s
  Finterval.tv_usec := 0;

  //nothing to wait for? then sleep some time to prevent 100% CPU
  if iCount = 0 then
  begin
    iResult := IdWinsock2.select(0, nil, nil, @Fexceptionset, @Finterval);
    if iResult = SOCKET_ERROR then
      iResult := 1;  //ignore errors
  end
  //wait till a socket has some data (or a signal via exceptionset is fired)
  else
    iResult := IdWinsock2.select(0, @Freadset, nil, @Fexceptionset, @Finterval);

  if iResult = SOCKET_ERROR then
    //raise EIdWinsockStubError.Build(WSAGetLastError, '', []);
    //ignore error during wait: socket disconnected etc
    Exit;

  if Terminated then Exit;  

  //some data?
  if (iResult > 0) then
  begin
    strmEvent := nil;

    l := FChannels.LockList;
    try
      //check for data for all channels
      for i := 0 to l.Count - 1 do
      begin
        chn := TIdHTTPWebsocketClient(l.Items[i]);
        try
          //try to process all events
          while chn.IOHandler.Readable(0) do //has some data
          begin
            ws  := chn.IOHandler as TIdIOHandlerWebsocket;
            //no pending dispatch active? (so actually we only read events here?)
            if ws.TryLock then
            begin
              try
                if strmEvent = nil then
                  strmEvent := TMemoryStream.Create;
                strmEvent.Clear;

                //first is the data type TWSDataType(text or bin), but is ignore/not needed
                wscode := TWSDataCode(chn.IOHandler.ReadLongWord);
                //next the size + data = stream
                chn.IOHandler.ReadStream(strmEvent);

                //ignore ping/pong messages
                if wscode in [wdcPing, wdcPong] then Continue;
              finally
                ws.Unlock;
              end;

              //fire event
              //offload event dispatching to different thread! otherwise deadlocks possible? (do to synchronize)
              strmEvent.Position := 0;
              if wscode = wdcBinary then
              begin
                chn.AsyncDispatchEvent(strmEvent);
              end
              else if wscode = wdcText then
              begin
                SetLength(swstext, strmEvent.Size);
                strmEvent.Read(swstext[1], strmEvent.Size);
                if swstext <> '' then
                begin
                  chn.AsyncDispatchEvent(string(swstext));
                end;
              end;
            end;
          end;
        except
          l := nil;
          FChannels.UnlockList;
          chn.ResetChannel;
          raise;
        end;
      end;

      if FPendingBreak then
        ResetSpecialEventSocket;
    finally
      if l <> nil then
        FChannels.UnlockList;
      strmEvent.Free;
    end;
  end;
end;

procedure TIdWebsocketMultiReadThread.RemoveClient(
  aChannel: TIdHTTPWebsocketClient);
begin
  if Self = nil then Exit;
  FChannels.Remove(aChannel);
  BreakSelectWait;
end;

class procedure TIdWebsocketMultiReadThread.RemoveInstance;
begin
  if FInstance <> nil then
    FreeAndNil(FInstance);
end;

procedure TIdWebsocketMultiReadThread.ResetSpecialEventSocket;
begin
  Assert(FPendingBreak);
  FPendingBreak := False;

  IdWinsock2.closesocket(FTempHandle);
  InitSpecialEventSocket;
end;

procedure TIdWebsocketMultiReadThread.Terminate;
begin
  inherited Terminate;

  FChannels.LockList;
  try
    //fire a signal, so the "select" wait will quit and thread can stop
    BreakSelectWait;
  finally
    FChannels.UnlockList;
  end;
end;

{ TIdWebsocketDispatchThread }

procedure TIdWebsocketDispatchThread.AfterConstruction;
begin
  inherited;
  FEvents     := TList<TThreadProcedure>.Create;
  FProcessing := TList<TThreadProcedure>.Create;
  FEvent  := TEvent.Create;
end;

destructor TIdWebsocketDispatchThread.Destroy;
begin
  System.TMonitor.Enter(FEvents);
  FEvents.Clear;
  FEvents.Free;
  FProcessing.Free;

  FEvent.Free;
  inherited;
end;

procedure TIdWebsocketDispatchThread.Execute;
var
  proc: Classes.TThreadProcedure;
begin
  while not Terminated do
  begin
    try
      if FEvent.WaitFor(3 * 1000) = wrSignaled then
      begin
        FEvent.ResetEvent;
        System.TMonitor.Enter(FEvents);
        try
          //copy
          while FEvents.Count > 0 do
          begin
            proc := FEvents.Items[0];
            FProcessing.Add(proc);
            FEvents.Delete(0);
          end;
        finally
          System.TMonitor.Exit(FEvents);
        end;
      end;

      while FProcessing.Count > 0 do
      begin
        proc := FProcessing.Items[0];
        FProcessing.Delete(0);
        proc();
      end;
    except
      //continue
    end;
  end;
end;

class function TIdWebsocketDispatchThread.Instance: TIdWebsocketDispatchThread;
begin
  if FInstance = nil then
  begin
    FInstance := TIdWebsocketDispatchThread.Create(True);
    FInstance.Start;
  end;
  Result := FInstance;
end;

procedure TIdWebsocketDispatchThread.QueueEvent(aEvent: TThreadProcedure);
begin
  System.TMonitor.Enter(FEvents);
  try
    FEvents.Add(aEvent);
  finally
    System.TMonitor.Exit(FEvents);
  end;
  FEvent.SetEvent;
end;

procedure TIdWebsocketDispatchThread.Terminate;
begin
  inherited Terminate;
  FEvent.SetEvent;
end;

initialization
finalization
  if TIdWebsocketMultiReadThread.FInstance <> nil then
  begin
    TIdWebsocketMultiReadThread.Instance.Terminate;
    TBaseNamedThread.WaitForThread(TIdWebsocketMultiReadThread.Instance, 5 * 1000);
    TIdWebsocketMultiReadThread.RemoveInstance;
  end;

end.
