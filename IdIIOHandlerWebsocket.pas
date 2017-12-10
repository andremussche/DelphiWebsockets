unit IdIIOHandlerWebsocket;

interface
uses
  System.Classes, IdGlobal, IdSocketHandle, IdBuffer, IdWebSocketTypes;

type
  {$if CompilerVersion >= 26}   //XE5
  TIdTextEncoding = IIdTextEncoding;
  {$ifend}

  IIOHandlerWebsocket = interface
    ['{6F5E19B2-7D2D-436D-B5A7-063C2B4E59B8}']
    function  CheckForDataOnSource(ATimeout: Integer = 0): Boolean;
    procedure CheckForDisconnect(ARaiseExceptionIfDisconnected: Boolean; AIgnoreBuffer: Boolean);
    procedure Clear;
    function  GetBinding: TIdSocketHandle;
    function  GetClosedGracefully: Boolean;
    function  GetConnected: Boolean;
    function  GetInputBuffer: TIdBuffer;
    function  GetIsWebsocket: Boolean;
    function  GetLastPingTime: TDateTime;
    function  GetLastActivityTime: TDateTime;
    function  HasData: Boolean;
    procedure Lock;
    function  ReadLongWord(AConvert: Boolean = True): UInt32;
    procedure ReadStream(AStream: TStream; AByteCount: TIdStreamSize = -1; AReadUntilDisconnect: Boolean = False);
    function  Readable(AMSec: Integer = IdTimeoutDefault): Boolean;
    procedure SetBusyUpgrading(const Value: Boolean);
    procedure SetIsWebsocket(const Value: Boolean);
    procedure SetLastActivityTime(const Value: TDateTime);
    procedure SetLastPingTime(const Value: TDateTime);
    procedure SetUseNagle(const Value: Boolean);
    function  TryLock: Boolean;
    procedure Unlock;
    procedure Write(const AOut: string; AEncoding: TIdTextEncoding = nil);
    function  WriteData(aData: TIdBytes; aType: TWSDataCode;
                        aFIN: boolean = true; aRSV1: boolean = false; aRSV2: boolean = false; aRSV3: boolean = false): integer;
    procedure WriteLn(AEncoding: IIdTextEncoding = nil); overload;
    procedure WriteLn(const AOut: string; AByteEncoding: IIdTextEncoding = nil); overload;

    property  Binding: TIdSocketHandle read GetBinding;
    property  BusyUpgrading: Boolean write SetBusyUpgrading;
    property  ClosedGracefully: Boolean read GetClosedGracefully;
    property  Connected: Boolean read GetConnected;
    property  InputBuffer: TIdBuffer read GetInputBuffer;
    property  IsWebsocket: Boolean read GetIsWebsocket write SetIsWebsocket;
    property  LastActivityTime: TDateTime read GetLastActivityTime write SetLastActivityTime;
    property  LastPingTime: TDateTime read GetLastPingTime write SetLastPingTime;
    property  UseNagle: Boolean write SetUseNagle;
  end;

implementation

end.
