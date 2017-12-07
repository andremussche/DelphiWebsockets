unit IdServerIOHandlerWebsocket;
interface
{$I wsdefines.pas}
uses
  Classes
  , IdServerIOHandlerStack
  , IdIOHandlerStack
  , IdGlobal
  , IdIOHandler
  , IdYarn
  , IdThread
  , IdSocketHandle
  //
  , IdIOHandlerWebsocket
  {$IFDEF WEBSOCKETSSL}
  , IdSSLOpenSSL
  {$ENDIF}
  ;

type
  {$IFDEF WEBSOCKETSSL}
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlerSSLOpenSSL)
  {$ELSE}
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlerStack)
  {$ENDIF}
  protected
    procedure InitComponent; override;
    {$IFDEF WEBSOCKETSSL}
    // function CreateOpenSSLSocket: TIdSSLIOHandlerSocketOpenSSL; override;
    {$ENDIF}
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
      AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;

implementation

{ TIdServerIOHandlerStack_Websocket }

{$IFDEF WEBSOCKETSSL}
//function TIdServerIOHandlerWebsocket.CreateOpenSSLSocket: TIdSSLIOHandlerSocketOpenSSL;
//begin
//  Result := TIdIOHandlerWebsocket.Create(nil);
//end;
{$ENDIF}

function TIdServerIOHandlerWebsocket.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
begin
  Result := inherited Accept(ASocket, AListenerThread, AYarn);
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocket).UseNagle := False;
  end;
end;

procedure TIdServerIOHandlerWebsocket.InitComponent;
begin
  inherited InitComponent;
  {$IFNDEF WEBSOCKETSSL}
  IOHandlerSocketClass := TIdIOHandlerWebsocket;
  {$ENDIF}
end;

function TIdServerIOHandlerWebsocket.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  {$IFNDEF WEBSOCKETSSL}
  if Result <> nil then
  begin
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
    (Result as TIdIOHandlerWebsocket).UseNagle := False;
  end;
  {$ENDIF}
end;

end.
