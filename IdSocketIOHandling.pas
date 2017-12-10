﻿unit IdSocketIOHandling;
interface
{$I wsdefines.pas}
uses
  windows, SyncObjs, SysUtils, StrUtils, Classes, Generics.Collections
  {$IFDEF SUPEROBJECT}
  , superobject
  {$ENDIF}
  , IdContext
  , IdException
  , IdHTTP
  //
  , IdServerBaseHandling
  , IdIOHandlerWebsocket, IdIIOHandlerWebsocket
  ;

type
  {$IFNDEF SUPEROBJECT}
  TSuperArray = String;
  {$ENDIF}

  TSocketIOContext = class;
  TSocketIOCallbackObj = class;
  TIdBaseSocketIOHandling = class;
  TIdSocketIOHandling = class;

  ISocketIOContext = interface;
  ISocketIOCallback = interface;

  TSocketIOMsg      = reference to procedure(const ASocket: ISocketIOContext; const aText: string; const aCallback: ISocketIOCallback);
  {$IFDEF SUPEROBJECT}
  TSocketIOMsgJSON  = reference to procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback);
  {$ELSE}
  TSocketIOMsgJSON  = reference to procedure(const ASocket: ISocketIOContext; const aJSON:string; const aCallback: ISocketIOCallback);
  {$ENDIF}
  TSocketIOEvent    = reference to procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallback: ISocketIOCallback);
  TSocketIONotify   = reference to procedure(const ASocket: ISocketIOContext);
  TSocketIOError    = reference to procedure(const ASocket: ISocketIOContext; const aErrorClass, aErrorMessage: string);
  TSocketIOEventError = reference to procedure(const ASocket: ISocketIOContext; const aCallback: ISocketIOCallback; E: Exception);

  TSocketIONotifyList = class(TList<TSocketIONotify>);
  TSocketIOEventList  = class(TList<TSocketIOEvent>);

  EIdSocketIoUnhandledMessage = class(EIdSilentException);

  ISocketIOContext = interface
    ['{ACCAC678-054C-4D75-8BAD-5922F55623AB}']
    function  GetCustomData: TObject;
    function  GetOwnsCustomData: Boolean;
    procedure SetCustomData(const Value: TObject);
    procedure SetOwnsCustomData(const Value: Boolean);

    property CustomData: TObject     read GetCustomData    write SetCustomData;
    property OwnsCustomData: Boolean read GetOwnsCustomData write SetOwnsCustomData;

    function ResourceName: string;
    function PeerIP: string;
    function PeerPort: Integer;

    procedure Lock;
    procedure UnLock;

    function IsDisconnected: Boolean;

    {$IFDEF SUPEROBJECT}
    procedure EmitEvent(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    procedure SendJSON(const aJSON: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);
    {$ENDIF}
    procedure EmitEvent(const aEventName: string; const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    procedure Send(const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);
  end;

  TSocketIOContext = class(TInterfacedObject,ISocketIOContext)
  private
    FLock: TCriticalSection;
    FPingSend: Boolean;
    FConnectSend: Boolean;
    FGUID: string;
    FPeerIP: string;
    FCustomData: TObject;
    FOwnsCustomData: Boolean;
    procedure SetContext(const Value: TIdContext);
    procedure SetConnectSend(const Value: Boolean);
    procedure SetPingSend(const Value: Boolean);
    function GetCustomData: TObject;
    function GetOwnsCustomData: Boolean;
    procedure SetCustomData(const Value: TObject);
    procedure SetOwnsCustomData(const Value: Boolean);
  protected
    FHandling: TIdBaseSocketIOHandling;
    FContext: TIdContext;
    FIOHandler: IIOHandlerWebsocket;
    FClient: TIdHTTP;
    FEvent: TEvent;
    FQueue: TList<string>;
    FPendingMessages: TList<Int64>;
    procedure QueueData(const aData: string);
    procedure ServerContextDestroy(AContext: TIdContext);
  public
    constructor Create();overload;
    constructor Create(aClient: TIdHTTP);overload;
    procedure   AfterConstruction; override;
    destructor  Destroy; override;

    procedure Lock;
    procedure UnLock;
    function  WaitForQueue(aTimeout_ms: Integer): string;

    function ResourceName: string;
    function PeerIP: string;
    function PeerPort: Integer;
    function IsDisconnected: Boolean;

    property GUID: string         read FGUID;
    property Context: TIdContext  read FContext write SetContext;
    property PingSend: Boolean    read FPingSend write SetPingSend;
    property ConnectSend: Boolean read FConnectSend write SetConnectSend;

    property CustomData: TObject     read GetCustomData    write SetCustomData;
    property OwnsCustomData: Boolean read GetOwnsCustomData write SetOwnsCustomData;

    procedure EmitEvent(const aEventName: string; const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    procedure Send(const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);
    {$IFDEF SUPEROBJECT}
    //todo: OnEvent per socket
    //todo: store session info per connection (see Socket.IO Set + Get -> Storing data associated to a client)
    //todo: namespace using "Of"
    procedure EmitEvent(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    procedure SendJSON(const aJSON: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);
    {$ENDIF}
  end;

  ISocketIOCallback = interface
    ['{BCC31817-7FD8-4CF6-B68B-0F9BAA80DF90}']
    procedure SendResponse(const aResponse: string);
    function  IsResponseSend: Boolean;
  end;

  TSocketIOCallbackObj = class(TInterfacedObject,
                               ISocketIOCallback)
  protected
    FHandling: TIdBaseSocketIOHandling;
    FSocket: ISocketIOContext;
    FMsgNr: Integer;
    {ISocketIOCallback}
    procedure SendResponse(const aResponse: string);
    function  IsResponseSend: Boolean;
  public
    constructor Create(aHandling: TIdBaseSocketIOHandling; aSocket: ISocketIOContext; aMsgNr: Integer);
  end;

  TSocketIOPromise = class
  protected
    Done, Success: Boolean;
    Error: Exception;
    {$IFDEF SUPEROBJECT}
    Data : ISuperObject;
    {$ENDIF}
    Event: TEvent;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;
  end;

  ESocketIOException  = class(Exception);
  ESocketIOTimeout    = class(ESocketIOException);
  ESocketIODisconnect = class(ESocketIOException);

  TIdBaseSocketIOHandling = class(TIdServerBaseHandling)
  protected
    FLock: TCriticalSection;
    FConnections: TObjectDictionary<TIdContext,ISocketIOContext>;
    FConnectionsGUID: TObjectDictionary<string,ISocketIOContext>;

    FOnConnectionList,
    FOnDisconnectList: TSocketIONotifyList;
    FOnEventList: TObjectDictionary<string,TSocketIOEventList>;
    FOnSocketIOMsg: TSocketIOMsg;
    {$IFDEF SUPEROBJECT}
    FOnSocketIOJson: TSocketIOMsgJSON;
    {$ENDIF}

    procedure ProcessEvent(const AContext: ISocketIOContext; const aText: string; aMsgNr: Integer; aHasCallback: Boolean);
  private
    FOnEventError: TSocketIOEventError;
  protected
    type
      TSocketIOCallback    = procedure(const aData: string) of object;
      TSocketIOCallbackRef = reference to procedure(const aData: string);
    var
      FSocketIOMsgNr: Integer;
      FSocketIOEventCallback: TDictionary<Integer,TSocketIOCallback>;
      FSocketIOEventCallbackRef: TDictionary<Integer,TSocketIOCallbackRef>;
      //FSocketIOEventPromises: TDictionary<Integer,TSocketIOPromise>;
      FSocketIOErrorRef: TDictionary<Integer,TSocketIOError>;

    function  WriteConnect(const ASocket: ISocketIOContext): string; overload;
    procedure WriteDisConnect(const ASocket: ISocketIOContext);overload;
    procedure WritePing(const ASocket: ISocketIOContext);overload;
    //
    function  WriteConnect(const AContext: TIdContext): string; overload;
    procedure WriteDisConnect(const AContext: TIdContext);overload;
    procedure WritePing(const AContext: TIdContext);overload;

    procedure WriteSocketIOMsg(const ASocket: ISocketIOContext; const aRoom, aData: string; aCallback: TSocketIOCallbackRef = nil; const aOnError: TSocketIOError = nil);
    procedure WriteSocketIOJSON(const ASocket: ISocketIOContext; const aRoom, aJSON: string; aCallback: TSocketIOCallbackRef = nil; const aOnError: TSocketIOError = nil);
    procedure WriteSocketIOEvent(const ASocket: ISocketIOContext; const aRoom, aEventName, aJSONArray: string; aCallback: TSocketIOCallback; const aOnError: TSocketIOError);
    procedure WriteSocketIOEventRef(const ASocket: ISocketIOContext; const aRoom, aEventName, aJSONArray: string; aCallback: TSocketIOCallbackRef; const aOnError: TSocketIOError);
    {$IFDEF SUPEROBJECT}
    function  WriteSocketIOEventSync(const ASocket: ISocketIOContext; const aRoom, aEventName, aJSONArray: string; aMaxwait_ms: Cardinal = INFINITE): ISuperObject;
    {$ENDIF}
    procedure WriteSocketIOResult(const ASocket: ISocketIOContext; aRequestMsgNr: Integer; const aRoom, aData: string);

    procedure ProcessSocketIO_XHR(const aGUID: string; const aStrmRequest, aStrmResponse: TStream);

    procedure ProcessSocketIORequest(const ASocket: ISocketIOContext; const strmRequest: TMemoryStream);overload;
    procedure ProcessSocketIORequest(const ASocket: ISocketIOContext; const aData: string);overload;
    procedure ProcessSocketIORequest(const AContext: TIdContext; const strmRequest: TMemoryStream);overload;

    procedure ProcessHeatbeatRequest(const ASocket: ISocketIOContext; const aText: string);virtual;
    procedure ProcessCloseChannel(const ASocket: ISocketIOContext; const aChannel: string);virtual;
    function  WriteString(const ASocket: ISocketIOContext; const aText: string): string; virtual;
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure Lock;
    procedure UnLock;
    function  ConnectionCount: Integer;

    function  GetSocketIOContext(const AContext: TIdContext): ISocketIOContext;

//    procedure  EmitEventToAll(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil);
    function  NewConnection(const AContext: TIdContext): ISocketIOContext;overload;
    function  NewConnection(const aGUID, aPeerIP: string): ISocketIOContext;overload;
    procedure FreeConnection(const AContext: TIdContext);overload;
    procedure FreeConnection(const ASocket: ISocketIOContext);overload;

    property  OnSocketIOMsg  : TSocketIOMsg read FOnSocketIOMsg  write FOnSocketIOMsg;
    {$IFDEF SUPEROBJECT}
    property  OnSocketIOJson : TSocketIOMsgJSON read FOnSocketIOJson write FOnSocketIOJson;
    {$ENDIF}

    procedure OnEvent     (const aEventName: string; const aCallback: TSocketIOEvent);
    procedure OnConnection(const aCallback: TSocketIONotify);
    procedure OnDisconnect(const aCallback: TSocketIONotify);
    property  OnEventError: TSocketIOEventError read FOnEventError write FOnEventError;

    procedure EnumerateSockets(const aEachSocketCallback: TSocketIONotify);
  end;

  TIdSocketIOHandling = class(TIdBaseSocketIOHandling)
  public
    procedure Send(const aMessage: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);
    procedure Emit(const aEventName: string; const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    {$IFDEF SUPEROBJECT}
    procedure Emit(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    function  EmitSync(const aEventName: string; const aData: ISuperObject; aMaxwait_ms: Cardinal = INFINITE): ISuperobject;
    //procedure Emit(const aEventName: string; const aData: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    {$ENDIF}
  end;

{$IFNDEF SUPEROBJECT}
function SO(const S:string):string; inline;
{$ENDIF}

implementation

uses
  IdServerWebsocketContext,  IdHTTPWebsocketClient;

{$IFNDEF SUPEROBJECT}
function SO(const S:string):string; inline;
begin
  Result := S;
end;
{$ENDIF}

procedure TIdBaseSocketIOHandling.AfterConstruction;
begin
  inherited;
  FLock := TCriticalSection.Create;

  FConnections      := TObjectDictionary<TIdContext,ISocketIOContext>.Create([]);
  FConnectionsGUID  := TObjectDictionary<string,ISocketIOContext>.Create([]);

  FOnConnectionList := TSocketIONotifyList.Create;
  FOnDisconnectList := TSocketIONotifyList.Create;
  FOnEventList      := TObjectDictionary<string,TSocketIOEventList>.Create([doOwnsValues]);

  FSocketIOEventCallback     := TDictionary<Integer,TSocketIOCallback>.Create;
  FSocketIOEventCallbackRef  := TDictionary<Integer,TSocketIOCallbackRef>.Create;
  FSocketIOErrorRef          := TDictionary<Integer,TSocketIOError>.Create;
  //FSocketIOEventPromises     := TDictionary<Integer,TSocketIOPromise>.Create;
end;

function TIdBaseSocketIOHandling.ConnectionCount: Integer;
var
  context: ISocketIOContext;
begin
  Lock;
  try
    Result := 0;

    //note: is single connection?
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;
      Inc(Result);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;
      Inc(Result);
    end;
  finally
    UnLock;
  end;
end;

destructor TIdBaseSocketIOHandling.Destroy;
var squid: string;
    idcontext: TIdContext;
begin
  Lock;
  FSocketIOEventCallback.Free;
  FSocketIOEventCallbackRef.Free;
  FSocketIOErrorRef.Free;
  //FSocketIOEventPromises.Free;

  FOnEventList.Free;
  FOnConnectionList.Free;
  FOnDisconnectList.Free;

  while FConnections.Count > 0 do
    for idcontext in FConnections.Keys do
    begin
      //FConnections.Items[idcontext]._Release;
      FConnections.ExtractPair(idcontext);
    end;
  while FConnectionsGUID.Count > 0 do
    for squid in FConnectionsGUID.Keys do
    begin
      //FConnectionsGUID.Items[squid]._Release;
      FConnectionsGUID.ExtractPair(squid);
    end;
  FConnections.Free;
  FConnections := nil;
  FConnectionsGUID.Free;

  UnLock;
  FLock.Free;
  inherited;
end;

procedure TIdBaseSocketIOHandling.EnumerateSockets(
  const aEachSocketCallback: TSocketIONotify);
var socket: ISocketIOContext;
begin
  Assert(Assigned(aEachSocketCallback));
  Lock;
  try
    for socket in FConnections.Values do
    try
      aEachSocketCallback(socket);
    except
      //continue: e.g. connnection closed etc
    end;
    for socket in FConnectionsGUID.Values do
    try
      aEachSocketCallback(socket);
    except
      //continue: e.g. connnection closed etc
    end;
  finally
    Unlock;
  end;
end;

procedure TIdBaseSocketIOHandling.FreeConnection(
  const ASocket: ISocketIOContext);
var squid: string;
    idcontext: TIdContext;
    errorref: TSocketIOError;
    i: Integer;
begin
  if ASocket = nil then Exit;
  Lock;
  try
    with TSocketIOContext(ASocket) do
    begin
      Context    := nil;
      FIOHandler := nil;
      FClient    := nil;
      FHandling  := nil;
      FGUID      := '';
      FPeerIP    := '';
    end;

    for idcontext in FConnections.Keys do
    begin
      if FConnections.Items[idcontext] = ASocket then
      begin
        FConnections.ExtractPair(idcontext);
        //ASocket._Release;
      end;
    end;
    for squid in FConnectionsGUID.Keys do
    begin
      if FConnectionsGUID.Items[squid] = ASocket then
      begin
        FConnectionsGUID.ExtractPair(squid);
        //ASocket._Release; //use reference count? otherwise AV when used in TThread.Queue
      end;
    end;

    //pending callbacks? then exceute error messages
    for i in TSocketIOContext(ASocket).FPendingMessages do
    begin
      FSocketIOEventCallback.Remove(i);
      FSocketIOEventCallbackRef.Remove(i);
      if FSocketIOErrorRef.TryGetValue(i, errorref) then
      begin
        FSocketIOErrorRef.Remove(i);
        try
          errorref(ASocket, ESocketIODisconnect.ClassName, 'Connection disconnected');
        except
        end;
      end;
    end;
  finally
    Unlock;
  end;
end;

function TIdBaseSocketIOHandling.GetSocketIOContext(const AContext: TIdContext): ISocketIOContext;
var
  socket: ISocketIOContext;
begin
  Result := nil;
  Lock;
  try
    if FConnections.TryGetValue(AContext, socket) then
      Exit(socket);
  finally
    UnLock;
  end;
end;

procedure TIdBaseSocketIOHandling.FreeConnection(const AContext: TIdContext);
var
  socket: ISocketIOContext;
begin
  Lock;
  try
    if FConnections.TryGetValue(AContext, socket) then
      FreeConnection(socket);
  finally
    UnLock;
  end;
end;

procedure TIdBaseSocketIOHandling.Lock;
begin
//  Assert(FConnections <> nil);
//  System.TMonitor.Enter(Self);
  FLock.Enter;
end;

function TIdBaseSocketIOHandling.NewConnection(
  const AGUID, aPeerIP: string): ISocketIOContext;
var
  socket: TSocketIOContext;
begin
  Lock;
  try
    if not FConnectionsGUID.TryGetValue(AGUID, Result) then
    begin
      socket := TSocketIOContext.Create;
      FConnectionsGUID.Add(AGUID, socket);
    end
    else
      socket := TSocketIOContext(Result);

    //socket.Context      := AContext;
    socket.FGUID        := AGUID;
    if aPeerIP <> '' then
      socket.FPeerIP    := aPeerIP;
    socket.FHandling    := Self;
    socket.FConnectSend := False;
    socket.FPingSend    := False;
    Result := socket;
  finally
    UnLock;
  end;
end;

function TIdBaseSocketIOHandling.NewConnection(const AContext: TIdContext): ISocketIOContext;
var
  socket: TSocketIOContext;
begin
  Lock;
  try
    if not FConnections.TryGetValue(AContext, Result) then
    begin
      socket := TSocketIOContext.Create;
      FConnections.Add(AContext, socket);
    end
    else
      socket := TSocketIOContext(Result);

    socket.Context      := AContext;
    socket.FHandling    := Self;
    socket.FConnectSend := False;
    socket.FPingSend    := False;
    Result := socket;
  finally
    UnLock;
  end;
end;

procedure TIdBaseSocketIOHandling.OnConnection(const aCallback: TSocketIONotify);
var context: ISocketIOContext;
begin
  FOnConnectionList.Add(aCallback);

  Lock;
  try
    for context in FConnections.Values do
      aCallback(context);
    for context in FConnectionsGUID.Values do
      aCallback(context);
  finally
    UnLock;
  end;
end;

procedure TIdBaseSocketIOHandling.OnDisconnect(const aCallback: TSocketIONotify);
begin
  FOnDisconnectList.Add(aCallback);
end;

procedure TIdBaseSocketIOHandling.OnEvent(const aEventName: string;  const aCallback: TSocketIOEvent);
var list: TSocketIOEventList;
begin
  if not FOnEventList.TryGetValue(aEventName, list) then
  begin
    list := TSocketIOEventList.Create;
    FOnEventList.Add(aEventName, list);
  end;
  list.Add(aCallback);
end;

procedure TIdBaseSocketIOHandling.ProcessCloseChannel(
  const ASocket: ISocketIOContext; const aChannel: string);
begin
  if aChannel <> '' then
    //todo: close channel
  else if (TSocketIOContext(ASocket).FContext <> nil) then
    TSocketIOContext(ASocket).FContext.Connection.Disconnect;
end;

procedure TIdBaseSocketIOHandling.ProcessEvent(const AContext: ISocketIOContext; const aText: string; aMsgNr: Integer;aHasCallback: Boolean);
var
  name: string;
  {$IFNDEF SUPEROBJECT}
  args: string;
  {$ELSE}
  args: TSuperArray;
  json: ISuperObject;
  //  socket: TSocketIOContext;
  {$ENDIF}
  list: TSocketIOEventList;
  event: TSocketIOEvent;
  callback: ISocketIOCallback;

  {$IFNDEF SUPEROBJECT}
  function _GetJsonMember(const aText:string; const iName:string):string;
  var xs,xe,ctn:Integer;
  begin
    // Based on json formated content
    Result := '';
    xs := Pos('"'+iName+'"',aText);
    if xs=0 then Exit;
    xs := PosEx(':',aText,xs);
    if xs=0 then Exit;
    //
    inc(xs);
    while (xs<=length(aText)) and (aText[xs] in [' ',#13,#10,#8,#9]) do inc(xs);
    if xs>=length(aText) then Exit;
    //
    if aText[xs]='[' then
     begin
       xe := xs+1; ctn := 1;
       while (xe<=length(aText)) do
        begin
          if aText[xe]='[' then inc(ctn);
          if aText[xe]=']' then dec(ctn);
          if ctn=0 then break;
          inc(xe);
        end;
       if ctn=0 then
        Result := Copy(aText,xs,xe-xs+1);
     end
     else
    if aText[xs]='{' then
     begin
       xe := xs+1; ctn := 1;
       while (xe<=length(aText)) do
        begin
          if aText[xe]='{' then inc(ctn);
          if aText[xe]='}' then dec(ctn);
          if ctn=0 then break;
          inc(xe);
        end;
       if ctn=0 then
        Result := Copy(aText,xs,xe-xs+1);
     end
     else
    if aText[xs]='"' then
     begin
       xe := PosEx('"',aText,xs+1);
       if xe=0 then Exit;
       Result := Copy(aText,xs+1,xe-xs-1);
     end;
  end;
  {$ENDIF}

begin
  //'5:' [message id ('+')] ':' [message endpoint] ':' [json encoded event]
  //5::/chat:{"name":"my other event","args":[{"my":"data"}]}
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  {$IFNDEF SUPEROBJECT}
   name := _GetJsonMember(aText,'name');  //"my other event
   args := _GetJsonMember(aText,'args');  //[{"my":"data"}]
  {$ELSE}
  json := SO(aText);
  //  args := nil;
  try
    name := json.S['name'];  //"my other event
    args := json.A['args'];  //[{"my":"data"}]
  {$ENDIF}

    if FOnEventList.TryGetValue(name, list) then
    begin
      if list.Count = 0 then
        raise EIdSocketIoUnhandledMessage.Create(aText);

//      socket   := FConnections.Items[AContext];
      if aHasCallback then
        callback := TSocketIOCallbackObj.Create(Self, AContext, aMsgNr)
      else
        callback := nil;
      try
        for event in list do
        try
          event(AContext, args, callback);
        except on E:Exception do
          if Assigned(OnEventError) then
            OnEventError(AContext, callback, e)
          else
            if callback <> nil then
              {$IFNDEF SUPEROBJECT}
              callback.SendResponse('Error');
              {$ELSE}
              callback.SendResponse( SO(['Error', SO(['msg', e.message])]).AsJSon );
              {$ENDIF}
        end;
      finally
        callback := nil;
      end;
    end
    else
      raise EIdSocketIoUnhandledMessage.Create(aText);

  {$IFDEF SUPEROBJECT}
  finally
//args.Free;
  json := nil;
  end;
  {$ENDIF}
end;

procedure TIdBaseSocketIOHandling.ProcessHeatbeatRequest(const ASocket: ISocketIOContext; const aText: string);
begin
  with TSocketIOContext(ASocket) do
  begin
    if PingSend then
      PingSend := False   //reset, client responded with 2:: heartbeat too
    else
    begin
      PingSend := True;  //stop infinite ping response loops
      WriteString(ASocket, aText);   //write same connect back, e.g. 2::
    end;
  end;
end;

procedure TIdBaseSocketIOHandling.ProcessSocketIORequest(
  const ASocket: ISocketIOContext; const strmRequest: TMemoryStream);

  function __ReadToEnd: string;
  var
    utf8: TBytes;
    ilength: Integer;
  begin
    Result := '';
    ilength := strmRequest.Size - strmRequest.Position;
    if ilength <= 0 then
      Exit;
    SetLength(utf8, ilength);
    strmRequest.Read(utf8[0], ilength);
    Result := TEncoding.UTF8.GetString(utf8);
  end;

var str: string;
begin
  str := __ReadToEnd;
  ProcessSocketIORequest(ASocket, str);
end;

procedure TIdBaseSocketIOHandling.ProcessSocketIORequest(const AContext: TIdContext;
  const strmRequest: TMemoryStream);
var
  socket: ISocketIOContext;
begin
  if not FConnections.TryGetValue(AContext, socket) then
  begin
    socket := NewConnection(AContext);
  end;
  ProcessSocketIORequest(socket, strmRequest);
end;

procedure TIdBaseSocketIOHandling.ProcessSocketIO_XHR(const aGUID: string; // const AContext: TIdContext;
  const aStrmRequest, aStrmResponse: TStream);
var
  socket: ISocketIOContext;
  sdata: string;
  i, ilength: Integer;
  bytes, singlemsg: TBytes;
begin
  if not FConnectionsGUID.TryGetValue(aGUID, socket) or
     socket.IsDisconnected
  then
    socket := NewConnection(aGUID, '');

  if not TSocketIOContext(socket).FConnectSend then
    WriteConnect(socket);

  if (aStrmRequest <> nil) and
     (aStrmRequest.Size > 0) then
  begin
    aStrmRequest.Position := 0;
    SetLength(bytes, aStrmRequest.Size);
    aStrmRequest.Read(bytes[0], aStrmRequest.Size);

    if (Length(bytes) > 3) and
       (bytes[0] = 239) and (bytes[1] = 191) and (bytes[2] = 189) then
    begin
      //io.parser.encodePayload(msgs)
      //'\ufffd' + packet.length + '\ufffd'
      //'�17�3:::singlemessage�52�5:4+::{"name":"registerScanner","args":["scanner1"]}'
      while bytes <> nil do
      begin
        i := 3;
        //search second '\ufffd'
        while not ( (bytes[i+0] = 239) and (bytes[i+1] = 191) and (bytes[i+2] = 189) ) do
        begin
          Inc(i);
          if i+2 > High(bytes) then Exit;  //wrong data
        end;
        //get data between
        ilength := StrToInt( TEncoding.UTF8.GetString(bytes, 3, i-3) );  //17

        singlemsg := Copy(bytes, i+3, ilength);
        bytes     := Copy(bytes, i+3 + ilength, Length(bytes));
        sdata     := TEncoding.UTF8.GetString(singlemsg);                //3:::singlemessage
        try
          ProcessSocketIORequest(socket, sdata);
        except
          //next
        end;
      end;
    end
    else
    begin
      sdata := TEncoding.UTF8.GetString(bytes);
      ProcessSocketIORequest(socket, sdata);
    end;
  end;

  //e.g. POST, no GET?
  if aStrmResponse = nil then Exit;  

  //wait till some response data to be send (long polling)
  sdata := TSocketIOContext(socket).WaitForQueue(5 * 1000);
  if sdata = '' then
  begin
    //no data? then send ping
    WritePing(socket);
    sdata := TSocketIOContext(socket).WaitForQueue(0);
  end;
  //send response back
  if sdata <> '' then
  begin
    {$WARN SYMBOL_PLATFORM OFF}
//    if DebugHook <> 0 then
//      Windows.OutputDebugString(PChar('Send: ' + sdata));

    bytes := TEncoding.UTF8.GetBytes(sdata);
    aStrmResponse.Write(bytes[0], Length(bytes));
  end;
end;

procedure TIdBaseSocketIOHandling.UnLock;
begin
  //System.TMonitor.Exit(Self);
  FLock.Leave;
end;

procedure TIdBaseSocketIOHandling.ProcessSocketIORequest(
  const ASocket: ISocketIOContext; const aData: string);

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
  bCallback: Boolean;
//  socket: TSocketIOContext;
  callback: TSocketIOCallback;
  callbackref: TSocketIOCallbackRef;
  callbackobj: ISocketIOCallback;
  errorref: TSocketIOError;
  {$IFDEF SUPEROBJECT}
  error: ISuperObject;
  {$ENDIF}
  socket: TSocketIOContext;
begin
  if ASocket = nil then Exit;
  socket := ASocket as TSocketIOContext;

  if not FConnections.ContainsValue(socket) and
     not FConnectionsGUID.ContainsValue(socket) then
  begin
    Lock;
    try
      //ASocket._AddRef;
      FConnections.Add(nil, socket);  //clients do not have a TIdContext?
    finally
      UnLock;
    end;
  end;

  str := aData;
  if str = '' then Exit;
//  if DebugHook <> 0 then
//    Windows.OutputDebugString(PChar('Received: ' + str));
  while str[1] = #0 do
    Delete(str, 1, 1);

  //5:1+:/chat:test
  smsg      := __GetSocketIOPart(str, 1);
  imsg      := 0;
  bCallback := False;
  if smsg <> '' then                                       // 1+
  begin
    imsg    := StrToIntDef(ReplaceStr(smsg,'+',''), 0);    // 1
    bCallback := (Pos('+', smsg) > 1);  //trailing +, e.g.    1+
  end;
  schannel  := __GetSocketIOPart(str, 2);                  // /chat
  sdata     := __GetSocketIOPart(str, 3);                  // test

  //(0) Disconnect
  if StartsStr('0:', str) then
  begin
    schannel := __GetSocketIOPart(str, 2);
    ProcessCloseChannel(socket, schannel);
  end
  //(1) Connect
  //'1::' [path] [query]
  else if StartsStr('1:', str) then
  begin
    //todo: add channel/room to authorized channel/room list
    if not socket.ConnectSend then
      WriteString(socket, str);     //write same connect back, e.g. 1::/chat
  end
  //(2) Heartbeat
  else if StartsStr('2:', str) then
  begin
    //todo: timer to disconnect client if no ping within time
    ProcessHeatbeatRequest(socket, str);
  end
  //(3) Message (https://github.com/LearnBoost/socket.io-spec#3-message)
  //'3:' [message id ('+')] ':' [message endpoint] ':' [data]
  //3::/chat:hi
  else if StartsStr('3:', str) then
  begin
    if Assigned(OnSocketIOMsg) then
    begin
      if bCallback then
      begin
        callbackobj := TSocketIOCallbackObj.Create(Self, socket, imsg);
        try
          try
            OnSocketIOMsg(socket, sdata, callbackobj); //, imsg, bCallback);
          except
            on E:Exception do
            begin
              {$IFDEF SUPEROBJECT}
              if not callbackobj.IsResponseSend then
                callbackobj.SendResponse( SO(['Error', SO(['Type', e.ClassName, 'Message', e.Message])]).AsJSon );
              {$ELSE}
              //TODO
              {$ENDIF}
            end;
          end;
        finally
          callbackobj := nil;
        end
      end
      else
        OnSocketIOMsg(ASocket, sdata, nil);
    end
    else
      raise EIdSocketIoUnhandledMessage.Create(str);
  end
  //(4) JSON Message
  //'4:' [message id ('+')] ':' [message endpoint] ':' [json]
  //4:1::{"a":"b"}
  else if StartsStr('4:', str) then
  begin
    {$IFDEF SUPEROBJECT}
    if Assigned(OnSocketIOJson) then
    begin
      if bCallback then
      begin
        callbackobj := TSocketIOCallbackObj.Create(Self, socket, imsg);
        try
          try
            OnSocketIOJson(socket, SO(sdata), callbackobj); //, imsg, bCallback);
          except
            on E:Exception do
            begin
              if not callbackobj.IsResponseSend then
                callbackobj.SendResponse( SO(['Error', SO(['Type', e.ClassName, 'Message', e.Message])]).AsJSon );
            end;
          end;
        finally
          callbackobj := nil;
        end
      end
      else
        OnSocketIOJson(ASocket, SO(sdata), nil); //, imsg, bCallback);
    end
    else
    {$ENDIF}
      raise EIdSocketIoUnhandledMessage.Create(str);
  end
  //(5) Event
  //'5:' [message id ('+')] ':' [message endpoint] ':' [json encoded event]
  //5::/chat:{"name":"my other event","args":[{"my":"data"}]}
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  else if StartsStr('5:', str) then
  begin
    //if Assigned(OnSocketIOEvent) then
    //  OnSocketIOEvent(AContext, sdata, imsg, bCallback);
    try
      ProcessEvent(socket, sdata, imsg, bCallback);
    except
      on e:exception do
        //
    end
  end
  //(6) ACK
  //6::/news:1+["callback"]
  //6:::1+["Response"]
  else if StartsStr('6:', str) then
  begin
    smsg  := Copy(sdata, 1, Pos('+', sData)-1);
    imsg  := StrToIntDef(smsg, 0);
    sData := Copy(sdata, Pos('+', sData)+1, Length(sData));

    TSocketIOContext(ASocket).FPendingMessages.Remove(imsg);
    if FSocketIOErrorRef.TryGetValue(imsg, errorref) then
    begin
      FSocketIOErrorRef.Remove(imsg);
      //'[{"Error":{"Message":"Operation aborted","Type":"EAbort"}}]'
      {$IFDEF SUPEROBJECT}
      if ContainsText(sdata, '{"Error":') then
      begin
        error := SO(sdata);
        if error.IsType(stArray) then
          error := error.O['0'];
        error := error.O['Error'];
        if error.S['Message'] <> '' then
          errorref(ASocket, error.S['Type'], error.S['Message'])
        else
          errorref(ASocket, 'Unknown', sdata);

        FSocketIOEventCallback.Remove(imsg);
        FSocketIOEventCallbackRef.Remove(imsg);
        Exit;
      end;
      {$ENDIF}
    end;

    if FSocketIOEventCallback.TryGetValue(imsg, callback) then
    begin
      FSocketIOEventCallback.Remove(imsg);
      if Assigned(callback) then
        callback(sdata);
    end
    else if FSocketIOEventCallbackRef.TryGetValue(imsg, callbackref) then
    begin
      FSocketIOEventCallbackRef.Remove(imsg);
      if Assigned(callbackref) then
        callbackref(sdata);
    end
    else ;
      //raise EIdSocketIoUnhandledMessage.Create(str);
  end
  //(7) Error
  else if StartsStr('7:', str) then
    raise EIdSocketIoUnhandledMessage.Create(str)
  //(8) Noop
  else if StartsStr('8:', str) then
  begin
    //nothing
  end
  else
    raise Exception.CreateFmt('Unsupported data: "%s"', [str]);
end;

function TIdBaseSocketIOHandling.WriteConnect(
  const ASocket: ISocketIOContext): string;
var
  notify: TSocketIONotify;
begin
  Lock;
  try
    if not FConnections.ContainsValue(ASocket) and
       not FConnectionsGUID.ContainsValue(ASocket) then
    begin
      //ASocket._AddRef;
      FConnections.Add(nil, ASocket);  //clients do not have a TIdContext?
    end;

    if not TSocketIOContext(ASocket).ConnectSend then
    begin
      TSocketIOContext(ASocket).ConnectSend := True;
      Result := WriteString(ASocket, '1::');
    end;
  finally
    UnLock;
  end;

  for notify in FOnConnectionList do
    notify(ASocket);
end;

procedure TIdBaseSocketIOHandling.WriteDisConnect(
  const ASocket: ISocketIOContext);
var
  notify: TSocketIONotify;
begin
  if ASocket = nil then Exit;
  for notify in FOnDisconnectList do
    notify(ASocket);

  Lock;
  try
    if not ASocket.IsDisconnected then
    try
      WriteString(ASocket, '0::');
    except
    end;
    FreeConnection(ASocket);
  finally
    UnLock;
  end;
end;

procedure TIdBaseSocketIOHandling.WritePing(
  const ASocket: ISocketIOContext);
begin
  TSocketIOContext(ASocket).PingSend := True;
  WriteString(ASocket, '2::')   //heartbeat: https://github.com/LearnBoost/socket.io-spec
end;

procedure TIdBaseSocketIOHandling.WriteSocketIOEvent(const ASocket: ISocketIOContext; const aRoom, aEventName,
  aJSONArray: string; aCallback: TSocketIOCallback; const aOnError: TSocketIOError);
var
  sresult: string;
  inr: Integer;
begin
  //see TROIndyHTTPWebsocketServer.ProcessSocketIORequest too
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  inr := InterlockedIncrement(FSocketIOMsgNr);
  if not Assigned(aCallback) then
    sresult := Format('5:%d:%s:{"name":"%s", "args":%s}',
                      [inr, aRoom, aEventName, aJSONArray])
  else
  begin
    //if FSocketIOEventCallback = nil then
    //  FSocketIOEventCallback := TDictionary<Integer,TSocketIOCallback>.Create;
    sresult := Format('5:%d+:%s:{"name":"%s", "args":%s}',
                      [inr, aRoom, aEventName, aJSONArray]);
    FSocketIOEventCallback.Add(inr, aCallback);
    TSocketIOContext(ASocket).FPendingMessages.Add(inr);

    if Assigned(aOnError) then
      FSocketIOErrorRef.Add(inr, aOnError);
  end;
  WriteString(ASocket, sresult);
end;

procedure TIdBaseSocketIOHandling.WriteSocketIOEventRef(const ASocket: ISocketIOContext;
  const aRoom, aEventName, aJSONArray: string; aCallback: TSocketIOCallbackRef; const aOnError: TSocketIOError);
var
  sresult: string;
  inr: Integer;
begin
  //see TROIndyHTTPWebsocketServer.ProcessSocketIORequest too
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  inr := InterlockedIncrement(FSocketIOMsgNr);
  if not Assigned(aCallback) then
    sresult := Format('5:%d:%s:{"name":"%s", "args":%s}',
                      [inr, aRoom, aEventName, aJSONArray])
  else
  begin
    //if FSocketIOEventCallbackRef = nil then
    //  FSocketIOEventCallbackRef := TDictionary<Integer,TSocketIOCallbackRef>.Create;
    sresult := Format('5:%d+:%s:{"name":"%s", "args":%s}',
                      [inr, aRoom, aEventName, aJSONArray]);
    FSocketIOEventCallbackRef.Add(inr, aCallback);
    TSocketIOContext(ASocket).FPendingMessages.Add(inr);

    if Assigned(aOnError) then
      FSocketIOErrorRef.Add(inr, aOnError);
  end;
  WriteString(ASocket, sresult);
end;

{$IFDEF SUPEROBJECT}
function TIdBaseSocketIOHandling.WriteSocketIOEventSync(const ASocket: ISocketIOContext; const aRoom, aEventName,
  aJSONArray: string; aMaxwait_ms: Cardinal = INFINITE): ISuperObject;
var
  sresult: string;
  inr: Integer;
  promise: TSocketIOPromise;
begin
  Result := nil;
  if (ASocket = nil) or (ASocket.IsDisconnected) then
    raise ESocketIOException.CreateFmt('Socket is not connected, cannot send "%s" request', [aEventName]);

  //see TROIndyHTTPWebsocketServer.ProcessSocketIORequest too
  //5:1+:/chat:{"name":"GetLocations","args":[""]}
  inr := InterlockedIncrement(FSocketIOMsgNr);

//  if FSocketIOEventPromises = nil then
//    FSocketIOEventPromises := TDictionary<Integer,TSocketIOPromise>.Create;
  promise := TSocketIOPromise.Create;
//  FSocketIOEventPromises.Add(inr, promise);

  sresult := Format('5:%d+:%s:{"name":"%s", "args":%s}',
                    [inr, aRoom, aEventName, aJSONArray]);
  Lock;
  try
    FSocketIOEventCallbackRef.Add(inr,
      procedure(const aData: string)
      begin
        promise.Success := True;
        promise.Error   := nil;
        promise.Data    := SO(aData);
        promise.Done    := True;
        promise.Event.SetEvent;
      end);
    FSocketIOErrorRef.Add(inr,
      procedure(const ASocket: ISocketIOContext; const aErrorClass, aErrorMessage: string)
      begin
        promise.Success := False;
        promise.Error   := ESocketIOException.Create(aErrorClass + ': ' + aErrorMessage);
        promise.Data    := nil;
        promise.Done    := True;
        promise.Event.SetEvent;
      end);
    TSocketIOContext(ASocket).FPendingMessages.Add(inr);
  finally
    Unlock;
  end;

  try
    try
      if ASocket.IsDisconnected then
        raise ESocketIOException.CreateFmt('Socket is disconnected, cannot send "%s" request', [aEventName])
      else
        WriteString(ASocket, sresult);

      //wait for callback
      if promise.Event.WaitFor(aMaxwait_ms) = wrSignaled then
        Assert(promise.Done)
      else
        //timeout
        raise ESocketIOTimeout.CreateFmt('No response received for "%s" request', [aEventName]);
    except
      Lock;
      try
        FSocketIOEventCallbackRef.Remove(inr);
        FSocketIOErrorRef.Remove(inr);
        TSocketIOContext(ASocket).FPendingMessages.Remove(inr);
      finally
        UnLock;
      end;
      raise;
    end;

    Result := promise.Data;
    if promise.Error <> nil then
    begin
      Assert(not promise.Success);
      raise promise.Error;
    end
    else
      Assert(promise.Success);
  finally
    promise.Free;
  end;
end;
{$ENDIF}
procedure TIdBaseSocketIOHandling.WriteSocketIOJSON(const ASocket: ISocketIOContext;
  const aRoom, aJSON: string; aCallback: TSocketIOCallbackRef = nil; const aOnError: TSocketIOError = nil);
var
  sresult: string;
  inr: Integer;
begin
  //see TROIndyHTTPWebsocketServer.ProcessSocketIORequest too
  //4:1::{"a":"b"}
  inr := InterlockedIncrement(FSocketIOMsgNr);

  if not Assigned(aCallback) then
    sresult := Format('4:%d:%s:%s', [inr, aRoom, aJSON])
  else
  begin
    //if FSocketIOEventCallbackRef = nil then
    //  FSocketIOEventCallbackRef := TDictionary<Integer,TSocketIOCallbackRef>.Create;
    sresult := Format('4:%d+:%s:%s',
                      [inr, aRoom, aJSON]);
    FSocketIOEventCallbackRef.Add(inr, aCallback);
    TSocketIOContext(ASocket).FPendingMessages.Add(inr);

    if Assigned(aOnError) then
      FSocketIOErrorRef.Add(inr, aOnError);
  end;

  WriteString(ASocket, sresult);
end;

procedure TIdBaseSocketIOHandling.WriteSocketIOMsg(const ASocket: ISocketIOContext;
  const aRoom, aData: string; aCallback: TSocketIOCallbackRef = nil; const aOnError: TSocketIOError = nil);
var
  sresult: string;
  inr: Integer;
begin
  //see TROIndyHTTPWebsocketServer.ProcessSocketIORequest too
  //3::/chat:hi
  inr := InterlockedIncrement(FSocketIOMsgNr);

  if not Assigned(aCallback) then
    sresult := Format('3:%d:%s:%s', [inr, aRoom, aData])
  else
  begin
    //if FSocketIOEventCallbackRef = nil then
    //  FSocketIOEventCallbackRef := TDictionary<Integer,TSocketIOCallbackRef>.Create;
    sresult := Format('3:%d+:%s:%s',
                      [inr, aRoom, aData]);
    FSocketIOEventCallbackRef.Add(inr, aCallback);
    TSocketIOContext(ASocket).FPendingMessages.Add(inr);

    if Assigned(aOnError) then
      FSocketIOErrorRef.Add(inr, aOnError);
  end;

  WriteString(ASocket, sresult);
end;

procedure TIdBaseSocketIOHandling.WriteSocketIOResult(const ASocket: ISocketIOContext;
  aRequestMsgNr: Integer; const aRoom, aData: string);
var
  sresult: string;
begin
  //6::/news:2+["callback"]
  sresult := Format('6::%s:%d+[%s]', [aRoom, aRequestMsgNr, aData]);
  WriteString(ASocket, sresult);
end;

function TIdBaseSocketIOHandling.WriteString(const ASocket: ISocketIOContext;
  const aText: string): string;
begin
  if ASocket = nil then Exit;

  ASocket.Lock;
  try
    with TSocketIOContext(ASocket) do
    begin
      if FIOHandler = nil then
      begin
        if FContext <> nil then
          FIOHandler := (FContext as TIdServerWSContext).IOHandler;
      end;

      if (FIOHandler <> nil) then
      begin
        //Assert(ASocket.FIOHandler.IsWebsocket);
  //      if DebugHook <> 0 then
  //        Windows.OutputDebugString(PChar('Send: ' + aText));
        FIOHandler.Write(aText);
      end
      else if GUID <> '' then
      begin
        QueueData(aText);
        Result := aText;    //for xhr-polling the data must be send using responseinfo instead of direct write!
      end;
      //else   //disconnected
      //  Assert(False, 'disconnected');
    end;
  finally
    ASocket.UnLock;
  end;
end;

{ TSocketIOCallbackObj }

constructor TSocketIOCallbackObj.Create(aHandling: TIdBaseSocketIOHandling;
  aSocket: ISocketIOContext; aMsgNr: Integer);
begin
  FHandling := aHandling;
  FSocket   := aSocket;
  FMsgNr    := aMsgNr;
  inherited Create();
end;

function TSocketIOCallbackObj.IsResponseSend: Boolean;
begin
  Result := (FMsgNr < 0);
end;

procedure TSocketIOCallbackObj.SendResponse(const aResponse: string);
begin
  FHandling.WriteSocketIOResult(FSocket, FMsgNr, '', aResponse);
  FMsgNr := -1;
end;

{ TSocketIOContext }

procedure TSocketIOContext.AfterConstruction;
begin
  inherited;
  FLock  := TCriticalSection.Create;
  FQueue := TList<string>.Create;
  FPendingMessages := TList<Int64>.Create;
end;

constructor TSocketIOContext.Create(aClient: TIdHTTP);
begin
  FClient := aClient;
  if aClient is TIdHTTPWebsocketClient then
  begin
    FHandling := (aClient as TIdHTTPWebsocketClient).SocketIO;
  end;
  FIOHandler := (aClient as TIdHTTPWebsocketClient).IOHandler;
end;

destructor TSocketIOContext.Destroy;
begin
  Lock;
  FEvent.Free;
  FreeAndNil(FQueue);
  UnLock;
  FLock.Free;
  if OwnsCustomData then
    FCustomData.Free;
  FPendingMessages.Free;
  inherited;
end;

procedure TSocketIOContext.EmitEvent(const aEventName, aData: string; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
begin
  Assert(FHandling <> nil);

  if not Assigned(aCallback) then
    FHandling.WriteSocketIOEvent(Self, '', aEventName, '[' + aData + ']', nil, nil)
  else
  begin
    FHandling.WriteSocketIOEventRef(Self, '', aEventName, '[' + aData + ']',
      procedure(const aData: string)
      begin
        aCallback(Self, SO(aData), nil);
      end, aOnError);
  end;
end;

{$IFDEF SUPEROBJECT}
procedure TSocketIOContext.EmitEvent(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
begin
  if aData <> nil then
    EmitEvent(aEventName, aData.AsJSon, aCallback, aOnError)
  else
    EmitEvent(aEventName, '', aCallback, aOnError);
end;
{$ENDIF}

function TSocketIOContext.GetCustomData: TObject;
begin
  Result := FCustomData;
end;

function TSocketIOContext.GetOwnsCustomData: Boolean;
begin
  Result := FOwnsCustomData;
end;

function TSocketIOContext.IsDisconnected: Boolean;
begin
  Result := (FClient = nil) and (FContext = nil) and (FGUID = '');
end;

procedure TSocketIOContext.Lock;
begin
//  Assert(FQueue <> nil);
//  System.TMonitor.Enter(Self);
  FLock.Enter;
end;

constructor TSocketIOContext.Create;
begin
  //
end;

function TSocketIOContext.PeerIP: string;
begin
  Result := FPeerIP;
  if FContext is TIdServerWSContext then
    Result := (FContext as TIdServerWSContext).Binding.PeerIP
  else if FIOHandler <> nil then
    Result := FIOHandler.Binding.PeerIP;
end;

function TSocketIOContext.PeerPort: Integer;
begin
  Result := 0;
  if FContext is TIdServerWSContext then
    Result := (FContext as TIdServerWSContext).Binding.PeerPort
  else if FIOHandler <> nil then
    Result := FIOHandler.Binding.PeerPort
end;

procedure TSocketIOContext.QueueData(const aData: string);
begin
  if FEvent = nil then
    FEvent := TEvent.Create;

  FQueue.Add(aData);

  //max 1000 items in queue (otherwise infinite mem leak possible?)
  while FQueue.Count > 1000 do
    FQueue.Delete(0);

  FEvent.SetEvent;
end;

function TSocketIOContext.ResourceName: string;
begin
  if FContext is TIdServerWSContext then
    Result := (FContext as TIdServerWSContext).ResourceName
  else if FClient <> nil then
    Result := (FClient as TIdHTTPWebsocketClient).WSResourceName
end;

procedure TSocketIOContext.Send(const aData: string; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
begin
  if not Assigned(aCallback) then
    FHandling.WriteSocketIOMsg(Self, '', aData)
  else
  begin
    FHandling.WriteSocketIOMsg(Self, '', aData,
      procedure(const aData: string)
      begin
        aCallback(Self, SO(aData), nil);
      end, aOnError);
  end;
end;

{$IFDEF SUPEROBJECT}
procedure TSocketIOContext.SendJSON(const aJSON: ISuperObject;
  const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
begin
  if not Assigned(aCallback) then
    FHandling.WriteSocketIOJSON(Self, '', aJSON.AsJSon())
  else
  begin
    FHandling.WriteSocketIOMsg(Self, '', aJSON.AsJSon(),
      procedure(const aData: string)
      begin
        aCallback(Self, SO(aData), nil);
      end, aOnError);
  end;
end;
{$ENDIF}
procedure TSocketIOContext.ServerContextDestroy(AContext: TIdContext);
begin
  Self.Context    := nil;
  Self.FIOHandler := nil;

  if FHandling <> nil then
    Self.FHandling.FreeConnection(AContext);
end;

procedure TSocketIOContext.SetConnectSend(const Value: Boolean);
begin
  FConnectSend := Value;
end;

procedure TSocketIOContext.SetContext(const Value: TIdContext);
begin
  if (Value <> FContext) and (Value = nil) and
     (FContext is TIdServerWSContext) then
    (FContext as TIdServerWSContext).OnDestroy := nil;

  FContext := Value;

  if FContext is TIdServerWSContext then
    (FContext as TIdServerWSContext).OnDestroy := Self.ServerContextDestroy;
end;

procedure TSocketIOContext.SetCustomData(const Value: TObject);
begin
  FCustomData := Value;
end;

procedure TSocketIOContext.SetOwnsCustomData(const Value: Boolean);
begin
  FOwnsCustomData := Value;
end;

procedure TSocketIOContext.SetPingSend(const Value: Boolean);
begin
  FPingSend := Value;
end;

procedure TSocketIOContext.UnLock;
begin
  //System.TMonitor.Exit(Self);
  FLock.Leave;
end;

function TSocketIOContext.WaitForQueue(aTimeout_ms: Integer): string;
begin
  if (FEvent = nil) or (FQueue = nil) then
  begin
    Lock;
    try
      if FEvent = nil then
        FEvent := TEvent.Create;
      if FQueue = nil then
        FQueue := TList<string>.Create;
    finally
      UnLock;
    end;
  end;

  if (FQueue.Count > 0) or
     (FEvent.WaitFor(aTimeout_ms) = wrSignaled) then
  begin
    Lock;
    try
      FEvent.ResetEvent;
      if (FQueue.Count > 0) then
      begin
        Result := FQueue.First;
        FQueue.Delete(0);
      end;
    finally
      UnLock;
    end;
  end;
end;

function TIdBaseSocketIOHandling.WriteConnect(const AContext: TIdContext): string;
var
  socket: ISocketIOContext;
begin
  //if not FConnections.TryGetValue(AContext, socket) then
  socket := NewConnection(AContext);
  Result := WriteConnect(socket);
end;

procedure TIdBaseSocketIOHandling.WriteDisConnect(const AContext: TIdContext);
var
  socket: ISocketIOContext;
begin
  if not FConnections.TryGetValue(AContext, socket) then
    socket := NewConnection(AContext);
  WriteDisConnect(socket);
end;

procedure TIdBaseSocketIOHandling.WritePing(const AContext: TIdContext);
var
  socket: ISocketIOContext;
begin
  if not FConnections.TryGetValue(AContext, socket) then
    socket := NewConnection(AContext);
  WritePing(socket);
end;

{ TIdSocketIOHandling }

{$IFDEF SUPEROBJECT}
procedure TIdSocketIOHandling.Emit(const aEventName: string;
  const aData: ISuperObject; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var
  context: ISocketIOContext;
  jsonarray: string;
  isendcount: Integer;
begin
  if aData <> nil then
  begin
    if aData.IsType(stArray) then
      jsonarray := aData.AsString
    else if aData.IsType(stString) then
      jsonarray := '["' + aData.AsString + '"]'
    else
      jsonarray := '[' + aData.AsString + ']';
  end;

  Lock;
  try
    isendcount := 0;

    //note: client has single connection?
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, jsonarray, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, jsonarray,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, jsonarray, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, jsonarray,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;

    if isendcount = 0 then
      raise EIdSocketIoUnhandledMessage.Create('Cannot emit: no socket.io connections!');
  finally
    UnLock;
  end;
end;

function TIdSocketIOHandling.EmitSync(const aEventName: string; const aData: ISuperObject; aMaxwait_ms: Cardinal = INFINITE): ISuperobject;
var
  firstcontext, context: ISocketIOContext;
  jsonarray: string;
  isendcount: Integer;
begin
  if aData <> nil then
  begin
    if aData.IsType(stArray) then
      jsonarray := aData.AsString
    else if aData.IsType(stString) then
      jsonarray := '["' + aData.AsString + '"]'
    else
      jsonarray := '[' + aData.AsString + ']';
  end;

  Lock;
  try
    isendcount := 0;
    //note: client has single connection?
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;
      firstcontext := context;
      Inc(isendcount);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;
      firstcontext := context;
      Inc(isendcount);
    end;

    //todo: use multiple promises?
    if isendcount > 1 then
      raise EIdSocketIoUnhandledMessage.Create('Cannot emit synchronized to more than one connection!');
  finally
    UnLock;
  end;

  Result := WriteSocketIOEventSync(firstcontext, ''{no room}, aEventName, jsonarray, aMaxwait_ms);
end;
{$ENDIF}

procedure TIdSocketIOHandling.Emit(const aEventName: string;
  const aData: string; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var context: ISocketIOContext; isendcount: Integer;
begin
  Lock;
  try
    isendcount := 0;

    //note: client has single connection?
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, aData, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, aData,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, aData, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, aData,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;

    if isendcount = 0 then
      raise EIdSocketIoUnhandledMessage.Create('Cannot emit: no socket.io connections!');
  finally
    UnLock;
  end;
end;

procedure TIdSocketIOHandling.Send(const aMessage: string;
  const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var
  context: ISocketIOContext;
  isendcount: Integer;
begin
  Lock;
  try
    isendcount := 0;

    //note: is single connection?
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOMsg(context, ''{no room}, aMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, aMessage,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOMsg(context, ''{no room}, aMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, aMessage,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(isendcount);
    end;

    if isendcount = 0 then
      raise EIdSocketIoUnhandledMessage.Create('Cannot send: no socket.io connections!');
  finally
    UnLock;
  end;
end;


{ TSocketIOPromise }

procedure TSocketIOPromise.AfterConstruction;
begin
  inherited;
  Event := TEvent.Create();
end;

destructor TSocketIOPromise.Destroy;
begin
  Event.Free;
  inherited;
end;

end.
