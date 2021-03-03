object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = #1044#1077#1090#1077#1082#1090#1086#1088' '#1079#1072#1097#1080#1090#1099' Lineage II'
  ClientHeight = 541
  ClientWidth = 784
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Menu = mmMain
  OldCreateOrder = False
  Position = poDesktopCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object lvList: TListView
    Left = 0
    Top = 0
    Width = 784
    Height = 452
    Align = alClient
    Columns = <
      item
        Caption = #1060#1072#1081#1083
        Width = 400
      end
      item
        Caption = #1055#1086#1076#1087#1080#1089#1100
        Width = 200
      end
      item
        Caption = #1047#1072#1097#1080#1090#1072
        Width = 150
      end>
    OwnerDraw = True
    ReadOnly = True
    RowSelect = True
    PopupMenu = pmList
    TabOrder = 0
    ViewStyle = vsReport
    OnDrawItem = lvListDrawItem
  end
  object mmLog: TMemo
    Left = 0
    Top = 452
    Width = 784
    Height = 89
    Align = alBottom
    Lines.Strings = (
      'mmLog')
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object pmList: TPopupMenu
    Left = 328
    Top = 40
    object miProperty: TMenuItem
      Caption = #1057#1074#1086#1081#1089#1090#1074#1072
      OnClick = miPropertyClick
    end
  end
  object mmMain: TMainMenu
    Left = 368
    Top = 40
    object miDriver: TMenuItem
      Caption = #1044#1088#1072#1081#1074#1077#1088#1099
      object miDriverList: TMenuItem
        Caption = #1057#1087#1080#1089#1086#1082
        OnClick = miDriverListClick
      end
      object miSnapshot: TMenuItem
        Caption = #1057#1085#1080#1084#1086#1082
        OnClick = miSnapshotClick
      end
      object miDiff: TMenuItem
        Caption = #1057#1088#1072#1074#1085#1077#1085#1080#1077
        OnClick = miDiffClick
      end
    end
    object miLineage: TMenuItem
      Caption = 'Lineage'
      OnClick = miLineageClick
      object miProcList: TMenuItem
        AutoHotkeys = maManual
        Caption = #1055#1088#1086#1094#1077#1089#1089
      end
      object miCheckSystem: TMenuItem
        Caption = #1057#1082#1072#1085#1077#1088' system'
        OnClick = miCheckSystemClick
      end
    end
    object miHelp: TMenuItem
      Caption = #1055#1086#1084#1086#1097#1100
      object miYManual: TMenuItem
        Caption = #1054#1087#1080#1089#1072#1085#1080#1077' (youtube)'
        OnClick = miYManualClick
      end
      object miManual: TMenuItem
        Caption = #1048#1085#1089#1090#1088#1091#1082#1094#1080#1103
        OnClick = miManualClick
      end
    end
  end
  object dlgPath: TFileOpenDialog
    FavoriteLinks = <>
    FileTypes = <>
    Options = [fdoPickFolders]
    Left = 368
    Top = 112
  end
end
