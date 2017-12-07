object Form3: TForm3
  Left = 0
  Top = 0
  Caption = 'WebSocket client'
  ClientHeight = 290
  ClientWidth = 554
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  DesignSize = (
    554
    290)
  PixelsPerInch = 96
  TextHeight = 13
  object Memo1: TMemo
    Left = 8
    Top = 40
    Width = 545
    Height = 249
    Anchors = [akLeft, akTop, akRight, akBottom]
    TabOrder = 0
  end
  object Edit1: TEdit
    Left = 8
    Top = 8
    Width = 457
    Height = 21
    TabOrder = 1
    Text = 'Edit1'
  end
  object Button2: TButton
    Left = 471
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Send'
    TabOrder = 2
    OnClick = Button2Click
  end
end
