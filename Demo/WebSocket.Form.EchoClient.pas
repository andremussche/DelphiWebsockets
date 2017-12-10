unit WebSocket.Form.EchoClient;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.Generics.Collections,
  IdHTTPWebsocketClient;

type
  TForm3 = class(TForm)
    Memo1: TMemo;
    Edit1: TEdit;
    Button2: TButton;
    procedure Button2Click(Sender: TObject);
  private
    FWebSocketClient: TIdHTTPWebsocketClient;
    { Private declarations }
    function CreateWebSocketClient: TIdHTTPWebsocketClient;
    procedure OnWebSocketBinData(const aData: TStream);
    procedure OnWebSocketTextData(const aData: string);
    procedure EnsureConnected(const AWSClient: TIdHTTPWebsocketClient);
  public
    { Public declarations }
  end;

var
  Form3: TForm3;

implementation
uses
  IdHTTP;

{$R *.dfm}

procedure TForm3.Button2Click(Sender: TObject);
begin
  if not Assigned(FWebSocketClient) then
    FWebSocketClient := CreateWebSocketClient;
  if not FWebSocketClient.Connected then
    begin
      FWebSocketClient.Connect;
      FWebSocketClient.UpgradeToWebsocket;
    end;
  FWebSocketClient.IOHandler.Write(Edit1.Text);
  Edit1.Text := '';
end;

function TForm3.CreateWebSocketClient: TIdHTTPWebsocketClient;
begin
  Result := TIdHTTPWebsocketClient.Create(nil);
  Result.Request.UserAgent := 'Mozilla/5.0+(Windows+NT+6.1;+Win64;+x64;+rv:57.0)+Gecko/20100101+Firefox/57.0';
  // Potential disconnect if hoKeepOrigProtocol is not added
  // Only affects Post, not Get
  Result.HTTPOptions := Result.HTTPOptions + [hoKeepOrigProtocol];

  // for verification using Fiddler
//  Result.ProxyParams.ProxyPort := 8888;
//  Result.ProxyParams.ProxyServer := '127.0.0.1';

  Result.HandleRedirects := True;
  Result.Host := 'localhost';
  Result.Port := 2345;
  Result.OnTextData := OnWebSocketTextData;
end;

procedure TForm3.EnsureConnected(const AWSClient: TIdHTTPWebsocketClient);
begin
  if not AWSClient.Connected then
    begin
      AWSClient.Connect;
      AWSClient.UpgradeToWebsocket;
    end;
end;

procedure TForm3.OnWebSocketBinData(const aData: TStream);
begin
end;

procedure TForm3.OnWebSocketTextData(const aData: string);
begin
  TThread.Synchronize(nil, procedure
  var EM: string;
  begin
    try
      Memo1.Lines.Add(aData);
    except
      on E: Exception do
        EM := E.Message;
    end;
  end);

end;

end.
