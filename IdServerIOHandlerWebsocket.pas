unit IdServerIOHandlerWebsocket;

interface

uses
  Classes,
  IdServerIOHandlerStack, IdIOHandlerStack, IdGlobal, IdIOHandler, IdYarn, IdThread, IdSocketHandle,
  IdIOHandlerWebsocket;

type
  TIdServerIOHandlerWebsocket = class(TIdServerIOHandlerStack)
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
begin
  Result := inherited Accept(ASocket, AListenerThread, AYarn);
  if Result <> nil then
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
end;

procedure TIdServerIOHandlerWebsocket.InitComponent;
begin
  inherited InitComponent;
  IOHandlerSocketClass := TIdIOHandlerWebsocket;
end;

function TIdServerIOHandlerWebsocket.MakeClientIOHandler(
  ATheThread: TIdYarn): TIdIOHandler;
begin
  Result := inherited MakeClientIOHandler(ATheThread);
  if Result <> nil then
    (Result as TIdIOHandlerWebsocket).IsServerSide := True; //server must not mask, only client
end;

end.
