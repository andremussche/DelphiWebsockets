unit IdServerIOHandlerWebsocketSSL;

interface
uses
  IdServerIOHandlerWebsocket, IdSSLOpenSSL, IdSocketHandle, IdThread, IdYarn,
  IdIOHandler;

type
  TIdServerIOHandlerWebsocketSSL = class(TIdServerIOHandlerSSLOpenSSL)
  end;

implementation

end.
