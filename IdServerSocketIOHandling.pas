unit IdServerSocketIOHandling;

interface

uses
  IdContext, IdCustomTCPServer,
  //IdServerWebsocketContext,
  Classes, Generics.Collections,
  superobject, IdException, IdServerBaseHandling, IdSocketIOHandling;

type
  TIdServerSocketIOHandling = class(TIdBaseSocketIOHandling)
  protected
    procedure ProcessHeatbeatRequest(const AContext: TSocketIOContext; const aText: string); override;
  public
    function  SendToAll(const aMessage: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil): Integer;
    procedure SendTo   (const aContext: TIdServerContext; const aMessage: string; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);

    function  EmitEventToAll(const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil): Integer;overload;
    function  EmitEventToAll(const aEventName: string; const aData: string      ; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil): Integer;overload;
    procedure EmitEventTo   (const aContext: TSocketIOContext;
                             const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
    procedure EmitEventTo   (const aContext: TIdServerContext;
                             const aEventName: string; const aData: ISuperObject; const aCallback: TSocketIOMsgJSON = nil; const aOnError: TSocketIOError = nil);overload;
  end;

implementation

uses
  SysUtils, StrUtils;

{ TIdServerSocketIOHandling }

procedure TIdServerSocketIOHandling.EmitEventTo(
  const aContext: TSocketIOContext; const aEventName: string;
  const aData: ISuperObject; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var
  jsonarray: string;
begin
  if aContext.IsDisconnected then
    raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

  if aData.IsType(stArray) then
    jsonarray := aData.AsString
  else if aData.IsType(stString) then
    jsonarray := '["' + aData.AsString + '"]'
  else
    jsonarray := '[' + aData.AsString + ']';

  if not Assigned(aCallback) then
    WriteSocketIOEvent(aContext, ''{no room}, aEventName, jsonarray, nil, nil)
  else
    WriteSocketIOEventRef(aContext, ''{no room}, aEventName, jsonarray,
      procedure(const aData: string)
      begin
        aCallback(aContext, SO(aData), nil);
      end, aOnError);
end;

procedure TIdServerSocketIOHandling.EmitEventTo(
  const aContext: TIdServerContext; const aEventName: string;
  const aData: ISuperObject; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var
  context: TSocketIOContext;
begin
  Lock;
  try
    context := FConnections.Items[aContext];
    EmitEventTo(context, aEventName, aData, aCallback, aOnError);
  finally
    UnLock;
  end;
end;

function TIdServerSocketIOHandling.EmitEventToAll(const aEventName,
  aData: string; const aCallback: TSocketIOMsgJSON;
  const aOnError: TSocketIOError): Integer;
var
  context: TSocketIOContext;
  jsonarray: string;
begin
  Result := 0;
  jsonarray := '[' + aData + ']';

  Lock;
  try
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, jsonarray, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, jsonarray,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(Result);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOEvent(context, ''{no room}, aEventName, jsonarray, nil, nil)
      else
        WriteSocketIOEventRef(context, ''{no room}, aEventName, jsonarray,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(Result);
    end;
  finally
    UnLock;
  end;
end;

function TIdServerSocketIOHandling.EmitEventToAll(const aEventName: string; const aData: ISuperObject;
  const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError): Integer;
begin
  if aData.IsType(stString) then
    Result := EmitEventToAll(aEventName, '"' + aData.AsString + '"', aCallback, aOnError)
  else
    Result := EmitEventToAll(aEventName, aData.AsString, aCallback, aOnError);
end;

procedure TIdServerSocketIOHandling.ProcessHeatbeatRequest(
  const AContext: TSocketIOContext; const aText: string);
begin
  inherited ProcessHeatbeatRequest(AContext, aText);
end;

procedure TIdServerSocketIOHandling.SendTo(const aContext: TIdServerContext;
  const aMessage: string; const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError);
var
  context: TSocketIOContext;
begin
  Lock;
  try
    context := FConnections.Items[aContext];
    if context.IsDisconnected then
      raise EIdSocketIoUnhandledMessage.Create('socket.io connection closed!');

    if not Assigned(aCallback) then
      WriteSocketIOMsg(context, ''{no room}, aMessage, nil)
    else
      WriteSocketIOMsg(context, ''{no room}, aMessage,
        procedure(const aData: string)
        begin
          aCallback(context, SO(aData), nil);
        end, aOnError);
  finally
    UnLock;
  end;
end;

function TIdServerSocketIOHandling.SendToAll(const aMessage: string;
  const aCallback: TSocketIOMsgJSON; const aOnError: TSocketIOError): Integer;
var
  context: TSocketIOContext;
begin
  Result := 0;
  Lock;
  try
    for context in FConnections.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOMsg(context, ''{no room}, aMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, aMessage,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end, aOnError);
      Inc(Result);
    end;
    for context in FConnectionsGUID.Values do
    begin
      if context.IsDisconnected then Continue;

      if not Assigned(aCallback) then
        WriteSocketIOMsg(context, ''{no room}, aMessage, nil)
      else
        WriteSocketIOMsg(context, ''{no room}, aMessage,
          procedure(const aData: string)
          begin
            aCallback(context, SO(aData), nil);
          end);
      Inc(Result);
    end;
  finally
    UnLock;
  end;
end;

end.
