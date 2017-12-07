object frmWebSocketEchoServer: TfrmWebSocketEchoServer
  Left = 0
  Top = 0
  Caption = 'WebSocket Echo Server'
  ClientHeight = 367
  ClientWidth = 613
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object Memo1: TMemo
    Left = 0
    Top = 53
    Width = 605
    Height = 306
    TabOrder = 0
  end
  object Edit1: TEdit
    Left = 4
    Top = 26
    Width = 489
    Height = 21
    TabOrder = 1
    Text = 'Edit1'
  end
  object btnSend: TButton
    Left = 508
    Top = 26
    Width = 93
    Height = 25
    Caption = 'Send'
    TabOrder = 2
    OnClick = btnSendClick
  end
  object cbUseSSL: TCheckBox
    Left = 8
    Top = 3
    Width = 97
    Height = 17
    Caption = 'Use SSL'
    TabOrder = 3
    OnClick = cbUseSSLClick
  end
end
