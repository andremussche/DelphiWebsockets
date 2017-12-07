unit IdServerWebsocketContext;
interface
{$I wsdefines.pas}
uses
  Classes, strUtils
  , IdContext
  , IdCustomTCPServer
  , IdCustomHTTPServer
  //
  , IdIOHandlerWebsocket
  , IdServerBaseHandling
  , IdServerSocketIOHandling, IdWebSocketTypes
  ;

type
  TIdServerWSContext = class;

  TWebSocketUpgradeEvent = procedure(const AContext: TIdServerWSContext; ARequestInfo: TIdHTTPRequestInfo; var Accept:boolean) of object;
  TWebsocketChannelRequest = procedure(const AContext: TIdServerWSContext; var aType:TWSDataType; const strmRequest, strmResponse: TMemoryStream) of object;

  TIdServerWSContext = class(TIdServerContext)
  private
    FWebSocketKey: string;
    FWebSocketVersion: Integer;
    FPath: string;
    FWebSocketProtocol: string;
    FResourceName: string;
    FOrigin: string;
    FQuery: string;
    FHost: string;
    FWebSocketExtensions: string;
    FCookie: string;
    //FSocketIOPingSend: Boolean;
    fOnWebSocketUpgrade: TWebSocketUpgradeEvent;
    FOnCustomChannelExecute: TWebsocketChannelRequest;
    FSocketIO: TIdServerSocketIOHandling;
    FOnDestroy: TIdContextEvent;
  public
    function IOHandler: TIdIOHandlerWebsocket;
  public
    function IsSocketIO: Boolean;
    property SocketIO: TIdServerSocketIOHandling read FSocketIO write FSocketIO;
    //property SocketIO: TIdServerBaseHandling read FSocketIO write FSocketIO;
    property OnDestroy: TIdContextEvent read FOnDestroy write FOnDestroy;
  public
    destructor Destroy; override;

    property Path        : string read FPath write FPath;
    property Query       : string read FQuery write FQuery;
    property ResourceName: string read FResourceName write FResourceName;
    property Host        : string read FHost write FHost;
    property Origin      : string read FOrigin write FOrigin;
    property Cookie      : string read FCookie write FCookie;

    property WebSocketKey       : string  read FWebSocketKey write FWebSocketKey;
    property WebSocketProtocol  : string  read FWebSocketProtocol write FWebSocketProtocol;
    property WebSocketVersion   : Integer read FWebSocketVersion write FWebSocketVersion;
    property WebSocketExtensions: string  read FWebSocketExtensions write FWebSocketExtensions;
  public
    property OnWebSocketUpgrade: TWebsocketUpgradeEvent read FOnWebSocketUpgrade write FOnWebSocketUpgrade;
    property OnCustomChannelExecute: TWebsocketChannelRequest read FOnCustomChannelExecute write FOnCustomChannelExecute;
  end;

implementation

{ TIdServerWSContext }

destructor TIdServerWSContext.Destroy;
begin
  if Assigned(OnDestroy) then
    OnDestroy(Self);
  inherited;
end;

function TIdServerWSContext.IOHandler: TIdIOHandlerWebsocket;
begin
  Result := Self.Connection.IOHandler as TIdIOHandlerWebsocket;
end;

function TIdServerWSContext.IsSocketIO: Boolean;
begin
  //FDocument	= '/socket.io/1/websocket/13412152'
  Result := StartsText('/socket.io/1/websocket/', FPath);
end;

end.
