unit IdServerIOHandlerWebsocket;

interface

uses
  Classes,
  IdServerIOHandlerStack, IdIOHandlerStack, IdGlobal, IdIOHandler, IdYarn, IdThread, IdSocketHandle,
{$IFNDEF WS_NO_SSL}
  IdSSLOpenSSL, 
  sysutils,
{$ENDIF}
  IdIOHandlerWebsocket;

type
{$IFNDEF WS_NO_SSL}
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlerStack)
{$ELSE}
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlersslOpenSSL)
{$ENDIF}
  protected
    procedure InitComponent; override;
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
      AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;

implementation

{ TIdServerIOHandlerStack_Websocket }

function TIdServerIOHandlerWebsocket.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
{$IFNDEF WS_NO_SSL}
var
  LIO: TIdIOHandlerWebsocketSSL;
{$ENDIF}
begin
{$IFDEF WS_NO_SSL}
  Result := inherited Accept(ASocket, AListenerThread, AYarn);
{$ELSE}
  Assert(ASocket<>nil);
  Assert(fSSLContext<>nil);
  LIO := TIdIOHandlerWebsocket.Create(nil);
  try
    LIO.PassThrough := True;
    LIO.Open;
    if LIO.Binding.Accept(ASocket.Handle) then
    begin
      //we need to pass the SSLOptions for the socket from the server
      LIO.ClearSSLOptions;
      LIO.IsPeer := True;
      LIO.SSLOptions := SSLOptions;
      LIO.SSLSocket := TIdSSLSocket.Create(Self);
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
{$ENDIF}
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocket).UseNagle := False;
  end;
end;

procedure TIdServerIOHandlerWebsocket.InitComponent;
begin
  inherited InitComponent;
//TODO: Check if this is necessary for SSL
  IOHandlerSocketClass := TIdIOHandlerWebsocket;
end;

function TIdServerIOHandlerWebsocket.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocket).UseNagle := False;
  end;
end;

end.
