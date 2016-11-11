unit IdServerIOHandlerWebsocket;
interface
{$I wsdefines.pas}
uses
  Classes, SysUtils
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
    {$if CompilerVersion >= 31}   //XE10
    function GetIOHandlerSelf: TIdSSLIOHandlerSocketOpenSSL;
    {$else}
    function CreateOpenSSLSocket:TIdSSLIOHandlerSocketOpenSSL; override;
    {$endif}
    {$ENDIF}
  public
    function Accept(ASocket: TIdSocketHandle; AListenerThread: TIdThread;
      AYarn: TIdYarn): TIdIOHandler; override;
    function MakeClientIOHandler(ATheThread:TIdYarn): TIdIOHandler; override;
  end;

implementation

{ TIdServerIOHandlerStack_Websocket }

{$IFDEF WEBSOCKETSSL}
  {$if CompilerVersion >= 31}   //XE10
function TIdServerIOHandlerWebsocket.GetIOHandlerSelf:TIdSSLIOHandlerSocketOpenSSL;
begin
  Result := TIdIOHandlerWebsocket.Create(nil);
end;
  {$else}
function TIdServerIOHandlerWebsocket.CreateOpenSSLSocket:TIdSSLIOHandlerSocketOpenSSL;
begin
  Result := TIdIOHandlerWebsocket.Create(nil);
end;
  {$endif}
{$ENDIF}

function TIdServerIOHandlerWebsocket.Accept(ASocket: TIdSocketHandle;
  AListenerThread: TIdThread; AYarn: TIdYarn): TIdIOHandler;
{$IFDEF WEBSOCKETSSL}
var
  LIO: TIdIOHandlerWebsocket;
{$ENDIF}
begin
{$IFnDEF WEBSOCKETSSL}
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
