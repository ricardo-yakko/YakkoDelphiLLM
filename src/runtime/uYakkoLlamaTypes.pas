unit uYakkoLlamaTypes;

{ Tipos compartilhados entre todas as units uYakkoLLM.
  Nenhuma dependencia externa - pode ser usado por qualquer camada. }

interface

type
  { Handles opacos da C API llama.cpp }
  TLlamaModelHandle    = Pointer;
  TLlamaVocabHandle    = Pointer;
  TLlamaContextoHandle = Pointer;
  TLlamaSamplerHandle  = Pointer;

  { Tipos de tokens }
  TLlamaToken      = Int32;
  PLlamaToken      = ^TLlamaToken;
  TLlamaTokenArray = array of TLlamaToken;

  { Mensagens de conversa }
  TLlamaMensagemRole = (mrSystem, mrUser, mrAssistant);

  TLlamaMensagem = record
    Role    : TLlamaMensagemRole;
    Conteudo: string;
  end;

  { Callback de streaming de tokens }
  TLlamaTextoParcialProc = reference to procedure(const ATexto: string);

implementation

end.

