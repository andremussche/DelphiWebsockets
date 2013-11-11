unit IdIOHandlerWebsocket;

//The WebSocket Protocol, RFC 6455
//http://datatracker.ietf.org/doc/rfc6455/?include_text=1

interface

uses
  Classes,
  IdIOHandlerStack, IdGlobal, IdException, IdBuffer, SyncObjs,
  Generics.Collections;

type
  TWSDataType      = (wdtText, wdtBinary);
  TWSDataCode      = (wdcNone, wdcContinuation, wdcText, wdcBinary, wdcClose, wdcPing, wdcPong);
  TWSExtensionBit  = (webBit1, webBit2, webBit3);
  TWSExtensionBits = set of TWSExtensionBit;

  TIdIOHandlerWebsocket   = class;
  EIdWebSocketHandleError = class(EIdSocketHandleError);

  TIdIOHandlerWebsocket = class(TIdIOHandlerStack)
  private
    FIsServerSide: Boolean;
    FBusyUpgrading: Boolean;
    FIsWebsocket: Boolean;
    FWSInputBuffer: TIdBuffer;
    FExtensionBits: TWSExtensionBits;
    FLock: TCriticalSection;
    FCloseReason: string;
    FCloseCode: Integer;
    FClosing: Boolean;
  protected
    FMessageStream: TMemoryStream;
    FWriteTextToTarget: Boolean;
    FCloseCodeSend: Boolean;

    function InternalReadDataFromSource(var VBuffer: TIdBytes): Integer;
    function ReadDataFromSource(var VBuffer: TIdBytes): Integer; override;
    function WriteDataToTarget (const ABuffer: TIdBytes; const AOffset, ALength: Integer): Integer; override;

    function ReadFrame(out aFIN, aRSV1, aRSV2, aRSV3: boolean; out aDataCode: TWSDataCode; out aData: TIdBytes): Integer;
    function ReadMessage(var aBuffer: TIdBytes; out aDataCode: TWSDataCode): Integer;
  public
    function WriteData(aData: TIdBytes; aType: TWSDataCode;
                        aFIN: boolean = true; aRSV1: boolean = false; aRSV2: boolean = false; aRSV3: boolean = false): integer;
    property BusyUpgrading : Boolean read FBusyUpgrading write FBusyUpgrading;
    property IsWebsocket   : Boolean read FIsWebsocket   write FIsWebsocket;
    property IsServerSide  : Boolean read FIsServerSide  write FIsServerSide;
    property ClientExtensionBits : TWSExtensionBits read FExtensionBits write FExtensionBits;
  public
    procedure  AfterConstruction;override;
    destructor Destroy; override;

    procedure Lock;
    procedure Unlock;
    function  TryLock: Boolean;

    procedure Close; override;
    property  Closing    : Boolean read FClosing;
    property  CloseCode  : Integer read FCloseCode   write FCloseCode;
    property  CloseReason: string  read FCloseReason write FCloseReason;

    //text/string writes
    procedure Write(const AOut: string; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure WriteLn(const AOut: string; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure WriteLnRFC(const AOut: string = ''; AEncoding: TIdTextEncoding = nil); override;
    procedure Write(AValue: TStrings; AWriteLinesCount: Boolean = False; AEncoding: TIdTextEncoding = nil); overload; override;
    procedure Write(AStream: TStream; aType: TWSDataType); overload;
  end;

//close frame codes
const
  C_FrameClose_Normal            = 1000; //1000 indicates a normal closure, meaning that the purpose for
                                         //which the connection was established has been fulfilled.
  C_FrameClose_GoingAway         = 1001; //1001 indicates that an endpoint is "going away", such as a server
                                         //going down or a browser having navigated away from a page.
  C_FrameClose_ProtocolError     = 1002; //1002 indicates that an endpoint is terminating the connection due
                                         //to a protocol error.
  C_FrameClose_UnhandledDataType = 1003; //1003 indicates that an endpoint is terminating the connection
                                         //because it has received a type of data it cannot accept (e.g., an
                                         //endpoint that understands only text data MAY send this if it
                                         //receives a binary message).
  C_FrameClose_Reserved          = 1004; //Reserved.  The specific meaning might be defined in the future.
  C_FrameClose_ReservedNoStatus  = 1005; //1005 is a reserved value and MUST NOT be set as a status code in a
                                         //Close control frame by an endpoint.  It is designated for use in
                                         //applications expecting a status code to indicate that no status
                                         //code was actually present.
  C_FrameClose_ReservedAbnormal  = 1006; //1006 is a reserved value and MUST NOT be set as a status code in a
                                         //Close control frame by an endpoint.  It is designated for use in
                                         //applications expecting a status code to indicate that the
                                         //connection was closed abnormally, e.g., without sending or
                                         //receiving a Close control frame.
  C_FrameClose_InconsistentData  = 1007; //1007 indicates that an endpoint is terminating the connection
                                         //because it has received data within a message that was not
                                         //consistent with the type of the message (e.g., non-UTF-8 [RFC3629]
                                         //data within a text message).
  C_FrameClose_PolicyError       = 1008; //1008 indicates that an endpoint is terminating the connection
                                         //because it has received a message that violates its policy.  This
                                         //is a generic status code that can be returned when there is no
                                         //other more suitable status code (e.g., 1003 or 1009) or if there
                                         //is a need to hide specific details about the policy.
  C_FrameClose_ToBigMessage      = 1009; //1009 indicates that an endpoint is terminating the connection
                                         //because it has received a message that is too big for it to process.
  C_FrameClose_MissingExtenstion = 1010; //1010 indicates that an endpoint (client) is terminating the
                                         //connection because it has expected the server to negotiate one or
                                         //more extension, but the server didn't return them in the response
                                         //message of the WebSocket handshake.  The list of extensions that
                                         //are needed SHOULD appear in the /reason/ part of the Close frame.
                                         //Note that this status code is not used by the server, because it
                                         //can fail the WebSocket handshake instead.
  C_FrameClose_UnExpectedError   = 1011; //1011 indicates that a server is terminating the connection because
                                         //it encountered an unexpected condition that prevented it from
                                         //fulfilling the request.
  C_FrameClose_ReservedTLSError  = 1015; //1015 is a reserved value and MUST NOT be set as a status code in a
                                         //Close control frame by an endpoint.  It is designated for use in
                                         //applications expecting a status code to indicate that the
                                         //connection was closed due to a failure to perform a TLS handshake
                                         //(e.g., the server certificate can't be verified).

implementation

uses
  SysUtils, Math, IdStream, IdStack, IdWinsock2, IdExceptionCore,
  IdResourceStrings, IdResourceStringsCore;

//frame codes
const
  C_FrameCode_Continuation = 0;
  C_FrameCode_Text         = 1;
  C_FrameCode_Binary       = 2;
  //3-7 are reserved for further non-control frames
  C_FrameCode_Close        = 8;
  C_FrameCode_Ping         = 9;
  C_FrameCode_Pong         = 10 {A};
  //B-F are reserved for further control frames

{ TIdIOHandlerStack_Websocket }

procedure TIdIOHandlerWebsocket.AfterConstruction;
begin
  inherited;
  FMessageStream := TMemoryStream.Create;
  FWSInputBuffer := TIdBuffer.Create;
  FLock := TCriticalSection.Create;
end;

procedure TIdIOHandlerWebsocket.Close;
var
  iaWriteBuffer: TIdBytes;
  sReason: UTF8String;
  iOptVal, iOptLen: Integer;
  bConnected: Boolean;
begin
  try
    //valid connection?
    bConnected := Opened and
                  SourceIsAvailable and
                  not ClosedGracefully;

    //no socket error? connection closed by software abort, connection reset by peer, etc
    iOptLen    := SIZE_INTEGER;
    bConnected := bConnected and
                  (IdWinsock2.getsockopt(Self.Binding.Handle, SOL_SOCKET, SO_ERROR, PAnsiChar(@iOptVal), iOptLen) = 0) and
                  (iOptVal = 0);

    if bConnected and IsWebsocket then
    begin
      //close message must be responded with a close message back
      //or initiated with a close message
      if not FCloseCodeSend then
      begin
        FCloseCodeSend  := True;

        //we initiate the close? then write reason etc
        if not Closing then
        begin
          SetLength(iaWriteBuffer, 2);
          if CloseCode < C_FrameClose_Normal then
            CloseCode := C_FrameClose_Normal;
          iaWriteBuffer[0] := Byte(CloseCode shr 8);
          iaWriteBuffer[1] := Byte(CloseCode);
          if CloseReason <> '' then
          begin
            sReason := utf8string(CloseReason);
            SetLength(iaWriteBuffer, Length(iaWriteBuffer) + Length(sReason));
            Move(sReason[1], iaWriteBuffer[2], Length(sReason));
          end;
        end
        else
        begin
          //just send normal close response back
          SetLength(iaWriteBuffer, 2);
          iaWriteBuffer[0] := Byte(C_FrameClose_Normal shr 8);
          iaWriteBuffer[1] := Byte(C_FrameClose_Normal);
        end;

        WriteData(iaWriteBuffer, wdcClose);  //send close + code back
      end;

      //we did initiate the close? then wait (a little) for close response
      if not Closing then
      begin
        FClosing := True;
        CheckForDisconnect();
        //wait till client respond with close message back
        //but a pending message can be in the buffer, so process this too
        while ReadFromSource(False{no disconnect error}, 1 * 1000, False) > 0 do ; //response within 1s?
      end;
    end;
  except
    //ignore, it's possible that the client is disconnected already (crashed etc)
  end;

  IsWebsocket   := False;
  BusyUpgrading := False;
  inherited Close;
end;

destructor TIdIOHandlerWebsocket.Destroy;
begin
  FLock.Enter;
  FLock.Free;

  FWSInputBuffer.Free;
  FMessageStream.Free;
  inherited;
end;

function TIdIOHandlerWebsocket.InternalReadDataFromSource(
  var VBuffer: TIdBytes): Integer;
begin
  CheckForDisconnect;
  if not Readable(ReadTimeout) or
     not Opened or
     not SourceIsAvailable then
  begin
    CheckForDisconnect; //disconnected during wait in "Readable()"?
    if not Opened then
      EIdNotConnected.Toss(RSNotConnected)
    else if not SourceIsAvailable then
      EIdClosedSocket.Toss(RSStatusDisconnected);
    GStack.CheckForSocketError(GStack.WSGetLastError); //check for socket error
    EIdReadTimeout.Toss(RSIdNoDataToRead);  //exit, no data can be received
  end;

  SetLength(VBuffer, RecvBufferSize);
  Result := inherited ReadDataFromSource(VBuffer);
  if Result = 0 then
  begin
    CheckForDisconnect; //disconnected in the mean time?
    GStack.CheckForSocketError(GStack.WSGetLastError); //check for socket error
    EIdNoDataToRead.Toss(RSIdNoDataToRead); //nothing read? then connection is probably closed -> exit
  end;
  SetLength(VBuffer, Result);
end;

procedure TIdIOHandlerWebsocket.WriteLn(const AOut: string;
  AEncoding: TIdTextEncoding);
begin
  FWriteTextToTarget := True;
  try
    inherited WriteLn(AOut, TIdTextEncoding.UTF8);  //must be UTF8!
  finally
    FWriteTextToTarget := False;
  end;
end;

procedure TIdIOHandlerWebsocket.WriteLnRFC(const AOut: string;
  AEncoding: TIdTextEncoding);
begin
  FWriteTextToTarget := True;
  try
    inherited WriteLnRFC(AOut, TIdTextEncoding.UTF8);  //must be UTF8!
  finally
    FWriteTextToTarget := False;
  end;
end;

procedure TIdIOHandlerWebsocket.Write(const AOut: string;
  AEncoding: TIdTextEncoding);
begin
  FWriteTextToTarget := True;
  try
    inherited Write(AOut, TIdTextEncoding.UTF8);  //must be UTF8!
  finally
    FWriteTextToTarget := False;
  end;
end;

procedure TIdIOHandlerWebsocket.Write(AValue: TStrings;
  AWriteLinesCount: Boolean; AEncoding: TIdTextEncoding);
begin
  FWriteTextToTarget := True;
  try
    inherited Write(AValue, AWriteLinesCount, TIdTextEncoding.UTF8);  //must be UTF8!
  finally
    FWriteTextToTarget := False;
  end;
end;

procedure TIdIOHandlerWebsocket.Write(AStream: TStream;
  aType: TWSDataType);
begin
  FWriteTextToTarget := (aType = wdtText);
  try
    inherited Write(AStream);
  finally
    FWriteTextToTarget := False;
  end;
end;

function TIdIOHandlerWebsocket.WriteDataToTarget(const ABuffer: TIdBytes;
  const AOffset, ALength: Integer): Integer;
begin
  if not IsWebsocket then
    Result := inherited WriteDataToTarget(ABuffer, AOffset, ALength)
  else
  begin
    Lock;
    try
      if FWriteTextToTarget then
        Result := WriteData(ABuffer, wdcText, True{send all at once},
                            webBit1 in ClientExtensionBits, webBit2 in ClientExtensionBits, webBit3 in ClientExtensionBits)
      else
        Result := WriteData(ABuffer, wdcBinary, True{send all at once},
                            webBit1 in ClientExtensionBits, webBit2 in ClientExtensionBits, webBit3 in ClientExtensionBits);
    except
      Unlock;  //always unlock when socket exception
      FClosedGracefully := True;
      Raise;
    end;
    Unlock;  //normal unlock (no double try finally)
  end;
end;

function TIdIOHandlerWebsocket.ReadDataFromSource(
  var VBuffer: TIdBytes): Integer;
var
  wscode: TWSDataCode;
begin
  //the first time something is read AFTER upgrading, we switch to WS
  //(so partial writes can be done, till a read is done)
  if BusyUpgrading then
  begin
    BusyUpgrading := False;
    IsWebsocket   := True;
  end;

  if not IsWebsocket then
    Result := inherited ReadDataFromSource(VBuffer)
  else
  begin
    Lock;
    try
      //we wait till we have a full message here (can be fragmented in several frames)
      Result := ReadMessage(VBuffer, wscode);

      //first write the data code (text or binary, ping, pong)
      FInputBuffer.Write(LongWord(Ord(wscode)));
      //we write message size here, vbuffer is written after this. This way we can use ReadStream to get 1 single message (in case multiple messages in FInputBuffer)
      if LargeStream then
        FInputBuffer.Write(Int64(Result))
      else
        FInputBuffer.Write(LongWord(Result))
    except
      Unlock;  //always unlock when socket exception
      FClosedGracefully := True; //closed (but not gracefully?)
      Raise;
    end;
    Unlock;  //normal unlock (no double try finally)
  end;
end;

function TIdIOHandlerWebsocket.ReadMessage(var aBuffer: TIdBytes; out aDataCode: TWSDataCode): Integer;
var
  iReadCount: Integer;
  iaReadBuffer: TIdBytes;
  bFIN, bRSV1, bRSV2, bRSV3: boolean;
  lDataCode: TWSDataCode;
  lFirstDataCode: TWSDataCode;
//    closeCode: integer;
//    closeResult: string;
begin
  Result := 0;
  (* ...all fragments of a message are of
     the same type, as set by the first fragment's opcode.  Since
     control frames cannot be fragmented, the type for all fragments in
     a message MUST be either text, binary, or one of the reserved
     opcodes. *)
  lFirstDataCode := wdcNone;
  FMessageStream.Clear;
  repeat
    //read a single frame
    iReadCount := ReadFrame(bFIN, bRSV1, bRSV2, bRSV3, lDataCode, iaReadBuffer);
    if (iReadCount > 0) or
       (lDataCode <> wdcNone) then
    begin
      Assert(Length(iaReadBuffer) = iReadCount);

      //store client extension bits
      if Self.IsServerSide then
      begin
        ClientExtensionBits := [];
        if bRSV1 then ClientExtensionBits := ClientExtensionBits + [webBit1];
        if bRSV2 then ClientExtensionBits := ClientExtensionBits + [webBit2];
        if bRSV3 then ClientExtensionBits := ClientExtensionBits + [webBit3];
      end;

      //process frame
      case lDataCode of
        wdcText, wdcBinary:
          begin
            if lFirstDataCode <> wdcNone then
              raise EIdWebSocketHandleError.Create('Invalid frame: specified data code only allowed for the first frame');
            lFirstDataCode := lDataCode;

            FMessageStream.Clear;
            TIdStreamHelper.Write(FMessageStream, iaReadBuffer);
          end;
        wdcContinuation:
          begin
            if not (lFirstDataCode in [wdcText, wdcBinary]) then
              raise EIdWebSocketHandleError.Create('Invalid frame continuation');
            TIdStreamHelper.Write(FMessageStream, iaReadBuffer);
          end;
        wdcClose:
          begin
            FCloseCode := C_FrameClose_Normal;
            //"If there is a body, the first two bytes of the body MUST be a 2-byte
            // unsigned integer (in network byte order) representing a status code"
            if Length(iaReadBuffer) > 1 then
            begin
              FCloseCode := (iaReadBuffer[0] shl 8) +
                             iaReadBuffer[1];
              if Length(iaReadBuffer) > 2 then
                FCloseReason := BytesToString(iaReadBuffer, 2, Length(iaReadBuffer), TEncoding.UTF8);
            end;

            FClosing := True;
            Self.Close;
          end;
        //Note: control frames can be send between fragmented frames
        wdcPing:
        begin
          WriteData(iaReadBuffer, wdcPong);  //send pong + same data back
          lFirstDataCode := lDataCode;
          //bFIN := False; //ignore ping when we wait for data?
        end;
        wdcPong:
        begin
           //pong received, ignore;
          lFirstDataCode := lDataCode;
        end;
      end;
    end
    else
      Break;
  until bFIN;

  //done?
  if bFIN then
  begin
    if (lFirstDataCode in [wdcText, wdcBinary]) then
    begin
      //result
      FMessageStream.Position := 0;
      TIdStreamHelper.ReadBytes(FMessageStream, aBuffer);
      Result    := FMessageStream.Size;
      aDataCode := lFirstDataCode
    end
    else if (lFirstDataCode in [wdcPing, wdcPong]) then
    begin
      //result
      FMessageStream.Position := 0;
      TIdStreamHelper.ReadBytes(FMessageStream, aBuffer);
      SetLength(aBuffer, FMessageStream.Size);
      //dummy data: there *must* be some data read otherwise connection is closed by Indy!
      if Length(aBuffer) <= 0 then
      begin
        SetLength(aBuffer, 1);
        aBuffer[0] := Ord(lFirstDataCode);
      end;

      Result    := Length(aBuffer);
      aDataCode := lFirstDataCode
    end;
  end;
end;

procedure TIdIOHandlerWebsocket.Lock;
begin
  FLock.Enter;
end;

function TIdIOHandlerWebsocket.TryLock: Boolean;
begin
  Result := FLock.TryEnter;
end;

procedure TIdIOHandlerWebsocket.Unlock;
begin
  FLock.Leave;
end;

function TIdIOHandlerWebsocket.ReadFrame(out aFIN, aRSV1, aRSV2, aRSV3: boolean;
                                               out aDataCode: TWSDataCode; out aData: TIdBytes): Integer;
var
  iInputPos: NativeInt;

  function _GetByte: Byte;
  var
    temp: TIdBytes;
  begin
    while FWSInputBuffer.Size <= iInputPos do
    begin
      //FWSInputBuffer.AsString;
      InternalReadDataFromSource(temp);
      FWSInputBuffer.Write(temp);
    end;

    //Self.ReadByte copies all data everytime (because the first byte must be removed) so we use index (much more efficient)
    Result := FWSInputBuffer.PeekByte(iInputPos);
    //FWSInputBuffer.AsString
    inc(iInputPos);
  end;

  function _GetBytes(aCount: Integer): TIdBytes;
  var
    temp: TIdBytes;
  begin
    while FWSInputBuffer.Size < aCount do
    begin
      InternalReadDataFromSource(temp);
      FWSInputBuffer.Write(temp);
    end;

    FWSInputBuffer.ExtractToBytes(Result, aCount);
  end;

var
  iByte: Byte;
  i, iCode: NativeInt;
  bHasMask: boolean;
  iDataLength, iPos: Int64;
  rMask: record
    case Boolean of
      True : (MaskAsBytes: array[0..3] of Byte);
      False: (MaskAsInt  : Int32);
  end;
begin
  iInputPos := 0;
  SetLength(aData, 0);
  aDataCode := wdcNone;

  //wait + process data
  iByte := _GetByte;
  (* 0                   1                   2                   3
     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 (nr)
     7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0 (bit)
    +-+-+-+-+-------+-+-------------+-------------------------------+
    |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
    |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
    |N|V|V|V|       |S|             |   (if payload len==126/127)   |
    | |1|2|3|       |K|             |                               |
    +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - + *)
  //FIN, RSV1, RSV2, RSV3: 1 bit each
  aFIN   := (iByte and (1 shl 7)) > 0;
  aRSV1  := (iByte and (1 shl 6)) > 0;
  aRSV2  := (iByte and (1 shl 5)) > 0;
  aRSV3  := (iByte and (1 shl 4)) > 0;
  //Opcode: 4 bits
  iCode  := (iByte and $0F); //clear 4 MSB's
  case iCode of
    C_FrameCode_Continuation: aDataCode := wdcContinuation;
    C_FrameCode_Text:         aDataCode := wdcText;
    C_FrameCode_Binary:       aDataCode := wdcBinary;
    C_FrameCode_Close:        aDataCode := wdcClose;
    C_FrameCode_Ping:         aDataCode := wdcPing;
    C_FrameCode_Pong:         aDataCode := wdcPong;
  else
    raise EIdException.CreateFmt('Unsupported data code: %d', [iCode]);
  end;

  //Mask: 1 bit
  iByte       := _GetByte;
  bHasMask    := (iByte and (1 shl 7)) > 0;
  //Length (7 bits or 7+16 bits or 7+64 bits)
  iDataLength := (iByte and $7F);  //clear 1 MSB
  //Extended payload length?
  //If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length
  if (iDataLength = 126) then
  begin
    iByte       := _GetByte;
    iDataLength := (iByte shl 8); //8 MSB
    iByte       := _GetByte;
    iDataLength := iDataLength + iByte;
  end
  //If 127, the following 8 bytes interpreted as a 64-bit unsigned integer (the most significant bit MUST be 0) are the payload length
  else if (iDataLength = 127) then
  begin
    iDataLength := 0;
    for i := 7 downto 0 do  //read 8 bytes in reverse order
    begin
      iByte       := _GetByte;
      iDataLength := iDataLength +
                     (Int64(iByte) shl (8 * i)); //shift bits to left to recreate 64bit integer
    end;
    Assert(iDataLength > 0);
  end;

  //"All frames sent from client to server must have this bit set to 1"
  if IsServerSide and not bHasMask then
    raise EIdWebSocketHandleError.Create('No mask supplied: mask is required for clients when sending data to server')
  else if not IsServerSide and bHasMask then
    raise EIdWebSocketHandleError.Create('Mask supplied but mask is not allowed for servers when sending data to clients');

  //Masking-key: 0 or 4 bytes
  if bHasMask then
  begin
    rMask.MaskAsBytes[0] := _GetByte;
    rMask.MaskAsBytes[1] := _GetByte;
    rMask.MaskAsBytes[2] := _GetByte;
    rMask.MaskAsBytes[3] := _GetByte;
  end;
  //Payload data:  (x+y) bytes
  FWSInputBuffer.Remove(iInputPos);  //remove first couple of processed bytes (header)
  //simple read?
  if not bHasMask then
    aData := _GetBytes(iDataLength)
  else
  //reverse mask
  begin
    aData := _GetBytes(iDataLength);
    iPos   := 0;
    while iPos < iDataLength do
    begin
      aData[iPos] := aData[iPos] xor
                      rMask.MaskAsBytes[iPos mod 4]; //apply mask
      inc(iPos);
    end;
  end;

  Result := Length(aData);
end;

function TIdIOHandlerWebsocket.WriteData(aData: TIdBytes;
  aType: TWSDataCode; aFIN, aRSV1, aRSV2, aRSV3: boolean): integer;
var
  iByte: Byte;
  i: NativeInt;
  iDataLength, iPos: Int64;
  rLength: Int64Rec;
  rMask: record
    case Boolean of
      True : (MaskAsBytes: array[0..3] of Byte);
      False: (MaskAsInt  : Int32);
  end;
  strmData: TMemoryStream;
  bData: TBytes;
begin
  Result := 0;
  Assert(Binding <> nil);

  strmData := TMemoryStream.Create;
  try
    (* 0                   1                   2                   3
       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 (nr)
       7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0|7 6 5 4 3 2 1 0 (bit)
      +-+-+-+-+-------+-+-------------+-------------------------------+
      |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
      |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
      |N|V|V|V|       |S|             |   (if payload len==126/127)   |
      | |1|2|3|       |K|             |                               |
      +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - + *)
    //FIN, RSV1, RSV2, RSV3: 1 bit each
    if aFIN  then iByte :=         (1 shl 7);
    if aRSV1 then iByte := iByte + (1 shl 6);
    if aRSV2 then iByte := iByte + (1 shl 5);
    if aRSV3 then iByte := iByte + (1 shl 4);
    //Opcode: 4 bits
    case aType of
      wdcContinuation : iByte := iByte + C_FrameCode_Continuation;
      wdcText         : iByte := iByte + C_FrameCode_Text;
      wdcBinary       : iByte := iByte + C_FrameCode_Binary;
      wdcClose        : iByte := iByte + C_FrameCode_Close;
      wdcPing         : iByte := iByte + C_FrameCode_Ping;
      wdcPong         : iByte := iByte + C_FrameCode_Pong;
    else
      raise EIdException.CreateFmt('Unsupported data code: %d', [Ord(aType)]);
    end;
    strmData.Write(iByte, SizeOf(iByte));

    iByte := 0;
    //Mask: 1 bit; Note: Clients must apply a mask
    if not IsServerSide then iByte := (1 shl 7);

    //Length: 7 bits or 7+16 bits or 7+64 bits
    if Length(aData) < 126 then            //7 bit, 128
      iByte := iByte + Length(aData)
    else if Length(aData) < 1 shl 16 then  //16 bit, 65536
      iByte := iByte + 126
    else
      iByte := iByte + 127;
    strmData.Write(iByte, SizeOf(iByte));

    //Extended payload length?
    if Length(aData) >= 126 then
    begin
      //If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length
      if Length(aData) < 1 shl 16 then  //16 bit, 65536
      begin
        rLength.Lo := Length(aData);
        iByte := rLength.Bytes[1];
        strmData.Write(iByte, SizeOf(iByte));
        iByte := rLength.Bytes[0];
        strmData.Write(iByte, SizeOf(iByte));
      end
      else
      //If 127, the following 8 bytes interpreted as a 64-bit unsigned integer (the most significant bit MUST be 0) are the payload length
      begin
        rLength := Int64Rec(Int64(Length(aData)));
        for i := 7 downto 0 do
        begin
          iByte := rLength.Bytes[i];
          strmData.Write(iByte, SizeOf(iByte));
        end;
      end
    end;

    //Masking-key: 0 or 4 bytes; Note: Clients must apply a mask
    if not IsServerSide then
    begin
      rMask.MaskAsInt := Random(MaxInt);
      strmData.Write(rMask.MaskAsBytes[0], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[1], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[2], SizeOf(Byte));
      strmData.Write(rMask.MaskAsBytes[3], SizeOf(Byte));
    end;

    //write header
    strmData.Position := 0;
    TIdStreamHelper.ReadBytes(strmData, bData);
    Result := Binding.Send(bData);

    //Mask? Note: Only clients must apply a mask
    if IsServerSide then
    begin
      Result := Binding.Send(aData);
    end
    else
    begin
      iPos := 0;
      iDataLength := Length(aData);
      //in place masking
      while iPos < iDataLength do
      begin
        iByte := aData[iPos] xor rMask.MaskAsBytes[iPos mod 4]; //apply mask
        aData[iPos] := iByte;
        inc(iPos);
      end;

      //send masked data
      Result := Binding.Send(aData);
    end;
  finally
    strmData.Free;
  end;
end;

end.
