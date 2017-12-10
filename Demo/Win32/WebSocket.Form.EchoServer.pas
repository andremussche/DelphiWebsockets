unit WebSocket.Form.EchoServer;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, IdWebsocketServer, Vcl.StdCtrls,
  IdServerWebsocketContext;

type
  TfrmWebSocketEchoServer = class(TForm)
    Memo1: TMemo;
    Edit1: TEdit;
    btnSend: TButton;
    cbUseSSL: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure cbUseSSLClick(Sender: TObject);
  private
    { Private declarations }
    FServer: TIdWebsocketServer;
    procedure OnMessageText(const AContext: TIdServerWSContext; const aText: string);
    procedure CreateServer;
    procedure SetSSLOptions;
    procedure ActivateServer;
  public
    { Public declarations }
  end;

var
  frmWebSocketEchoServer: TfrmWebSocketEchoServer;

implementation
uses
  IdWebsocketServerSSL, IdServerIOHandler, IdSSLOpenSSL, IdIOHandler;

{$R *.dfm}

procedure TfrmWebSocketEchoServer.ActivateServer;
begin
  FServer.DefaultPort := 2345;
  FServer.OnMessageText := OnMessageText;
  FServer.Active := True;
end;

procedure TfrmWebSocketEchoServer.btnSendClick(Sender: TObject);
var
  I: Integer;
  LList: TList;
  LContext: TIdServerWSContext;
  LText: string;
begin
  LText := Edit1.Text;
  LList := FServer.Contexts.LockList;
  try
    for I := 0 to LList.Count - 1 do
    begin
      LContext := TIdServerWSContext(LList[I]);
      Assert(LContext is TIdServerWSContext);
      if LContext.IOHandler.IsWebsocket and not LContext.IsSocketIO then
        LContext.IOHandler.Write(LText);
    end;
  finally
    FServer.Contexts.UnlockList;
  end;
end;

procedure TfrmWebSocketEchoServer.cbUseSSLClick(Sender: TObject);
begin
  CreateServer;
  ActivateServer;
end;

procedure TfrmWebSocketEchoServer.CreateServer;
begin
  if Assigned(FServer) then
    FServer.Free;
  if cbUseSSL.Checked then
    FServer := TIdWebSocketServerSSL.Create(nil) else
    FServer := TIdWebsocketServer.Create(nil);
  SetSSLOptions;
end;

procedure TfrmWebSocketEchoServer.FormCreate(Sender: TObject);
begin
  CreateServer;
  ActivateServer;
end;

procedure TfrmWebSocketEchoServer.FormDestroy(Sender: TObject);
begin
  FServer.Free;
end;

procedure TfrmWebSocketEchoServer.OnMessageText(const AContext: TIdServerWSContext;
  const aText: string);
begin
  TThread.Synchronize(nil, procedure begin
    Memo1.Lines.Add(aText);
  end);
end;

procedure TfrmWebSocketEchoServer.SetSSLOptions;
var
  LIOHandler: TIdServerIOHandlerSSLOpenSSL;
begin
  if FServer.IOHandler is TIdServerIOHandlerSSLOpenSSL then
    begin
      LIOHandler := TIdServerIOHandlerSSLOpenSSL(FServer.IOHandler);

      LIOHandler.SSLOptions.CertFile := '';  // set this, or SSL won't work!!!
      LIOHandler.SSLOptions.KeyFile := '';   // set this, or SSL won't work!!!
      LIOHandler.SSLOptions.Method := sslvSSLv23;
      LIOHandler.SSLOptions.SSLVersions := [sslvSSLv2, sslvSSLv3, sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2];
      LIOHandler.SSLOptions.Mode := sslmServer;
      LIOHandler.SSLOptions.VerifyMode := [TIdSSLVerifyMode.sslvrfPeer];
      LIOHandler.SSLOptions.VerifyDepth := 0;

    end;
end;

end.
