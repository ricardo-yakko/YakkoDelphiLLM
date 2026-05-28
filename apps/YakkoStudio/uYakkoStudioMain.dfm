object Form1: TYakkoStudioMainForm
  Left = 0
  Top = 0
  Caption = 'Yakko - Demo Completo'
  ClientHeight = 700
  ClientWidth = 1120
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnClose = FormClose
  OnCreate = FormCreate
  TextHeight = 15
  object LbSistema: TLabel
    Left = 16
    Top = 16
    Width = 99
    Height = 15
    Caption = 'Prompt de sistema'
  end
  object LbPrompt: TLabel
    Left = 16
    Top = 190
    Width = 93
    Height = 15
    Caption = 'Pergunta/Prompt'
  end
  object LbTemplatePersona: TLabel
    Left = 16
    Top = 139
    Width = 95
    Height = 15
    Caption = 'Template de perfil'
  end
  object LbSaida: TLabel
    Left = 560
    Top = 16
    Width = 87
    Height = 15
    Caption = 'Saida/Streaming'
  end
  object LbNCtx: TLabel
    Left = 16
    Top = 326
    Width = 26
    Height = 15
    Caption = 'NCtx'
  end
  object LbMaxTokens: TLabel
    Left = 128
    Top = 326
    Width = 59
    Height = 15
    Caption = 'MaxTokens'
  end
  object LbTemperatura: TLabel
    Left = 256
    Top = 326
    Width = 67
    Height = 15
    Caption = 'Temperatura'
  end
  object LbTopK: TLabel
    Left = 376
    Top = 326
    Width = 27
    Height = 15
    Caption = 'TopK'
  end
  object LbTopP: TLabel
    Left = 464
    Top = 326
    Width = 27
    Height = 15
    Caption = 'TopP'
  end
  object LbInteracoes: TLabel
    Left = 16
    Top = 496
    Width = 54
    Height = 15
    Caption = 'Interacoes'
  end
  object LbDelayMs: TLabel
    Left = 128
    Top = 496
    Width = 56
    Height = 15
    Caption = 'Delay (ms)'
  end
  object LbStatus: TLabel
    Left = 16
    Top = 668
    Width = 102
    Height = 15
    Caption = 'Status: aguardando'
  end
  object MemoSistema: TMemo
    Left = 16
    Top = 37
    Width = 520
    Height = 96
    TabOrder = 0
  end
  object MemoPrompt: TMemo
    Left = 16
    Top = 211
    Width = 520
    Height = 144
    TabOrder = 1
  end
  object CbTemplatePersona: TComboBox
    Left = 16
    Top = 160
    Width = 520
    Height = 23
    Style = csDropDownList
    TabOrder = 2
    OnChange = CbTemplatePersonaChange
  end
  object MemoSaida: TMemo
    Left = 560
    Top = 37
    Width = 544
    Height = 646
    ScrollBars = ssVertical
    TabOrder = 3
  end
  object EdNCtx: TEdit
    Left = 16
    Top = 347
    Width = 97
    Height = 23
    TabOrder = 4
    Text = '4096'
  end
  object EdMaxTokens: TEdit
    Left = 128
    Top = 347
    Width = 105
    Height = 23
    TabOrder = 5
    Text = '512'
  end
  object EdTemperatura: TEdit
    Left = 256
    Top = 347
    Width = 97
    Height = 23
    TabOrder = 6
    Text = '0.7'
  end
  object EdTopK: TEdit
    Left = 376
    Top = 347
    Width = 73
    Height = 23
    TabOrder = 7
    Text = '40'
  end
  object EdTopP: TEdit
    Left = 464
    Top = 347
    Width = 73
    Height = 23
    TabOrder = 8
    Text = '0.95'
  end
  object CkUseThink: TCheckBox
    Left = 16
    Top = 384
    Width = 145
    Height = 17
    Caption = 'UseThinkMode'
    TabOrder = 9
  end
  object CkSanitize: TCheckBox
    Left = 176
    Top = 384
    Width = 169
    Height = 17
    Caption = 'SanitizeOutput'
    Checked = True
    State = cbChecked
    TabOrder = 10
  end
  object BtnInicializar: TButton
    Left = 16
    Top = 420
    Width = 125
    Height = 30
    Caption = 'Inicializar'
    TabOrder = 11
    OnClick = BtnInicializarClick
  end
  object BtnFinalizar: TButton
    Left = 152
    Top = 420
    Width = 125
    Height = 30
    Caption = 'Finalizar'
    TabOrder = 12
    OnClick = BtnFinalizarClick
  end
  object BtnPerguntarAgente: TButton
    Left = 288
    Top = 420
    Width = 125
    Height = 30
    Caption = 'Perguntar Agente'
    TabOrder = 13
    OnClick = BtnPerguntarAgenteClick
  end
  object BtnPerguntarChat: TButton
    Left = 424
    Top = 420
    Width = 113
    Height = 30
    Caption = 'Perguntar Chat'
    TabOrder = 14
    OnClick = BtnPerguntarChatClick
  end
  object BtnCancelar: TButton
    Left = 16
    Top = 460
    Width = 125
    Height = 30
    Caption = 'Cancelar Geracao'
    TabOrder = 15
    OnClick = BtnCancelarClick
  end
  object BtnReiniciarSessao: TButton
    Left = 152
    Top = 460
    Width = 125
    Height = 30
    Caption = 'Reiniciar Sessao'
    TabOrder = 16
    OnClick = BtnReiniciarSessaoClick
  end
  object EdInteracoes: TEdit
    Left = 16
    Top = 517
    Width = 97
    Height = 23
    TabOrder = 17
    Text = '4'
  end
  object EdDelayMs: TEdit
    Left = 128
    Top = 517
    Width = 97
    Height = 23
    TabOrder = 18
    Text = '10000'
  end
  object BtnSimularConversa: TButton
    Left = 240
    Top = 513
    Width = 173
    Height = 30
    Caption = 'Simular Comprador x Vendedor'
    TabOrder = 19
    OnClick = BtnSimularConversaClick
  end
  object BtnTestarTool: TButton
    Left = 288
    Top = 460
    Width = 125
    Height = 30
    Caption = 'Testar Tool'
    TabOrder = 20
    OnClick = BtnTestarToolClick
  end
  object YakkoAgente1: TYakkoAgente
    Engine = YakkoEngine1
    NCtxPadrao = 512
    MaxTokensPadrao = 64
    Temperatura = 0.699999988079071000
    TopP = 0.949999988079071000
    Left = 312
    Top = 96
  end
  object YakkoModelo1: TYakkoModelo
    DllPath = 
      'C:\Users\Yakko\Documents\harmonica.io\dlls\llama-b9012-bin-win-c' +
      'uda-13.1-x64'
    ModelPath = 'C:\Users\Yakko\Documents\harmonica.io\models\phi-4-Q5_K_M.gguf'
    GpuLayersPadrao = 999
    Left = 224
    Top = 152
  end
  object YakkoGerador1: TYakkoGerador
    Left = 152
    Top = 32
  end
  object YakkoEngine1: TYakkoEngine
    Paths = YakkoPaths1
    Config.AutoResumoLimiar = 0.700000000000000000
    Modelo = YakkoModelo1
    Contexto = YakkoContexto1
    Gerador = YakkoGerador1
    Chat = YakkoChat1
    Left = 232
    Top = 24
  end
  object YakkoDll1: TYakkoDll
    Left = 496
    Top = 168
  end
  object YakkoPaths1: TYakkoPaths
    Dlls = 
      'C:\Users\Yakko\Documents\harmonica.io\dlls\llama-b9012-bin-win-c' +
      'uda-13.1-x64'
    Modelos = 'C:\Users\Yakko\Documents\harmonica.io\models'
    Left = 112
    Top = 160
  end
  object YakkoContexto1: TYakkoContexto
    Modelo = YakkoModelo1
    Config.AutoResumoLimiar = 0.700000000000000000
    Left = 392
    Top = 8
  end
  object YakkoChat1: TYakkoChat
    Gerador = YakkoGerador1
    Config.AutoResumoLimiar = 0.700000000000000000
    Left = 72
    Top = 32
  end
  object YakkoFullExports1: TYakkoFullExports
    DllPath = 
      'C:\Users\Yakko\Documents\harmonica.io\dlls\llama-b9012-bin-win-c' +
      'uda-13.1-x64'
    Left = 440
    Top = 240
  end
end


