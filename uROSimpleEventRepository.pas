unit uROSimpleEventRepository;

interface

uses
  uROEventRepository, uROClient, uROTypes, uROClientIntf,
  uROHTTPWebsocketServer, uROSessions, Classes, SyncObjs;

type
  TROSimpleWebsocketEventRepository = class(TInterfacedObject,
                                            IROEventRepository)
  private
    FMessage: TROMessage;
    FROServer: TROIndyHTTPWebsocketServer;
    FEventCount: Integer;
  protected
    {IROEventRepository}
    procedure AddSession(aSessionID : TGUID); overload;
    procedure AddSession(aSessionID : TGUID; aEventSinkId: AnsiString); overload;
    procedure RemoveSession(aSessionID : TGUID); overload;
    procedure RemoveSession(aSessionID : TGUID; aEventSinkId: AnsiString); overload;

    procedure StoreEventData(SourceSessionID : TGUID; Data : Binary;
                             const ExcludeSender: Boolean;
                             const ExcludeSessionList: Boolean;
                             const SessionList: String); overload;
    procedure StoreEventData(SourceSessionID : TGUID; Data : Binary;
                             const ExcludeSender: Boolean;
                             const ExcludeSessionList: Boolean;
                             const SessionList: String;
                             const EventSinkId: AnsiString); overload;
    function GetEventData(SessionID : TGUID; var TargetStream : Binary) : integer;
  public
    function GetEventWriter(const IID: TGUID): IROEventWriter;

    property Message : TROMessage read FMessage write FMessage;
    property ROServer: TROIndyHTTPWebsocketServer read FROServer write FROServer;
  end;

implementation

uses
  IdContext, IdIOHandlerWebsocket, Windows;

{ TSimpleEventRepository }

procedure TROSimpleWebsocketEventRepository.AddSession(aSessionID: TGUID);
begin
  //no session
end;

procedure TROSimpleWebsocketEventRepository.AddSession(aSessionID: TGUID;
  aEventSinkId: AnsiString);
begin
  //no session
end;

procedure TROSimpleWebsocketEventRepository.RemoveSession(aSessionID: TGUID;
  aEventSinkId: AnsiString);
begin
  //no session
end;

procedure TROSimpleWebsocketEventRepository.RemoveSession(aSessionID: TGUID);
begin
  //no session
end;

function TROSimpleWebsocketEventRepository.GetEventWriter(
  const IID: TGUID): IROEventWriter;
var
  lEventWriterClass: TROEventWriterClass;
begin
  lEventWriterClass := FindEventWriterClass(IID);
  if not assigned(lEventWriterClass) then exit;
  result := lEventWriterClass.Create(fMessage, Self) as IROEventWriter;
end;

function TROSimpleWebsocketEventRepository.GetEventData(SessionID: TGUID;
  var TargetStream: Binary): integer;
begin
  Result := -1;
  Assert(False);
end;

procedure TROSimpleWebsocketEventRepository.StoreEventData(SourceSessionID: TGUID;
  Data: Binary; const ExcludeSender, ExcludeSessionList: Boolean;
  const SessionList: String; const EventSinkId: AnsiString);
begin
  StoreEventData(SourceSessionID, Data, ExcludeSender, ExcludeSessionList, SessionList);
end;

procedure TROSimpleWebsocketEventRepository.StoreEventData(SourceSessionID: TGUID;
  Data: Binary; const ExcludeSender, ExcludeSessionList: Boolean;
  const SessionList: String);
var
  i, iEventNr: Integer;
  LContext: TIdContext;
  l: TList;
  ws: TIdIOHandlerWebsocket;
begin
  l := ROServer.IndyServer.Contexts.LockList;
  try
    if l.Count <= 0 then Exit;

    iEventNr      := -1 * InterlockedIncrement(FEventCount); //negative = event, positive is normal RO message
    if iEventNr > 0 then
    begin
      InterlockedExchange(FEventCount, 0);
      iEventNr    := -1 * InterlockedIncrement(FEventCount); //negative = event, positive is normal RO message
    end;
    Assert(iEventNr < 0);
    Data.Position := Data.Size;
    Data.Write(C_ROWSNR, Length(C_ROWSNR));
    Data.Write(iEventNr, SizeOf(iEventNr));
    Data.Position := 0;

    //direct write to ALL connections
    for i := 0 to l.Count - 1 do
    begin
      LContext := TIdContext(l.Items[i]);
      ws       := (LContext.Connection.IOHandler as TIdIOHandlerWebsocket);
      if not ws.IsWebsocket then Continue;
      ws.Lock;
      try
        ws.Write(Data, wdtBinary);
      finally
        ws.Unlock;
      end;
    end;
  finally
    ROServer.IndyServer.Contexts.UnlockList;
  end;
end;

end.

