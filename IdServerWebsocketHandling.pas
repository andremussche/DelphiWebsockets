unit IdServerWebsocketHandling;
interface
{$I wsdefines.pas}
uses
  Classes, StrUtils, SysUtils, DateUtils
  , IdCoderMIME
  , IdThread
  , IdContext
  , IdCustomHTTPServer
  {$IF CompilerVersion <= 21.0}  //D2010
  , IdHashSHA1
  {$else}
  , IdHashSHA                     //XE3 etc
  {$IFEND}
  , IdServerSocketIOHandling
  //
  , IdSocketIOHandling
  , IdServerBaseHandling
  , IdServerWebsocketContext
  , IdIOHandlerWebsocket
  ;

type
  TIdServerSocketIOHandling_Ext = class(TIdServerSocketIOHandling)
  end;

  TIdServerWebsocketHandling = class(TIdServerBaseHandling)
  protected
    class procedure DoWSExecute(AThread: TIdContext; aSocketIOHandler: TIdServerSocketIOHandling_Ext);virtual;
    class procedure HandleWSMessage(AContext: TIdServerWSContext; var aType: TWSDataType;
                                    aRequestStrm, aResponseStrm: TMemoryStream;
                                    aSocketIOHandler: TIdServerSocketIOHandling_Ext);virtual;
  public
    class function ProcessServerCommandGet(AThread: TIdServerWSContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo): Boolean;

    class function CurrentSocket: ISocketIOContext;
  end;

implementation

{ TIdServerWebsocketHandling }

class function TIdServerWebsocketHandling.CurrentSocket: ISocketIOContext;
var
  thread: TIdThreadWithTask;
  context: TIdServerWSContext;
begin
  if not (TThread.Currentthread is TIdThreadWithTask) then Exit(nil);
  thread  := TThread.Currentthread as TIdThreadWithTask;
  if not (thread.Task is TIdServerWSContext) then Exit(nil);
  context := thread.Task as TIdServerWSContext;
  Result  := context.SocketIO.GetSocketIOContext(context);
end;

class procedure TIdServerWebsocketHandling.DoWSExecute(AThread: TIdContext; aSocketIOHandler: TIdServerSocketIOHandling_Ext);
var
  strmRequest, strmResponse: TMemoryStream;
  wscode: TWSDataCode;
  wstype: TWSDataType;
  context: TIdServerWSContext;
  tstart: TDateTime;
begin
  context   := nil;
  try
    context := AThread as TIdServerWSContext;
    //todo: make seperate function + do it after first real write (not header!)
    if context.IOHandler.BusyUpgrading then
    begin
      context.IOHandler.IsWebsocket   := True;
      context.IOHandler.BusyUpgrading := False;
    end;
    //initial connect
    if context.IsSocketIO then
    begin
      Assert(aSocketIOHandler <> nil);
      aSocketIOHandler.WriteConnect(context);
    end;
    AThread.Connection.Socket.UseNagle := False;  //no 200ms delay!

    tstart := Now;
    context := AThread as TIdServerWSContext;

    while AThread.Connection.Connected do
    begin
      if context.IOHandler.HasData or
        (AThread.Connection.IOHandler.InputBuffer.Size > 0) or
         AThread.Connection.IOHandler.Readable(1 * 1000) then     //wait 5s, else ping the client(!)
      begin
        tstart := Now;

        strmResponse := TMemoryStream.Create;
        strmRequest  := TMemoryStream.Create;
        try

          strmRequest.Position := 0;
          //first is the type: text or bin
          wscode := TWSDataCode(context.IOHandler.ReadLongWord);
          //then the length + data = stream
          context.IOHandler.ReadStream(strmRequest);
          strmRequest.Position := 0;
          //ignore ping/pong messages
          if wscode in [wdcPing, wdcPong] then
          begin
            if wscode = wdcPing then
              context.IOHandler.WriteData(nil, wdcPong);
            Continue;
          end;

          if wscode = wdcText
             then wstype := wdtText
             else wstype := wdtBinary;

          HandleWSMessage(context, wstype, strmRequest, strmResponse, aSocketIOHandler);

          //write result back (of the same type: text or bin)
          if strmResponse.Size > 0 then
          begin
            if wstype = wdtText
               then context.IOHandler.Write(strmResponse, wdtText)
               else context.IOHandler.Write(strmResponse, wdtBinary)
          end
          else context.IOHandler.WriteData(nil, wdcPing);
        finally
          strmRequest.Free;
          strmResponse.Free;
        end;
      end
      //ping after 5s idle
      else if SecondsBetween(Now, tstart) > 5 then
      begin
        tstart := Now;
        //ping
        if context.IsSocketIO then
        begin
          //context.SocketIOPingSend := True;
          Assert(aSocketIOHandler <> nil);
          aSocketIOHandler.WritePing(context);
        end
        else
        begin
          context.IOHandler.WriteData(nil, wdcPing);
        end;
      end;

    end;
  finally
    if context.IsSocketIO then
    begin
      Assert(aSocketIOHandler <> nil);
      aSocketIOHandler.WriteDisConnect(context);
    end;
    context.IOHandler.Clear;
    AThread.Data := nil;
  end;
end;

class procedure TIdServerWebsocketHandling.HandleWSMessage(AContext: TIdServerWSContext; var aType:TWSDataType; aRequestStrm, aResponseStrm: TMemoryStream; aSocketIOHandler: TIdServerSocketIOHandling_Ext);
begin
  if AContext.IsSocketIO then
  begin
    aRequestStrm.Position := 0;
    Assert(aSocketIOHandler <> nil);
    aSocketIOHandler.ProcessSocketIORequest(AContext, aRequestStrm);
  end
  else if Assigned(AContext.OnCustomChannelExecute) then
    AContext.OnCustomChannelExecute(AContext, aType, aRequestStrm, aResponseStrm);
end;

class function TIdServerWebsocketHandling.ProcessServerCommandGet(
  AThread: TIdServerWSContext; ARequestInfo: TIdHTTPRequestInfo;
  AResponseInfo: TIdHTTPResponseInfo): Boolean;
var
  Accept: Boolean;
  sValue, squid: string;
  context: TIdServerWSContext;
  hash: TIdHashSHA1;
  guid: TGUID;
begin
  (* GET /chat HTTP/1.1
     Host: server.example.com
     Upgrade: websocket
     Connection: Upgrade
     Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
     Origin: http://example.com
     Sec-WebSocket-Protocol: chat, superchat
     Sec-WebSocket-Version: 13 *)

  (* GET ws://echo.websocket.org/?encoding=text HTTP/1.1
     Origin: http://websocket.org
     Cookie: __utma=99as
     Connection: Upgrade
     Host: echo.websocket.org
     Sec-WebSocket-Key: uRovscZjNol/umbTt5uKmw==
     Upgrade: websocket
     Sec-WebSocket-Version: 13 *)

  //Connection: Upgrade
  if not ContainsText(ARequestInfo.Connection, 'Upgrade') then   //Firefox uses "keep-alive, Upgrade"
  begin
    //initiele ondersteuning voor socket.io
    if SameText(ARequestInfo.document , '/socket.io/1/') then
    begin
      {
      https://github.com/LearnBoost/socket.io-spec
      The client will perform an initial HTTP POST request like the following
      http://example.com/socket.io/1/
      200: The handshake was successful.
      The body of the response should contain the session id (sid) given to the client, followed by the heartbeat timeout, the connection closing timeout, and the list of supported transports separated by :
      The absence of a heartbeat timeout ('') is interpreted as the server and client not expecting heartbeats.
      For example 4d4f185e96a7b:15:10:websocket,xhr-polling.
      }
      AResponseInfo.ResponseNo   := 200;
      AResponseInfo.ResponseText := 'Socket.io connect OK';

      CreateGUID(guid);
      squid := GUIDToString(guid);
      AResponseInfo.ContentText  := squid +
                                    ':15:10:websocket,xhr-polling';
      AResponseInfo.CloseConnection := False;
      (AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(AThread);
      //(AThread.SocketIO as TIdServerSocketIOHandling_Ext).NewConnection(squid, AThread.Binding.PeerIP);

      Result := True;  //handled
    end
    //'/socket.io/1/xhr-polling/2129478544'
    else if StartsText('/socket.io/1/xhr-polling/', ARequestInfo.document) then
    begin
      AResponseInfo.ContentStream   := TMemoryStream.Create;
      AResponseInfo.CloseConnection := False;

      squid := Copy(ARequestInfo.Document, 1 + Length('/socket.io/1/xhr-polling/'), Length(ARequestInfo.document));
      if ARequestInfo.CommandType = hcGET then
        (AThread.SocketIO as TIdServerSocketIOHandling_Ext)
          .ProcessSocketIO_XHR(squid, ARequestInfo.PostStream, AResponseInfo.ContentStream)
      else if ARequestInfo.CommandType = hcPOST then
        (AThread.SocketIO as TIdServerSocketIOHandling_Ext)
          .ProcessSocketIO_XHR(squid, ARequestInfo.PostStream, nil);   //no response expected with POST!
      Result := True;  //handled
    end
    else
      Result := False;  //NOT handled
  end
  else
  begin
    Result  := True;  //handled
    context := AThread as TIdServerWSContext;

    if Assigned(Context.OnWebSocketUpgrade) then
     begin
        Accept := True;
        Context.OnWebSocketUpgrade(Context,ARequestInfo,Accept);
        if not Accept then Abort;
     end;

    //Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    sValue := ARequestInfo.RawHeaders.Values['sec-websocket-key'];
    //"The value of this header field MUST be a nonce consisting of a randomly
    // selected 16-byte value that has been base64-encoded"
    if (sValue <> '') then
    begin
      if (Length(TIdDecoderMIME.DecodeString(sValue)) = 16) then
        context.WebSocketKey := sValue
      else
        Abort; //invalid length
    end
    else
      //important: key must exists, otherwise stop!
      Abort;

    (*
     ws-URI = "ws:" "//" host [ ":" port ] path [ "?" query ]
     wss-URI = "wss:" "//" host [ ":" port ] path [ "?" query ]
     2.   The method of the request MUST be GET, and the HTTP version MUST be at least 1.1.
          For example, if the WebSocket URI is "ws://example.com/chat",
          the first line sent should be "GET /chat HTTP/1.1".
     3.   The "Request-URI" part of the request MUST match the /resource
          name/ defined in Section 3 (a relative URI) or be an absolute
          http/https URI that, when parsed, has a /resource name/, /host/,
          and /port/ that match the corresponding ws/wss URI.
    *)
    context.ResourceName := ARequestInfo.Document;
    if ARequestInfo.UnparsedParams <> '' then
      context.ResourceName := context.ResourceName + '?' +
                              ARequestInfo.UnparsedParams;
    //seperate parts
    context.Path         := ARequestInfo.Document;
    context.Query        := ARequestInfo.UnparsedParams;

    //Host: server.example.com
    context.Host   := ARequestInfo.RawHeaders.Values['host'];
    //Origin: http://example.com
    context.Origin := ARequestInfo.RawHeaders.Values['origin'];
    //Cookie: __utma=99as
    context.Cookie := ARequestInfo.RawHeaders.Values['cookie'];

    //Sec-WebSocket-Version: 13
    //"The value of this header field MUST be 13"
    sValue := ARequestInfo.RawHeaders.Values['sec-websocket-version'];
    if (sValue <> '') then
    begin
      context.WebSocketVersion := StrToIntDef(sValue, 0);

      if context.WebSocketVersion < 13 then
        Abort;  //must be at least 13
    end
    else
      Abort; //must exist

    context.WebSocketProtocol   := ARequestInfo.RawHeaders.Values['sec-websocket-protocol'];
    context.WebSocketExtensions := ARequestInfo.RawHeaders.Values['sec-websocket-extensions'];

    //Response
    (* HTTP/1.1 101 Switching Protocols
       Upgrade: websocket
       Connection: Upgrade
       Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo= *)
    AResponseInfo.ResponseNo         := 101;
    AResponseInfo.ResponseText       := 'Switching Protocols';
    AResponseInfo.CloseConnection    := False;
    //Connection: Upgrade
    AResponseInfo.Connection         := 'Upgrade';
    //Upgrade: websocket
    AResponseInfo.CustomHeaders.Values['Upgrade'] := 'websocket';

    //Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
    sValue := Trim(context.WebSocketKey) +                   //... "minus any leading and trailing whitespace"
              '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';        //special GUID
    hash := TIdHashSHA1.Create;
    try
      sValue := TIdEncoderMIME.EncodeBytes(                   //Base64
                     hash.HashString(sValue) );               //SHA1
    finally
      hash.Free;
    end;
    AResponseInfo.CustomHeaders.Values['Sec-WebSocket-Accept'] := sValue;
{$IFNDEF WS_NO_SSL}
    //keep alive the ssl connection
    AResponseInfo.CustomHeaders.Values['Keep-alive'] := 'true';
{$ENDIF}
        
    //send same protocol back?
    AResponseInfo.CustomHeaders.Values['Sec-WebSocket-Protocol']   := context.WebSocketProtocol;
    //we do not support extensions yet (gzip deflate compression etc)
    //AResponseInfo.CustomHeaders.Values['Sec-WebSocket-Extensions'] := context.WebSocketExtensions;
    //http://www.lenholgate.com/blog/2011/07/websockets---the-deflate-stream-extension-is-broken-and-badly-designed.html
    //but is could be done using idZlib.pas and DecompressGZipStream etc
{$IFNDEF WS_NO_SSL}
    //YD: TODO: Check if this is really necessary
    AResponseInfo.CustomHeaders.Values['sec-websocket-extensions']   := '';
    context.WebSocketExtensions := '';
{$ENDIF}

    //send response back
    context.IOHandler.InputBuffer.Clear;
    context.IOHandler.BusyUpgrading := True;
    AResponseInfo.WriteHeader;

    //handle all WS communication in seperate loop
    DoWSExecute(AThread, (context.SocketIO as TIdServerSocketIOHandling_Ext) );
  end;
end;

end.
