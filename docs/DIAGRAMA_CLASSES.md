# YAKKO AI - DIAGRAMA DE CLASSES

## Visao Completa Por Dominios

```mermaid
classDiagram

namespace "APLICACAO / ORQUESTRACAO" {
  class TYakkoAgente {
    +Active: Boolean
    +AutoInitialize: Boolean
    +Engine: TYakkoEngine
    +InitializeAgent()
    +FinalizeAgent()
    +RestartSession()
    +Ask(APrompt, AMaxTokens) string
  }

  class TYakkoEngine {
    +Paths: TYakkoPaths
    +Config: TYakkoInferenceConfig
    +FullExports: TYakkoFullExports
    +Modelo: TYakkoModelo
    +ChatTemplate: TYakkoChatTemplate
    +Tokenizer: TYakkoTokenizer
    +Contexto: TYakkoContexto
    +Sessao: TYakkoSessao
    +ToolManager: TYakkoToolManager
    +MemoryManager: TYakkoMemoryManager
    +Gerador: TYakkoGerador
    +Chat: TYakkoChat
    +ContextAssembler: TYakkoContextAssembler
    +NovaChat() TYakkoChat
    +SincronizarPathsModelo()
  }

  class TYakkoGerador {
    +Modelo: TYakkoModelo
    +Contexto: TYakkoContexto
    +Sessao: TYakkoSessao
    +ChatTemplate: TYakkoChatTemplate
    +Tokenizer: TYakkoTokenizer
    +ToolManager: TYakkoToolManager
    +Config: TYakkoInferenceConfig
    +Gerar(APrompt, AMaxTokens) string
    +GerarComMensagens(...) string
    +EstimarTokensComMensagens(...) Integer
    +ContextoDisponivel() Integer
    +ResetarContexto()
    +CancelarGeracao()
  }

  class TYakkoChat {
    +Gerador: TYakkoGerador
    +MemoryManager: TYakkoMemoryManager
    +ContextAssembler: TYakkoContextAssembler
    +Config: TYakkoInferenceConfig
    +Perguntar(APrompt, AMaxTokens) string
    +ReiniciarSessao()
    +LimparHistorico()
    +EstimarTokensSessao() Integer
  }

  class TYakkoMemoryManager {
    +Tokenizer: TYakkoTokenizer
    +ChatTemplate: TYakkoChatTemplate
    +Gerador: TYakkoGerador
    +Config: TYakkoInferenceConfig
    +EstimarUsoContexto(...) Integer
    +DeveResumir(...) Boolean
    +ResumirHistorico(...) Boolean
    +AjustarContexto(...)
  }

  class TYakkoToolManager {
    +Parser: IYakkoToolCallParser
    +RegistrarTool(ATool)
    +EncontrarTool(ANome) TYakkoTool
    +ExecutarToolCall(AToolCall) TYakkoToolResult
    +TryParseToolCall(ARawPayload, out AToolCall) Boolean
  }

  class TYakkoTool {
    +Enabled: Boolean
    +Nome() string
    +Descricao() string
    +Execute(AParametrosJson) string
  }

  class TYakkoJsonToolParser {
    +TryParse(ARawPayload, out AToolCall) Boolean
  }
}

namespace "SESSAO / CONTEXTO / CONFIG" {
  class TYakkoPaths {
    +Dlls: string
    +Modelos: string
    +ModeloEmbeddings: string
  }

  class TYakkoInferenceConfig {
    +MaxTokens: Integer
    +NCtx: Integer
    +Threads: Integer
    +AutoResumo: Boolean
    +AutoResumoLimiar: Double
    +AutoResumoMaxTokens: Integer
    +AutoResumoMensagensRecentes: Integer
    +UseThinkMode: Boolean
    +ShowThinkBlocks: Boolean
    +SanitizeOutput: Boolean
  }

  class TYakkoSamplingParams {
    +Temperature: Single
    +TopK: Integer
    +TopP: Single
    +Seed: Cardinal
    +ResetToDefaults()
  }

  class TYakkoContexto {
    +Modelo: TYakkoModelo
    +Config: TYakkoInferenceConfig
    +NCtxPadrao: Cardinal
    +Abrir(ACtxSize, AThreads)
    +Fechar()
    +EstaAberto: Boolean
    +NCtx() Cardinal
    +NThreads() Int32
  }

  class TYakkoSessao {
    +Contexto: TYakkoContexto
    +Config: TYakkoInferenceConfig
    +Chat: TComponent
    +SessaoAtiva: Boolean
    +KVCacheValido: Boolean
    +EmGeracao: Boolean
    +ResetarSessao()
    +LimparKVCache()
    +MarcarGeracaoIniciada()
    +MarcarGeracaoFinalizada(AGerouTokens)
  }
}

namespace "MODELO / BACKEND" {
  class TYakkoFullExports {
    +DllPath: string
    +Carregado: Boolean
    +Carregar(ACaminho)
    +Descarregar()
    +EstaCarregado() Boolean
  }

  class TYakkoDll {
    +Caminho: string
    +Carregar(ACaminho)
    +Descarregar()
    +EstaCarregado() Boolean
  }

  class TYakkoModelo {
    +DllPath: string
    +ModelPath: string
    +GpuLayersPadrao: Integer
    +FullExports: TYakkoFullExports
    +Handle: TLlamaModelHandle
    +Vocab: TLlamaVocabHandle
    +Carregar(ACaminho, AGpuLayers)
    +Descarregar()
    +EstaCarregado() Boolean
    +NCtxTrain() Integer
    +NEmbedding() Integer
    +Descricao() string
  }

  class TYakkoChatTemplate {
    +Modelo: TYakkoModelo
    +BuildPrompt(...)
    +BuildPromptFromLegacy(...)
    +PodeMontarPrompt() Boolean
  }

  class TYakkoTokenizer {
    +Modelo: TYakkoModelo
    +CountTokens(ATexto) Integer
    +Tokenize(ATexto) TLlamaTokenArray
    +Detokenize(ATokens) string
    +TruncateToFit(ATexto, AMaxTokens) string
  }
}

namespace "ORQUESTRACAO DE INFERENCIA" {
  class TYakkoContextAssembler {
    +BuildPrompt(ARequest) string
    +BuildSystemPrompt(ARequest) string
    +BuildMessages(ARequest) TArray~TLlamaMensagem~
    +Assemble(ARequest) TYakkoAssembledContext
  }

  class TYakkoInferenceRequestOrch {
    +Mode: TYakkoInferenceMode
    +Prompt: string
    +SystemPrompt: string
    +Messages: TArray~TLlamaMensagem~
    +RetrievedContext: string
    +MaxTokens: Integer
    +AddRetrievedChunk(AChunk)
    +ClearRetrievedChunks()
    +Validate()
  }

  class TYakkoRetrievedChunk {
    +SourceId: string
    +Content: string
    +Score: Double
    +Metadata: TDictionary~string,string~
  }

  class TYakkoBasePipeline {
    +SupportsMode(AMode) Boolean
  }

  class TYakkoChatPipeline
  class TYakkoRAGPipeline
  class TYakkoAgentPipeline
  class TYakkoEmbeddingPipeline
}

namespace "EVENTOS / PIPELINE RUNTIME" {
  class TYakkoGenerationEvents {
    +OnToken
    +OnFinished
    +OnError
    +OnCancelled
    +OnStatistics
    +OnReasoningToken
    +OnToolCall
    +Clear()
  }

  class TYakkoCancellationToken {
    +Cancel()
    +Reset()
    +IsCancelled() Boolean
  }

  class TYakkoInferencePipeline {
    +PipelineAtiva: Boolean
    +StageAtual: TYakkoInferenceStage
    +PodeExecutar() Boolean
    +Executar(ARequest) TYakkoInferenceResult
  }

  class TYakkoInferenceRequestGen {
    +Prompt: string
    +PromptSistema: string
    +Mensagens: TArray~TLlamaMensagem~
    +MaxTokens: Integer
    +Config: TYakkoInferenceConfig
    +Sessao: TYakkoSessao
    +ToolManager: TYakkoToolManager
  }

  class TYakkoInferenceResult {
    +TextoGerado: string
    +Stats: TYakkoGenerationStats
    +Cancelado: Boolean
    +Falhou: Boolean
  }
}

namespace "RAG / APLICACAO VCL" {
  class TYakkoStudioMainForm {
    +YakkoEngine1: TYakkoEngine
    +YakkoAgente1: TYakkoAgente
    +YakkoGerador1: TYakkoGerador
    +YakkoModelo1: TYakkoModelo
    +YakkoDll1: TYakkoDll
    +YakkoPaths1: TYakkoPaths
    +YakkoContexto1: TYakkoContexto
    +YakkoChat1: TYakkoChat
    +YakkoFullExports1: TYakkoFullExports
    +BtnInicializarClick()
    +BtnPerguntarAgenteClick()
    +BtnPerguntarChatClick()
    +BtnRagModalClick()
    +RunCliRagTestIfRequested()
  }

  class TYakkoStudioRagModalForm {
    +Engine: TYakkoEngine
    +EmbeddingModelPath: string
    +ExecuteRagOnce(...)
    +BtnGerarEmbeddingsClick()
    +BtnPerguntarClick()
    +ComputeEmbedding(AText, AIsQuery) TArray~Single~
    +BuildContextFromTopK(...)
  }

  class TYakkoVectorStoreSQLite {
    +Create(ADatabasePath)
    +DeleteSourceChunks(ASourceFile)
    +SaveChunk(ASourceFile, AChunkIndex, AContent, AVector)
    +SearchSimilar(AQueryVector, ATopK, AQueryText, ASourceFilters, AMinSimilaridade)
    +HasRealVectorBackend() Boolean
  }

  class TToolHoraAtual {
    +Nome() string
    +Descricao() string
    +Execute(AParametrosJson) string
  }
}

namespace "DESIGN-TIME (IDE)" {
  class TYakkoBaseFolderProperty {
    +GetAttributes() TPropertyAttributes
    +Edit()
    +GetDialogTitle() string
  }

  class TYakkoDllsFolderProperty
  class TYakkoModelosFolderProperty
  class TYakkoModelPathListProperty {
    +GetAttributes() TPropertyAttributes
    +GetValues(Proc)
    +SetValue(Value)
  }
}

TYakkoInferenceConfig *-- TYakkoSamplingParams : composicao

TYakkoEngine o-- TYakkoPaths : agregacao
TYakkoEngine *-- TYakkoInferenceConfig : composicao
TYakkoEngine *-- TYakkoFullExports : composicao
TYakkoEngine o-- TYakkoModelo : agregacao
TYakkoEngine o-- TYakkoChatTemplate : agregacao
TYakkoEngine o-- TYakkoTokenizer : agregacao
TYakkoEngine o-- TYakkoContexto : agregacao
TYakkoEngine o-- TYakkoSessao : agregacao
TYakkoEngine o-- TYakkoToolManager : agregacao
TYakkoEngine o-- TYakkoMemoryManager : agregacao
TYakkoEngine o-- TYakkoGerador : agregacao
TYakkoEngine o-- TYakkoChat : agregacao
TYakkoEngine o-- TYakkoContextAssembler : agregacao

TYakkoModelo --> TYakkoFullExports : usa backend
TYakkoDll ..> TYakkoFullExports : dependencia
TYakkoChatTemplate --> TYakkoModelo : associacao
TYakkoTokenizer --> TYakkoModelo : associacao
TYakkoContexto --> TYakkoModelo : associacao
TYakkoContexto --> TYakkoInferenceConfig : associacao
TYakkoSessao --> TYakkoContexto : associacao
TYakkoSessao --> TYakkoInferenceConfig : associacao

TYakkoToolManager *-- TYakkoTool : composicao
TYakkoToolManager --> TYakkoJsonToolParser : associacao

TYakkoGerador *-- TYakkoGenerationEvents : composicao
TYakkoGerador *-- TYakkoCancellationToken : composicao
TYakkoGerador *-- TYakkoInferencePipeline : composicao
TYakkoGerador --> TYakkoModelo : associacao
TYakkoGerador --> TYakkoContexto : associacao
TYakkoGerador --> TYakkoSessao : associacao
TYakkoGerador --> TYakkoChatTemplate : associacao
TYakkoGerador --> TYakkoTokenizer : associacao
TYakkoGerador --> TYakkoToolManager : associacao
TYakkoGerador --> TYakkoInferenceConfig : associacao

TYakkoMemoryManager --> TYakkoTokenizer : associacao
TYakkoMemoryManager --> TYakkoChatTemplate : associacao
TYakkoMemoryManager --> TYakkoGerador : associacao
TYakkoMemoryManager --> TYakkoInferenceConfig : associacao

TYakkoChat --> TYakkoGerador : associacao
TYakkoChat --> TYakkoMemoryManager : associacao
TYakkoChat --> TYakkoContextAssembler : associacao
TYakkoChat --> TYakkoInferenceConfig : associacao

TYakkoInferenceRequestOrch *-- TYakkoRetrievedChunk : composicao
TYakkoContextAssembler ..> TYakkoInferenceRequestOrch : dependencia

TYakkoChatPipeline --|> TYakkoBasePipeline
TYakkoRAGPipeline --|> TYakkoBasePipeline
TYakkoAgentPipeline --|> TYakkoBasePipeline
TYakkoEmbeddingPipeline --|> TYakkoBasePipeline

TYakkoInferencePipeline ..> TYakkoInferenceRequestGen : dependencia
TYakkoInferencePipeline ..> TYakkoInferenceResult : dependencia

TToolHoraAtual --|> TYakkoTool
TYakkoStudioMainForm --> TYakkoAgente : associacao
TYakkoStudioMainForm --> TYakkoEngine : associacao
TYakkoStudioMainForm --> TYakkoGerador : associacao
TYakkoStudioMainForm --> TYakkoModelo : associacao
TYakkoStudioMainForm --> TYakkoDll : associacao
TYakkoStudioMainForm --> TYakkoPaths : associacao
TYakkoStudioMainForm --> TYakkoContexto : associacao
TYakkoStudioMainForm --> TYakkoChat : associacao
TYakkoStudioMainForm --> TYakkoFullExports : associacao
TYakkoStudioMainForm --> TYakkoStudioRagModalForm : associacao
TYakkoStudioRagModalForm --> TYakkoEngine : associacao
TYakkoStudioRagModalForm o-- TYakkoVectorStoreSQLite : agregacao
TYakkoStudioRagModalForm --> TYakkoFullExports : associacao
TYakkoStudioRagModalForm --> TYakkoModelo : associacao
TYakkoStudioRagModalForm --> TYakkoContexto : associacao

TYakkoDllsFolderProperty --|> TYakkoBaseFolderProperty
TYakkoModelosFolderProperty --|> TYakkoBaseFolderProperty
TYakkoDllsFolderProperty ..> TYakkoPaths : dependencia
TYakkoModelosFolderProperty ..> TYakkoPaths : dependencia
TYakkoModelPathListProperty ..> TYakkoPaths : dependencia
```
