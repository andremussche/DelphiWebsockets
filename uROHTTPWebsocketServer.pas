unit uROHTTPWebsocketServer;

interface

uses
  Classes, IdServerIOHandlerWebsocket, IdIOHandlerWebsocket,
  uROIndyHTTPServer, uROClientIntf, uROServer, uROHTTPDispatch,
  IdContext, IdCustomHTTPServer, IdCustomTCPServer, uROHash, uROServerIntf,
  IdServerWebsocketContext, IdServerSocketIOHandling,
  IdServerWebsocketHandling;

type
  TROTransportContext = class;

  TROIndyHTTPWebsocketServer = class(TROIndyHTTPServer)
  private
    FOnCustomChannelExecute: TWebsocketChannelRequest;
    FSocketIO: TIdServerSocketIOHandling_Ext;
    function GetSocketIO: TIdServerSocketIOHandling;
  protected
    FROTransportContexts: TInterfaceList;
    procedure InternalServerConnect(AThread: TIdContext); override;
    procedure InternalServerDisConnect(AThread: TIdContext); virtual;
    procedure InternalServerCommandGet(AThread: TIdThreadClass;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo); override;
    procedure ProcessRemObjectsRequest(const AThread: TIdContext; const strmRequest: TMemoryStream; const strmResponse: TMemoryStream);

    function GetDispatchersClass: TROMessageDispatchersClass; override;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;
    procedure  Loaded; override;

    property SocketIO: TIdServerSocketIOHandling read GetSocketIO;
    property OnCustomChannelExecute: TWebsocketChannelRequest read FOnCustomChannelExecute write FOnCustomChannelExecute;
  end;

  TROHTTPDispatcher_Websocket = class(TROHTTPDispatcher)
  public
    function CanHandleMessage(const aTransport: IROTransport; aRequeststream : TStream): boolean; override;
  end;

  TROHTTPMessageDispatchers_WebSocket = class(TROHTTPMessageDispatchers)
  protected
    function GetDispatcherClass : TROMessageDispatcherClass; override;
  end;

  TROTransportContext = class(TInterfacedObject,
                       IROTransport, IROTCPTransport,
                       IROActiveEventServer)
  private
    FROServer: TROIndyHTTPServer;
    FIdContext: TIdServerWSContext;
    FEventCount: Integer;
    FClientId: TGUID;
  private
    class var FGlobalEventCount: Integer;
  protected
    {IROTransport}
    function GetTransportObject: TObject;
    {IROTCPTransport}
    function GetClientAddress : string;
    {IROActiveEventServer}
    procedure EventsRegistered(aSender : TObject; aClient: TGUID);
    procedure DispatchEvent(anEventDataItem : TROEventData; aSessionReference : TGUID; aSender: TObject); // asender is TROEventRepository
  public
    //constructor Create(aROServer: TROIndyHTTPServer; aIOHandler: TIdIOHandlerWebsocket);
    constructor Create(aROServer: TROIndyHTTPServer; aIdContext: TIdServerWSContext);

    property Context: TIdServerWSContext read FIdContext;
    property ClientId: TGUID read FClientId write FClientId;
  end;

  procedure Register;

implementation

uses
  SysUtils, IdCoderMIME, Windows, uROEventRepository, uROSessions, uROClient,
  uROClasses, StrUtils, uROIdServerWebsocketHandling;

procedure Register;
begin
  RegisterComponents('RBK', [TROIndyHTTPWebsocketServer]);
end;

procedure TROIndyHTTPWebsocketServer.AfterConstruction;
begin
  inherited;

  FSocketIO := TIdServerSocketIOHandling_Ext.Create;
  FROTransportContexts := TInterfaceList.Create;

  IndyServer.ContextClass := TROIdServerWSContext;
  if Self.IndyServer.IOHandler = nil then
    IndyServer.IOHandler := TIdServerIOHandlerWebsocket.Create(Self);
  IndyServer.OnDisconnect := InternalServerDisConnect;
end;

destructor TROIndyHTTPWebsocketServer.Destroy;
begin
  inherited;
  FSocketIO.Free;
  FROTransportContexts.Free;
end;

function TROIndyHTTPWebsocketServer.GetDispatchersClass: TROMessageDispatchersClass;
begin
  Result := TROHTTPMessageDispatchers_Websocket;
end;

function TROIndyHTTPWebsocketServer.GetSocketIO: TIdServerSocketIOHandling;
begin
  Result := FSocketIO;
end;

procedure TROIndyHTTPWebsocketServer.InternalServerCommandGet(AThread: TIdThreadClass;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  (AThread as TIdServerWSContext).OnCustomChannelExecute := Self.OnCustomChannelExecute;
  (AThread as TIdServerWSContext).SocketIO               := Self.FSocketIO;
  (AThread as TROIdServerWSContext).OnRemObjectsRequest  := Self.ProcessRemObjectsRequest;

  if not TROIdServerWebsocketHandling.ProcessServerCommandGet(AThread as TIdServerWSContext, ARequestInfo, AResponseInfo) then
    inherited InternalServerCommandGet(AThread, ARequestInfo, AResponseInfo)
end;


procedure TROIndyHTTPWebsocketServer.InternalServerConnect(AThread: TIdContext);
begin
  inherited;
  (AThread as TIdServerWSContext).OnCustomChannelExecute := Self.OnCustomChannelExecute;
  (AThread as TROIdServerWSContext).OnRemObjectsRequest  := Self.ProcessRemObjectsRequest;
end;

procedure TROIndyHTTPWebsocketServer.InternalServerDisConnect(
  AThread: TIdContext);
var
  transport: TROTransportContext;
begin
  transport := AThread.Data as TROTransportContext;
  if transport <> nil then
    FROTransportContexts.Remove(transport);
  //transport._Release;
  AThread.Data := nil;
end;

procedure TROIndyHTTPWebsocketServer.Loaded;
begin
  //do before inherited in case of designtime connection
  if Self.IndyServer.IOHandler = nil then
    IndyServer.IOHandler := TIdServerIOHandlerWebsocket.Create(Self);
  inherited;
end;

procedure TROIndyHTTPWebsocketServer.ProcessRemObjectsRequest(
  const AThread: TIdContext; const strmRequest: TMemoryStream; const strmResponse: TMemoryStream);
var
  cWSNR: array[0..High(C_ROWSNR)] of AnsiChar;
  msg: TROMessageDispatcher;
  iMsgNr: Integer;
  imsg: IROMessage;
  transport: TROTransportContext;
begin
  if strmRequest.Size < Length(C_ROWSNR) + SizeOf(iMsgNr) then Exit;
  //read messagenr from the end
  strmRequest.Position := strmRequest.Size - Length(C_ROWSNR) - SizeOf(iMsgNr);
  strmRequest.Read(cWSNR[0], Length(C_ROWSNR));
  if (cWSNR <> C_ROWSNR) then Exit;
  strmRequest.Read(iMsgNr, SizeOf(iMsgNr));
  strmRequest.Position := 0;
  //trunc extra data
  strmRequest.Size := strmRequest.Size - Length(C_ROWSNR) - SizeOf(iMsgNr);
  transport := AThread.Data as TROTransportContext;
  //no RO transport object already made?
  if transport = nil then
  begin
    //create IROTransport object
    transport := TROTransportContext.Create(Self, AThread as TIdServerWSContext);
    //(transport as IROTransport)._AddRef;
    FROTransportContexts.Add(transport);
    //attach RO transport to indy context
    AThread.Data := transport;
    //todo: enveloppes
    //read client GUID the first time (needed to be able to send RO events)
    msg := Self.Dispatchers.FindDispatcher(transport, strmRequest);
    if msg = nil then
      raise EROException.Create('No suiteable message dispatcher found!');
    imsg := (msg.MessageIntf as IROMessageCloneable).Clone;
    imsg.InitializeRead(transport);
    imsg.ReadFromStream(strmRequest);
    transport.ClientId := imsg.ClientID;
    imsg := nil;
    Assert(not IsEqualGUID(transport.ClientID, EmptyGUID));
  end;
  //EXECUTE FUNCTION
  Self.DispatchMessage(transport, strmRequest, strmResponse);
  //write number at end
  strmResponse.Position := strmResponse.Size;
  strmResponse.Write(C_ROWSNR, Length(C_ROWSNR));
  strmResponse.Write(iMsgNr, SizeOf(iMsgNr));
  strmResponse.Position := 0;
end;

{ TROTransport }

constructor TROTransportContext.Create(aROServer: TROIndyHTTPServer;
  aIdContext: TIdServerWSContext);
begin
  FROServer  := aROServer;
  FIdContext := aIdContext;
end;

procedure TROTransportContext.EventsRegistered(aSender: TObject; aClient: TGUID);
begin
  //
end;

procedure TROTransportContext.DispatchEvent(anEventDataItem: TROEventData;
  aSessionReference: TGUID; aSender: TObject);
var
  i: Integer;
  LContext: TIdContext;
  transport: TROTransportContext;
  l: TList;
  ws: TIdIOHandlerWebsocket;
  cWSNR: array[0..High(C_ROWSNR)] of AnsiChar;
begin
  l := FROServer.IndyServer.Contexts.LockList;
  try
    if l.Count <= 0 then Exit;

    anEventDataItem.Data.Position := anEventDataItem.Data.Size - Length(C_ROWSNR) - SizeOf(FEventCount);
    anEventDataItem.Data.Read(cWSNR[0], Length(cWSNR));
    //event number not written already?
    if cWSNR <> C_ROWSNR then
    begin
      //new event nr
      FEventCount   := -1 * InterlockedIncrement(FGlobalEventCount); //negative = event, positive is normal RO message
      //overflow? then start again from 0
      if FEventCount > 0 then
      begin
        InterlockedExchange(FGlobalEventCount, 0);
        FEventCount := -1 * InterlockedIncrement(FGlobalEventCount); //negative = event, positive is normal RO message
      end;
      Assert(FEventCount < 0);
      //write nr at end of message
      anEventDataItem.Data.Position := anEventDataItem.Data.Size;
      anEventDataItem.Data.Write(C_ROWSNR, Length(C_ROWSNR));
      anEventDataItem.Data.Write(FEventCount, SizeOf(FEventCount));
      anEventDataItem.Data.Position := 0;
    end;

    //search specific client
    for i := 0 to l.Count - 1 do
    begin
      LContext  := TIdContext(l.Items[i]);
      transport := LContext.Data as TROTransportContext;
      if transport = nil then Continue;
      if not IsEqualGUID(transport.ClientId, aSessionReference) then Continue;

      //direct write event data
      ws       := (LContext.Connection.IOHandler as TIdIOHandlerWebsocket);
      if not ws.IsWebsocket then Exit;
      ws.Lock;
      try
        try ws.Write(anEventDataItem.Data, wdtBinary) except {continue with other connections} end;
      finally
        ws.Unlock;
      end;
    end;
  finally
    anEventDataItem.RemoveRef;
    FROServer.IndyServer.Contexts.UnlockList;
  end;
end;

function TROTransportContext.GetClientAddress: string;
begin
  Result := FIdContext.Binding.PeerIP;
end;

function TROTransportContext.GetTransportObject: TObject;
begin
  Result := FROServer;
end;

{ TROHTTPMessageDispatchers_WebSocket }

function TROHTTPMessageDispatchers_WebSocket.GetDispatcherClass: TROMessageDispatcherClass;
begin
  result := TROHTTPDispatcher_Websocket;
end;

{ TROHTTPDispatcher_Websocket }

function TROHTTPDispatcher_Websocket.CanHandleMessage(
  const aTransport: IROTransport; aRequeststream: TStream): boolean;
var
  tcp: IROTCPTransport;
  buf: array [0..5] of AnsiChar;
begin
  if aRequeststream = nil then result := FALSE else // for preventing warning in FPC
  result := FALSE;

  if not Enabled or
     not Supports(aTransport, IROTCPTransport, tcp)
  then
    Exit;
  if (tcp as TROTransportContext).FIdContext.IOHandler.IsWebsocket then
  begin
    //we can handle all kind of messages, independent on the path, so check which kind of message we have
    Result := Self.Message.IsValidMessage((aRequeststream as TMemoryStream).Memory, aRequeststream.Size);

    //goes wrong with enveloppes!
    //TROMessage.Envelopes_ProcessIncoming
    if not Result and
       (aRequeststream.Size > 6) then
    begin
      aRequeststream.Read(buf,6);
      Result := (buf[0] = EnvelopeSignature[0]) and
                (buf[1] = EnvelopeSignature[1]) and
                (buf[2] = EnvelopeSignature[2]) and
                (buf[3] = EnvelopeSignature[3]) and
                (buf[4] = EnvelopeSignature[4]);
      aRequeststream.Position := 0;
    end;
  end
  else
    Result := inherited CanHandleMessage(aTransport, aRequeststream);
end;

end.
