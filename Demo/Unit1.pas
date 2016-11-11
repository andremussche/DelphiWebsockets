unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  IdServerWebsocketContext;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Timer1: TTimer;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    procedure ServerMessageTextReceived(const AContext: TIdServerWSContext; const aText: string);
    procedure ClientBinDataReceived(const aData: TStream);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  IdWebsocketServer, IdHTTPWebsocketClient, superobject, IdSocketIOHandling,
  IdIOHandlerWebsocket;

var
  server: TIdWebsocketServer;
  client: TIdHTTPWebsocketClient;

const
  C_CLIENT_EVENT = 'CLIENT_TO_SERVER_EVENT_TEST';
  C_SERVER_EVENT = 'SERVER_TO_CLIENT_EVENT_TEST';

procedure ShowMessageInMainthread(const aMsg: string) ;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      ShowMessage(aMsg);
    end);
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  server := TIdWebsocketServer.Create(Self);
  server.DefaultPort := 12345;
  server.SocketIO.OnEvent(C_CLIENT_EVENT,
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallback: ISocketIOCallback)
    begin
      //show request (threadsafe)
      ShowMessageInMainthread('REQUEST: ' + aArgument[0].AsJSon);
      //send callback (only if specified!)
      if aCallback <> nil then
        aCallback.SendResponse( SO(['succes', True]).AsJSon );
    end);
  server.Active      := True;

  client := TIdHTTPWebsocketClient.Create(Self);
  client.Port := 12345;
  client.Host := 'localhost';
  client.SocketIOCompatible := True;
  client.SocketIO.OnEvent(C_SERVER_EVENT,
    procedure(const ASocket: ISocketIOContext; const aArgument: TSuperArray; const aCallback: ISocketIOCallback)
    begin
      ShowMessageInMainthread('Data PUSHED from server: ' + aArgument[0].AsJSon);
      //server wants a response?
      if aCallback <> nil then
        aCallback.SendResponse('thank for the push!');
    end);
  client.Connect;
  client.SocketIO.Emit(C_CLIENT_EVENT, SO([ 'request', 'some data']),
    //provide callback
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
      //show response (threadsafe)
      ShowMessageInMainthread('RESPONSE: ' + aJSON.AsJSon);
    end);

  //start timer so server pushes (!) data to all clients
  Timer1.Interval := 5 * 1000; //5s
//  Timer1.Enabled  := True;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  client.Free;
  server.Free;

  server := TIdWebsocketServer.Create(Self);
  server.DefaultPort := 12346;
  server.Active      := True;

  client := TIdHTTPWebsocketClient.Create(Self);
  client.Port := 12346;
  client.Host := 'localhost';
  client.Connect;
  client.UpgradeToWebsocket;

  client.OnBinData     := ClientBinDataReceived;
  server.OnMessageText := ServerMessageTextReceived;
  client.IOHandler.Write('test');
end;

procedure TForm1.ClientBinDataReceived(const aData: TStream);
begin
  //
end;

procedure TForm1.ServerMessageTextReceived(const AContext: TIdServerWSContext; const aText: string);
var
  strm: TStringStream;
begin
  ShowMessageInMainthread('WS REQUEST: ' + aText);
  strm := TStringStream.Create('SERVER: ' + aText);
  AContext.IOHandler.Write(strm, wdtBinary);
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  Timer1.Enabled := false;
  server.SocketIO.EmitEventToAll(C_SERVER_EVENT, SO(['data', 'pushed from server']),
    procedure(const ASocket: ISocketIOContext; const aJSON: ISuperObject; const aCallback: ISocketIOCallback)
    begin
        //show response (threadsafe)
        TThread.Synchronize(nil,
          procedure
          begin
            ShowMessage('RESPONSE from a client: ' + aJSON.AsJSon);
          end);
    end);
end;

end.
