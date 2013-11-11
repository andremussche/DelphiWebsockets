unit uROIdServerWebsocketHandling;

interface

uses
  IdServerWebsocketHandling, IdServerWebsocketContext,
  IdContext,
  Classes, IdIOHandlerWebsocket;

type
  TOnRemObjectsRequest = procedure(const AThread: TIdContext; const strmRequest: TMemoryStream; const strmResponse: TMemoryStream) of object;

  TROIdServerWSContext = class(TIdServerWSContext)
  private
    FOnRemObjectsRequest: TOnRemObjectsRequest;
  public
    property OnRemObjectsRequest: TOnRemObjectsRequest read FOnRemObjectsRequest write FOnRemObjectsRequest;
  end;

  TROIdServerWebsocketHandling = class(TIdServerWebsocketHandling)
  protected
    class procedure DoWSExecute(AThread: TIdContext; aSocketIOHandler: TIdServerSocketIOHandling_Ext); override;
    class procedure HandleWSMessage(AContext: TIdServerWSContext; aType: TWSDataType; aRequestStrm, aResponseStrm: TMemoryStream;
                                    aSocketIOHandler: TIdServerSocketIOHandling_Ext);override;
  end;

const
  C_ROWSNR: array[0..5] of AnsiChar = 'ROWSNR';

implementation

uses
  uROHTTPWebsocketServer, uROClientIntf;

{ TROIdServerWebsocketHandling }

class procedure TROIdServerWebsocketHandling.DoWSExecute(AThread: TIdContext;
  aSocketIOHandler: TIdServerSocketIOHandling_Ext);
var
  transport: TROTransportContext;
begin
  try
    inherited DoWSExecute(AThread, aSocketIOHandler);
  finally
    transport := AThread.Data as TROTransportContext;
    //detach RO transport
    if transport <> nil then
      (transport as IROTransport)._Release;
  end;
end;

class procedure TROIdServerWebsocketHandling.HandleWSMessage(
  AContext: TIdServerWSContext; aType: TWSDataType; aRequestStrm, aResponseStrm: TMemoryStream;
  aSocketIOHandler: TIdServerSocketIOHandling_Ext);
var
  cWSNR: array[0..High(C_ROWSNR)] of AnsiChar;
  rocontext: TROIdServerWSContext;
begin
  if aRequestStrm.Size > Length(C_ROWSNR) + SizeOf(Integer) then
  begin
    aRequestStrm.Position := aRequestStrm.Size - Length(C_ROWSNR) - SizeOf(Integer);
    aRequestStrm.Read(cWSNR[0], Length(cWSNR));
  end
  else
    cWSNR := '';

  if cWSNR = C_ROWSNR then
  begin
    rocontext := AContext as TROIdServerWSContext;
    if Assigned(rocontext.OnRemObjectsRequest) then
      rocontext.OnRemObjectsRequest(AContext, aRequestStrm, aResponseStrm);
  end
//  else if SameText(context.path, '/RemObjects') then
//  begin
//    ProcessRemObjectsRequest(AThread, strmRequest, strmResponse, transport);
//  end
  else
    inherited HandleWSMessage(AContext, aType, aRequestStrm, aResponseStrm, aSocketIOHandler);
end;

end.
