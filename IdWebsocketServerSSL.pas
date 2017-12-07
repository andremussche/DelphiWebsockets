unit IdWebsocketServerSSL;

interface

uses
  IdWebsocketServer;

type
  TIdWebSocketServerSSL = class(TIdWebsocketServer)
  public
    procedure AfterConstruction; override;
  end;

implementation

{ TIdWebSocketServerSSL }

uses IdServerIOHandlerWebsocket, IdServerIOHandlerWebsocketSSL;

procedure TIdWebSocketServerSSL.AfterConstruction;
begin
  inherited;
  if IOHandler is TIdServerIOHandlerWebsocket then
    begin
      IOHandler.Free;
      IOHandler := TIdServerIOHandlerWebsocketSSL.Create(Self);
    end;
end;

end.
