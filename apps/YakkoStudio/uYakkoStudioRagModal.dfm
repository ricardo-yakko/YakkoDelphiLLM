object YakkoStudioRagModalForm: TYakkoStudioRagModalForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'RAG com Embeddings'
  ClientHeight = 700
  ClientWidth = 980
  Color = 15527148
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 13
  object LbArquivos: TLabel
    Left = 16
    Top = 12
    Width = 112
    Height = 13
    Caption = 'Arquivos para indexar'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LbPergunta: TLabel
    Left = 496
    Top = 12
    Width = 161
    Height = 13
    Caption = 'Pergunta sobre os embeddings'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object LbTopK: TLabel
    Left = 20
    Top = 300
    Width = 24
    Height = 13
    Caption = 'TopK'
  end
  object LbMaxTokens: TLabel
    Left = 114
    Top = 300
    Width = 56
    Height = 13
    Caption = 'MaxTokens'
  end
  object LbStatus: TLabel
    Left = 16
    Top = 620
    Width = 102
    Height = 13
    Caption = 'Status: aguardando'
  end
  object MemoArquivos: TMemo
    Left = 16
    Top = 32
    Width = 460
    Height = 220
    Color = clWhite
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object MemoPergunta: TMemo
    Left = 496
    Top = 32
    Width = 460
    Height = 120
    Color = clWhite
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    Lines.Strings = (
      
        'Qual TV foi mencionada e qual faixa de preco aparece nos arquivo' +
        's?')
    ScrollBars = ssVertical
    TabOrder = 1
  end
  object MemoResposta: TMemo
    Left = 496
    Top = 200
    Width = 460
    Height = 444
    Color = 16776186
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 2
  end
  object BtnSelecionarArquivos: TButton
    Left = 16
    Top = 262
    Width = 145
    Height = 28
    Caption = 'Selecionar Arquivos'
    TabOrder = 3
    OnClick = BtnSelecionarArquivosClick
  end
  object BtnGerarEmbeddings: TButton
    Left = 172
    Top = 262
    Width = 145
    Height = 28
    Caption = 'Gerar Embeddings'
    TabOrder = 4
    OnClick = BtnGerarEmbeddingsClick
  end
  object BtnPerguntar: TButton
    Left = 496
    Top = 162
    Width = 145
    Height = 28
    Caption = 'Perguntar (RAG)'
    TabOrder = 5
    OnClick = BtnPerguntarClick
  end
  object BtnFechar: TButton
    Left = 811
    Top = 162
    Width = 145
    Height = 28
    Caption = 'Fechar'
    TabOrder = 6
    OnClick = BtnFecharClick
  end
  object EdTopK: TEdit
    Left = 60
    Top = 296
    Width = 46
    Height = 21
    Color = clWhite
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 7
    Text = '4'
  end
  object EdMaxTokens: TEdit
    Left = 182
    Top = 296
    Width = 62
    Height = 21
    Color = clWhite
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    TabOrder = 8
    Text = '1024'
  end
end
