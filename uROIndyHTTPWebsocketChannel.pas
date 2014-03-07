unit uROIndyHTTPWebsocketChannel;

interface

uses
  Classes, SyncObjs,
  uROIndyHTTPChannel, uROClientIntf,
  IdHTTPWebsocketClient, IdHTTP, IdWinsock2;

const
  C_RO_WS_NR: array[0..5] of AnsiChar = 'ROWSNR';

type
  TROIndyHTTPWebsocketChannel = class;

  //TROIndyHTTPSocketIOClient = class(TIdHTTPSocketIOClient_old)
  TROIndyHTTPSocketIOClient = class(TIdHTTPWebsocketClient)
  protected
    FParent: TROIndyHTTPWebsocketChannel;
  public
    procedure AsyncDispatchEvent(const aEvent: TStream); overload; override;
    procedure AsyncDispatchEvent(const aEvent: string); overload; override;
  end;

  TROIndyHTTPWebsocketChannel = class(TROIndyHTTPChannel,
                                      IROActiveEventChannel)
  private
    function  GetHost: string;
    function  GetPort: integer;
    procedure SetHost(const Value: string);
    procedure SetPort(const Value: integer);
    function  GetIndyClient: TIdHTTPWebsocketClient;
    procedure SetWSResourceName(const Value: string);
    function  GetWSResourceName: string;
  protected
    FTriedUpgrade: Boolean;
    FEventReceivers: TInterfaceList;
    FMessageNr: Integer;
    procedure IntDispatchEvent(aEvent: TStream);
    procedure AsyncDispatchEvent(aEvent: TStream);
    procedure SocketConnected(Sender: TObject);
    procedure ResetChannel;

    function  TryUpgradeToWebsocket: Boolean;
    procedure CheckConnection;
  protected
    procedure IntDispatch(aRequest, aResponse: TStream); override;
    function  CreateIndyClient: TIdHTTP; override;
  protected
    {IROActiveEventChannel}
    procedure RegisterEventReceiver  (aReceiver: IROEventReceiver);
    procedure UnregisterEventReceiver(aReceiver: IROEventReceiver);
  public
    procedure  AfterConstruction;override;
    destructor Destroy; override;
  published
    property  IndyClient: TIdHTTPWebsocketClient read GetIndyClient;
    property  Port: integer read GetPort write SetPort;
    property  Host: string  read GetHost write SetHost;
    property  WSResourceName: string read GetWSResourceName write SetWSResourceName;
  end;

  procedure Register;

implementation

uses
  SysUtils, Windows,
  IdStack, IdStackConsts, IdGlobal, IdStackBSDBase,
  uRORes, uROIndySupport, mcFinalizationHelper, IdIOHandlerWebsocket, StrUtils;

procedure Register;
begin
  RegisterComponents('RBK', [TROIndyHTTPWebsocketChannel]);
end;

type
  TAnonymousThread = class(TThread)
  protected
    FThreadProc: TThreadProcedure;
    procedure Execute; override;
  public
    constructor Create(AThreadProc: TThreadProcedure);
  end;

procedure CreateAnonymousThread(AThreadProc: TThreadProcedure);
begin
  TAnonymousThread.Create(AThreadProc);
end;

{ TROIndyHTTPChannel_Websocket }

procedure TROIndyHTTPWebsocketChannel.AfterConstruction;
begin
  inherited;
  FEventReceivers := TInterfaceList.Create;
  //not needed, is ignored at server now, but who knows later? :) e.g. support multiple sub protocols
  WSResourceName  := 'RemObjects';
end;

destructor TROIndyHTTPWebsocketChannel.Destroy;
begin
  if TIdWebsocketMultiReadThread.Instance <> nil then
    TIdWebsocketMultiReadThread.Instance.RemoveClient(Self.IndyClient);

  FEventReceivers.Free;
  inherited;
end;

function TROIndyHTTPWebsocketChannel.GetIndyClient: TIdHTTPWebsocketClient;
begin
  Result := inherited IndyClient as TIdHTTPWebsocketClient;
end;

procedure TROIndyHTTPWebsocketChannel.SetHost(const Value: string);
begin
  IndyClient.Host := Value;
  TargetURL := Format('ws://%s:%d/%s', [Host, Port, WSResourceName]);
end;

procedure TROIndyHTTPWebsocketChannel.SetPort(const Value: integer);
begin
  IndyClient.Port := Value;
  TargetURL := Format('ws://%s:%d/%s', [Host, Port, WSResourceName]);
end;

procedure TROIndyHTTPWebsocketChannel.SetWSResourceName(const Value: string);
begin
  IndyClient.WSResourceName := Value;
  TargetURL := Format('ws://%s:%d/%s', [Host, Port, WSResourceName]);
end;

function TROIndyHTTPWebsocketChannel.GetHost: string;
begin
  Result := IndyClient.Host;
end;

function TROIndyHTTPWebsocketChannel.GetPort: integer;
begin
  Result := IndyClient.Port;
end;

function TROIndyHTTPWebsocketChannel.GetWSResourceName: string;
begin
  Result := IndyClient.WSResourceName;
end;

procedure TROIndyHTTPWebsocketChannel.AsyncDispatchEvent(aEvent: TStream);
var
  strmevent: TMemoryStream;
begin
  strmevent := TMemoryStream.Create;
  strmevent.CopyFrom(aEvent, aEvent.Size);

  //events during dispatch? channel is busy so offload event dispatching to different thread!
  TIdWebsocketDispatchThread.Instance.QueueEvent(
    procedure
    begin
      IntDispatchEvent(strmevent);
      strmevent.Free;
    end);

  //events during dispatch? channel is busy so offload event dispatching to different thread!
//  CreateAnonymousThread(
//    procedure
//    begin
//      IntDispatchEvent(strmevent);
//      strmevent.Free;
//    end);
end;

procedure TROIndyHTTPWebsocketChannel.CheckConnection;
begin
  try
    if IndyClient.Connected then
      IndyClient.IOHandler.CheckForDisconnect(True, True)
  except
    IndyClient.Disconnect(False);
  end;
  if not IndyClient.Connected then
  begin
    if IndyClient.IOHandler <> nil then
      IndyClient.IOHandler.Clear;
    IndyClient.Connect;
    if not IndyClient.IOHandler.IsWebsocket then   //not already upgraded?
      TryUpgradeToWebsocket;
    FTriedUpgrade := True; //one shot
  end;
end;

function TROIndyHTTPWebsocketChannel.CreateIndyClient: TIdHTTP;
var
  wsclient: TROIndyHTTPSocketIOClient;
begin
  //Result := inherited CreateIndyClient;
  wsclient := TROIndyHTTPSocketIOClient.Create(Self);
//  wsclient := TIdHTTPWebsocketClient.Create(Self);
  wsclient.FParent     := Self;
  wsclient.Port        := 80;
  wsclient.Host        := '127.0.0.1';
  wsclient.Request.UserAgent := uRORes.str_ProductName;
  wsclient.OnConnected := SocketConnected;
  //TargetURL := '';

  Result := wsclient;
end;

procedure TROIndyHTTPWebsocketChannel.SocketConnected(Sender: TObject);
begin
  if DisableNagle then
    uROIndySupport.Indy_DisableNagle(IndyClient);
end;

function TROIndyHTTPWebsocketChannel.TryUpgradeToWebsocket: Boolean;
begin
  try
    Result := (IndyClient as TIdHTTPWebsocketClient).TryUpgradeToWebsocket;
    if Result then
    begin
      Self.IndyClient.IOHandler.InputBuffer.Clear;
      Self.IndyClient.IOHandler.ReadTimeout := Self.IndyClient.ReadTimeout;
      //background wait for data in single thread
      TIdWebsocketMultiReadThread.Instance.AddClient(Self.IndyClient);
    end;
  except
    ResetChannel;
    raise;
  end;
end;

procedure TROIndyHTTPWebsocketChannel.IntDispatch(aRequest, aResponse: TStream);
var
  cWSNR: array[0..High(C_RO_WS_NR)] of AnsiChar;
  iMsgNr, iMsgNr2: Integer;
  ws: TIdIOHandlerWebsocket;
  wscode: TWSDataCode;
  swstext: utf8string;
begin
  //http server supports websockets?
  if not FTriedUpgrade then
  begin
    if not IndyClient.IOHandler.IsWebsocket then   //not already upgraded?
      TryUpgradeToWebsocket;
    FTriedUpgrade := True; //one shot
  end;

  ws := IndyClient.IOHandler as TIdIOHandlerWebsocket;
  if not ws.IsWebsocket then
    //normal http dispatch
    inherited IntDispatch(aRequest, aResponse)
  else
  //websocket dispatch
  begin
    ws.Lock;
    try
      //write messagenr at end
      aRequest.Position := aRequest.Size;
      Inc(FMessageNr);
      iMsgNr := FMessageNr;
      aRequest.Write(C_RO_WS_NR, Length(C_RO_WS_NR));
      aRequest.Write(iMsgNr, SizeOf(iMsgNr));
      aRequest.Position := 0;

      CheckConnection;

      //write
      IndyClient.IOHandler.Write(aRequest);

      iMsgNr2 := 0;
      while iMsgNr2 <= 0 do
      begin
        aResponse.Size := 0;  //clear
        //first is the data type TWSDataType(text or bin), but is ignore/not needed
        wscode := TWSDataCode(IndyClient.IOHandler.ReadLongWord);
        //next the size + data = stream
        IndyClient.IOHandler.ReadStream(aResponse);
        //ignore ping/pong messages
        if wscode in [wdcPing, wdcPong] then Continue;
        if aResponse.Size >= Length(C_RO_WS_NR) + SizeOf(iMsgNr) then
        begin
          //get event or message nr
          aResponse.Position   := aResponse.Size - Length(C_RO_WS_NR) - SizeOf(iMsgNr2);
          aResponse.Read(cWSNR[0], Length(cWSNR));
        end;

        if (cWSNR = C_RO_WS_NR) then
        begin
          aResponse.Read(iMsgNr2, SizeOf(iMsgNr2));
          aResponse.Size       := aResponse.Size - Length(C_RO_WS_NR) - SizeOf(iMsgNr2); //trunc
          aResponse.Position   := 0;

          //event?
          if iMsgNr2 < 0 then
          begin
            //events during dispatch? channel is busy so offload event dispatching to different thread!
            AsyncDispatchEvent(aResponse);
            aResponse.Size := 0;
            {
            ws.Unlock;
            try
              IntDispatchEvent(aResponse);
              aResponse.Size := 0;
            finally
              ws.Lock;
            end;
            }
          end;
        end
        else
        begin
          aResponse.Position := 0;
          if wscode = wdcBinary then
          begin
            Self.IndyClient.AsyncDispatchEvent(aResponse);
          end
          else if wscode = wdcText then
          begin
            SetLength(swstext, aResponse.Size);
            aResponse.Read(swstext[1], aResponse.Size);
            if swstext <> '' then
            begin
              Self.IndyClient.AsyncDispatchEvent(string(swstext));
            end;
          end;
        end;
      end;
    except
      ws.Unlock; //always unlock
      ResetChannel;
      Raise;
    end;
    ws.Unlock;  //normal unlock (no extra try finally needed)

    if iMsgNr2 <> iMsgNr then
      Assert(iMsgNr2 = iMsgNr, 'Message number mismatch between send and received!');
  end;
end;

procedure TROIndyHTTPWebsocketChannel.IntDispatchEvent(aEvent: TStream);
var
  i: Integer;
  eventrecv: IROEventReceiver;
begin
  for i := 0 to FEventReceivers.Count - 1 do
  begin
    aEvent.Position := 0;
    eventrecv := FEventReceivers.Items[i] as IROEventReceiver;
    try
      eventrecv.Dispatch(aEvent, TThread.CurrentThread);
    except
      //ignore errors within events, so normal communication is preserved
    end;
  end;
end;

procedure TROIndyHTTPWebsocketChannel.RegisterEventReceiver(
  aReceiver: IROEventReceiver);
begin
  FEventReceivers.Add(aReceiver);
end;

procedure TROIndyHTTPWebsocketChannel.ResetChannel;
//var
//  ws: TIdIOHandlerWebsocket;
begin
  FTriedUpgrade := False; //reset
  TIdWebsocketMultiReadThread.Instance.RemoveClient(Self.IndyClient);

  if IndyClient.IOHandler <> nil then
  begin
    IndyClient.IOHandler.InputBuffer.Clear;
    //close/disconnect internal socket
    //ws := IndyClient.IOHandler as TIdIOHandlerWebsocket;
    //ws.Close;  done in disconnect below
  end;
  IndyClient.Disconnect(False);
end;

procedure TROIndyHTTPWebsocketChannel.UnregisterEventReceiver(
  aReceiver: IROEventReceiver);
begin
  FEventReceivers.Remove(aReceiver);
end;

{ TMultiChannelReadThread }

(*
procedure TROIndyWSMultiChannelReadThread_old.ReadFromAllChannels;
                if strmEvent = nil then
                  strmEvent := TMemoryStream.Create;
                strmEvent.Clear;

                //first is the data type TWSDataType(text or bin), but is ignore/not needed
                wscode := TWSDataCode(chn.IndyClient.IOHandler.ReadLongWord);
                //next the size + data = stream
                chn.IndyClient.IOHandler.ReadStream(strmEvent);

                //ignore ping/pong messages
                if wscode in [wdcPing, wdcPong] then Continue;
                if strmEvent.Size < Length(C_ROWSNR) + SizeOf(iEventNr) then Continue;

                //get event nr
                strmEvent.Position := strmEvent.Size - Length(C_ROWSNR) - SizeOf(iEventNr);
                strmEvent.Read(cWSNR[0], Length(cWSNR));
                Assert(cWSNR = C_ROWSNR);
                strmEvent.Read(iEventNr, SizeOf(iEventNr));
                Assert(iEventNr < 0);
                //trunc
                strmEvent.Size := strmEvent.Size - Length(C_ROWSNR) - SizeOf(iEventNr);

              //fire event
              //chn.IntDispatchEvent(strmEvent);
              //offload event dispatching to different thread! otherwise deadlocks possible? (do to synchronize)
              strmEvent.Position := 0;
              chn.AsyncDispatchEvent(strmEvent);
*)

{ TAnonymousThread }

constructor TAnonymousThread.Create(AThreadProc: TThreadProcedure);
begin
  FThreadProc := AThreadProc;
  FreeOnTerminate := True;
  inherited Create(False {direct start});
end;

procedure TAnonymousThread.Execute;
begin
  if Assigned(FThreadProc) then
    FThreadProc();
end;

{ TROIndyHTTPSocketIOClient }

procedure TROIndyHTTPSocketIOClient.AsyncDispatchEvent(const aEvent: TStream);
var
  iEventNr: Integer;
  cWSNR: array[0..High(C_RO_WS_NR)] of AnsiChar;
  s: string;
begin
  if aEvent.Size > Length(C_RO_WS_NR) + SizeOf(iEventNr) then
  begin
    //get event nr
    aEvent.Position := aEvent.Size - Length(C_RO_WS_NR) - SizeOf(iEventNr);
    aEvent.Read(cWSNR[0], Length(cWSNR));
    //has eventnr?
    if cWSNR = C_RO_WS_NR then
    begin
      aEvent.Read(iEventNr, SizeOf(iEventNr));
      if iEventNr >= 0 then
      begin
        aEvent.Position := 0;
        with TStreamReader.Create(aEvent) do
        begin
          s := ReadToEnd;
          Free;
        end;
        Assert(iEventNr < 0, 'must be negative number for RO events: ' + s);
      end;
      //trunc
      aEvent.Size := aEvent.Size - Length(C_RO_WS_NR) - SizeOf(iEventNr);

      aEvent.Position := 0;
      FParent.AsyncDispatchEvent(aEvent);
      Exit;
    end;
  end;

  inherited AsyncDispatchEvent(aEvent);
end;

procedure TROIndyHTTPSocketIOClient.AsyncDispatchEvent(const aEvent: string);
begin
  inherited AsyncDispatchEvent(aEvent);
end;

end.
