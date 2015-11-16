unit IdServerIOHandlerWebsocket;

interface

uses
  Classes,
  IdServerIOHandlerStack, IdIOHandlerStack, IdGlobal, IdIOHandler, IdYarn, IdThread, IdSocketHandle,
  IdIOHandlerWebsocket, IdSSLOpenSSL, sysutils;

type
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlerStack)
  protected
    procedure InitComponent; override;
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;

  TIdServerIOHandlerWebsocketSSL = class(TIdServerIOHandlersslOpenSSL)
  protected
    procedure InitComponent; override;
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;

implementation

{ TIdServerIOHandlerStack_Websocket }

function TIdServerIOHandlerWebsocket.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
var
  LIOHandler: TIdIOHandlerWebsocketPlain;
begin
  //Result := inherited Accept(ASocket, AListenerThread, AYarn);

  //using a custom scheduler, AYarn may be nil, so don't assert
  Assert(ASocket<>nil);
  Assert(AListenerThread<>nil);

  Result := nil;
  LIOHandler := TIdIOHandlerWebsocketPlain.Create(nil);
  try
    LIOHandler.Open;
    while not AListenerThread.Stopped do
    begin
      if ASocket.Select(250) then
      begin
        if LIOHandler.Binding.Accept(ASocket.Handle) then
begin
          LIOHandler.AfterAccept;
          Result := LIOHandler;
          LIOHandler := nil;
          Break;
        end;
      end;
    end;
  finally
    FreeAndNil(LIOHandler);
  end;

  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocketPlain).WebsocketImpl.IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocketPlain).UseNagle := False;
  end;
end;

procedure TIdServerIOHandlerWebsocket.InitComponent;
begin
  inherited InitComponent;
  //IOHandlerSocketClass := TIdIOHandlerWebsocket;
end;

function TIdServerIOHandlerWebsocket.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocketPlain).WebsocketImpl.IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocketPlain).UseNagle := False;
  end;
end;

{ TIdServerIOHandlerWebsocketSSL }

function TIdServerIOHandlerWebsocketSSL.Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
  AYarn: TIdYarn): TIdIOHandler;
var
  LIO: TIdIOHandlerWebsocketSSL;
begin
  Assert(ASocket<>nil);
  Assert(fSSLContext<>nil);
  LIO := TIdIOHandlerWebsocketSSL.Create(nil);
  try
    LIO.PassThrough := True;    //initial no ssl?
    //we need to pass the SSLOptions for the socket from the server
    LIO.SSLOptions  := SSLOptions;
    LIO.IsPeer      := True;    //shared SSLOptions + fSSLContext
    LIO.Open;
    if LIO.Binding.Accept(ASocket.Handle) then
    begin
      //LIO.ClearSSLOptions;
      LIO.SSLSocket  := TIdSSLSocket.Create(Self);
      LIO.SSLContext := fSSLContext;
    end
    else
    begin
      FreeAndNil(LIO);
    end;
  except
    LIO.Free;
    raise;
  end;
  Result := LIO;

  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocketSSL).WebsocketImpl.IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocketSSL).UseNagle := False;
  end;
end;

procedure TIdServerIOHandlerWebsocketSSL.InitComponent;
begin
  inherited InitComponent;
  //IOHandlerSocketClass := TIdIOHandlerWebsocket;
end;

function TIdServerIOHandlerWebsocketSSL.MakeClientIOHandler(ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocketSSL).WebsocketImpl.IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocketSSL).UseNagle := False;
  end;
end;

end.
