unit IdWebsocketServer;

interface

uses
  IdServerWebsocketHandling, IdServerSocketIOHandling, IdServerWebsocketContext,
  IdHTTPServer, IdContext, IdCustomHTTPServer, Classes, IdIOHandlerWebsocket, IdGlobal, IdServerIOHandler;

type
  TWebsocketMessageText = procedure(const AContext: TIdServerWSContext; const aText: string)  of object;
  TWebsocketMessageBin  = procedure(const AContext: TIdServerWSContext; const aData: TStream) of object;

  TIdWebsocketServer = class(TIdHTTPServer)
  private
    FSocketIO: TIdServerSocketIOHandling_Ext;
    FOnMessageText: TWebsocketMessageText;
    FOnMessageBin: TWebsocketMessageBin;
    FWriteTimeout: Integer;
    FUseSSL: boolean;
    function GetSocketIO: TIdServerSocketIOHandling;
    procedure SetWriteTimeout(const Value: Integer);
    function  GetIOHandler: TIdServerIOHandler;
  protected
    procedure Startup; override;
    procedure DetermineSSLforPort(APort: TIdPort; var VUseSSL: Boolean);

    procedure DoCommandGet(AContext: TIdContext; ARequestInfo: TIdHTTPRequestInfo;
     AResponseInfo: TIdHTTPResponseInfo); override;
    procedure ContextCreated(AContext: TIdContext); override;
    procedure ContextDisconnected(AContext: TIdContext); override;

    procedure WebsocketChannelRequest(const AContext: TIdServerWSContext; aType: TWSDataType; const aStrmRequest, aStrmResponse: TMemoryStream);
  public
    procedure  AfterConstruction; override;
    destructor Destroy; override;

    procedure SendMessageToAll(const aBinStream: TStream);overload;
    procedure SendMessageToAll(const aText: string);overload;

    property OnMessageText: TWebsocketMessageText read FOnMessageText write FOnMessageText;
    property OnMessageBin : TWebsocketMessageBin  read FOnMessageBin  write FOnMessageBin;

    property IOHandler: TIdServerIOHandler read GetIOHandler write SetIOHandler;
    property SocketIO: TIdServerSocketIOHandling read GetSocketIO;
  published
    property WriteTimeout: Integer read FWriteTimeout write SetWriteTimeout default 2000;
    property UseSSL: boolean       read FUseSSL write FUseSSL;
  end;

implementation

uses
  IdServerIOHandlerWebsocket, IdStreamVCL, Windows, IdWinsock2, IdSSLOpenSSL, IdSSL, IdThread; //, idIOHandler, idssl;

{ TIdWebsocketServer }

procedure TIdWebsocketServer.AfterConstruction;
begin
  inherited;

  FSocketIO := TIdServerSocketIOHandling_Ext.Create;

  ContextClass := TIdServerWSContext;
  FWriteTimeout := 2 * 1000;  //2s
end;

procedure TIdWebsocketServer.ContextCreated(AContext: TIdContext);
begin
  inherited ContextCreated(AContext);
  (AContext as TIdServerWSContext).OnCustomChannelExecute := Self.WebsocketChannelRequest;

  //default 2s write timeout
  //http://msdn.microsoft.com/en-us/library/windows/desktop/ms740532(v=vs.85).aspx
  AContext.Connection.Socket.Binding.SetSockOpt(SOL_SOCKET, SO_SNDTIMEO, Self.WriteTimeout);
end;

procedure TIdWebsocketServer.ContextDisconnected(AContext: TIdContext);
begin
  FSocketIO.FreeConnection(AContext);
  inherited;
end;

destructor TIdWebsocketServer.Destroy;
begin
  inherited;
  FSocketIO.Free;
end;

procedure TIdWebsocketServer.DetermineSSLforPort(APort: TIdPort; var VUseSSL: Boolean);
//var
//  thread: TIdThreadWithTask;
//  ctx: TIdServerWSContext;
begin
  VUseSSL := IOHandler.InheritsFrom(TIdServerIOHandlerSSLBase);

  {$message warn 'todo: no ssl for localhost (testing, server IPC, etc)?'}
  (*
  //
  if TThread.CurrentThread is TIdThreadWithTask then
  begin
    thread := TThread.CurrentThread as TIdThreadWithTask;
    ctx    := thread.Task as TIdServerWSContext;
    //yarn   := thread.Task.Yarn as TIdYarnOfThread;

    if ctx.Binding.PeerIP = '127.0.0.1' then
      VUseSSL := false;
  end;
  *)
end;

procedure TIdWebsocketServer.DoCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
begin
  (AContext as TIdServerWSContext).OnCustomChannelExecute := Self.WebsocketChannelRequest;
  (AContext as TIdServerWSContext).SocketIO               := FSocketIO;

  if not TIdServerWebsocketHandling.ProcessServerCommandGet(AContext as TIdServerWSContext, ARequestInfo, AResponseInfo) then
    inherited DoCommandGet(AContext, ARequestInfo, AResponseInfo);
end;

function TIdWebsocketServer.GetIOHandler: TIdServerIOHandler;
begin
  Result := inherited IOHandler;

  if Result = nil then
  begin
    if UseSSL then
    begin
      Result := TIdServerIOHandlerWebsocketSSL.Create(Self);

      with Result as TIdServerIOHandlerWebsocketSSL do
      begin
        //note: custom certificate files must be set by user, e.g. in datamodule OnCreate:
        //FHttpServer := TIdWebsocketServer.Create;
        //FHttpServer.UseSSL := True;
        //with FHttpServer.IOHandler as TIdServerIOHandlerWebsocketSSL do
        //  SSLOptions.RootCertFile := 'root.cer';
        //  SSLOptions.CertFile := 'your_cert.cer';
        //  SSLOptions.KeyFile := 'key.pem';

        SSLOptions.Method := sslvSSLv23;
        SSLOptions.Mode   := sslmServer;

        OnQuerySSLPort := DetermineSSLforPort;
      end;
    end
    else
      Result := TIdServerIOHandlerWebsocket.Create(Self);

    inherited IOHandler := Result;
  end;
end;

function TIdWebsocketServer.GetSocketIO: TIdServerSocketIOHandling;
begin
  Result := FSocketIO;
end;

procedure TIdWebsocketServer.SendMessageToAll(const aText: string);
var
  l: TList;
  ctx: TIdServerWSContext;
  i: Integer;
begin
  l := Self.Contexts.LockList;
  try
    for i := 0 to l.Count - 1 do
    begin
      ctx := TIdServerWSContext(l.Items[i]);
      Assert(ctx is TIdServerWSContext);
      if ctx.WebsocketImpl.IsWebsocket and
         not ctx.IsSocketIO
      then
        ctx.IOHandler.Write(aText);
    end;
  finally
    Self.Contexts.UnlockList;
  end;
end;

procedure TIdWebsocketServer.SetWriteTimeout(const Value: Integer);
begin
  FWriteTimeout := Value;
end;

procedure TIdWebsocketServer.Startup;
begin
  inherited;
end;

procedure TIdWebsocketServer.WebsocketChannelRequest(
  const AContext: TIdServerWSContext; aType: TWSDataType; const aStrmRequest,
  aStrmResponse: TMemoryStream);
var s: string;
begin
  if aType = wdtText then
  begin
    with TStreamReader.Create(aStrmRequest) do
    begin
      s := ReadToEnd;
      Free;
    end;
    if Assigned(OnMessageText) then
      OnMessageText(AContext, s)
  end
  else if Assigned(OnMessageBin) then
      OnMessageBin(AContext, aStrmRequest)
end;

procedure TIdWebsocketServer.SendMessageToAll(const aBinStream: TStream);
var
  l: TList;
  ctx: TIdServerWSContext;
  i: Integer;
  bytes: TIdBytes;
begin
  l := Self.Contexts.LockList;
  try
    TIdStreamHelperVCL.ReadBytes(aBinStream, bytes);

    for i := 0 to l.Count - 1 do
    begin
      ctx := TIdServerWSContext(l.Items[i]);
      Assert(ctx is TIdServerWSContext);
      if ctx.WebsocketImpl.IsWebsocket and
         not ctx.IsSocketIO
      then
        ctx.IOHandler.Write(bytes);
    end;
  finally
    Self.Contexts.UnlockList;
  end;
end;

end.
