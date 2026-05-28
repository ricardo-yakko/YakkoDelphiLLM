# YakkoDelphiLLM

Biblioteca Delphi para orquestrar inferencia local com backend llama.cpp, com arquitetura baseada em componentes.

Este guia foca em uso real de recursos. Nao apenas inicializar, perguntar e finalizar.

## O que voce consegue fazer

- Conversa com memoria de contexto
- Streaming de tokens em tempo real
- Cancelamento cooperativo
- Configuracao unificada de inferencia
- Ajuste de auto-resumo de historico
- Tool calling com registro de ferramentas customizadas
- Telemetria por eventos de geracao
- Uso em nivel alto (agente) e nivel baixo (engine + chat + gerador)

## Arquitetura em uma frase

TYakkoEngine centraliza ownership e dependencias, TYakkoInferenceConfig centraliza configuracoes, e os demais componentes operam por referencias compartilhadas.

## Estrutura de pastas

- src/runtime: units de runtime da biblioteca
- src/design: units de design-time/registro de componentes
- packages: projetos e pacotes Delphi (dproj/dpk)
- apps/YakkoStudio: app de exemplo e fluxo RAG
- resources: recursos de compilacao (rc/res)
- docs: documentacao

## Padrao de nomenclatura Delphi adotado

As units agora seguem prefixo u, que e um padrao comum em projetos Delphi.

- Runtime: uYakko...
- Design: uYakkoLLMReg
- App: uYakkoStudioMain e uYakkoStudioRagModal

Exemplos:

- uYakkoEngineComponent
- uYakkoInferenceConfigComponent
- uYakkoGeradorComponent
- uYakkoStudioMain
- uYakkoStudioRagModal

## Componentes principais

- TYakkoEngine: orquestrador central
- TYakkoInferenceConfig: configuracao unificada
- TYakkoModelo: carga do modelo
- TYakkoContexto: contexto de inferencia
- TYakkoTokenizer: tokenizacao
- TYakkoGerador: pipeline de inferencia e streaming
- TYakkoChat: historico e conversa
- TYakkoMemoryManager: auto-resumo e ajuste de janela
- TYakkoToolManager: tool calling
- TYakkoAgente: fachada de alto nivel

## Fluxos recomendados

### 1) Fluxo rapido de alto nivel com TYakkoAgente

Use quando voce quer produtividade rapida.

    uses
      uYakkoAgenteComponent,
      uYakkoEngineComponent,
      uYakkoModeloComponent;

    var
      Engine: TYakkoEngine;
      Agente: TYakkoAgente;
      Resposta: string;
    begin
      Engine := TYakkoEngine.Create(nil);
      Agente := TYakkoAgente.Create(nil);
      try
        Engine.Modelo.ModelPath := 'C:\models\seu-modelo.gguf';
        Engine.Modelo.DllPath := 'C:\llama\llama.dll';

        Agente.Engine := Engine;
        Agente.NCtxPadrao := 8192;
        Agente.MaxTokensPadrao := 1024;
        Agente.Temperatura := 0.7;
        Agente.TopK := 40;
        Agente.TopP := 0.95;
        Agente.SystemPrompt := 'Responda de forma objetiva e tecnica.';

        Agente.InitializeAgent;
        try
          Resposta := Agente.Ask('Explique o padrao Strategy em Delphi.');
        finally
          Agente.FinalizeAgent;
        end;
      finally
        Agente.Free;
        Engine.Free;
      end;
    end;

### 2) Fluxo completo com Engine + Chat

Use quando voce quer controle fino de sessao e eventos.

    uses
      uYakkoEngineComponent;

    var
      Engine: TYakkoEngine;
      Texto: string;
    begin
      Engine := TYakkoEngine.Create(nil);
      try
        Engine.Modelo.ModelPath := 'C:\models\seu-modelo.gguf';
        Engine.Modelo.DllPath := 'C:\llama\llama.dll';
        Engine.Modelo.Carregar(Engine.Modelo.ModelPath);

        Engine.Chat.PromptSistema := 'Voce e um assistente Delphi.';

        Texto := Engine.Chat.Perguntar(
          'Crie um exemplo de Factory Method.',
          800,
          procedure(const Token: string)
          begin
            // streaming de token
          end
        );

      finally
        Engine.Modelo.Descarregar;
        Engine.Free;
      end;
    end;

## Configuracao unificada

Toda configuracao principal fica em TYakkoInferenceConfig, acessada por Engine.Config.

### Exemplo de configuracao central

    Engine.Config.NCtx := 8192;
    Engine.Config.MaxTokens := 1200;
    Engine.Config.Threads := 8;

    Engine.Config.Sampling.Temperature := 0.7;
    Engine.Config.Sampling.TopK := 40;
    Engine.Config.Sampling.TopP := 0.95;
    Engine.Config.Sampling.Seed := Cardinal($FFFFFFFF);

    Engine.Config.AutoResumo := True;
    Engine.Config.AutoResumoLimiar := 0.70;
    Engine.Config.AutoResumoMaxTokens := 256;
    Engine.Config.AutoResumoMensagensRecentes := 4;

    Engine.Config.UseThinkMode := False;
    Engine.Config.ShowThinkBlocks := False;
    Engine.Config.SanitizeOutput := True;

## Eventos de geracao e telemetria

Voce pode assinar eventos para logs, UI, metricas e auditoria.

    Engine.Gerador.Events.OnToken :=
      procedure(const T: string)
      begin
        // token parcial
      end;

    Engine.Gerador.Events.OnFinished :=
      procedure(const TextoFinal: string; const Stats: TYakkoGenerationStats)
      begin
        // Stats.PromptTokens, Stats.GeneratedTokens, Stats.TokensPerSecond
      end;

    Engine.Gerador.Events.OnError :=
      procedure(const Msg: string)
      begin
        // tratamento centralizado de erro
      end;

    Engine.Gerador.Events.OnCancelled :=
      procedure(const Parcial: string; const Stats: TYakkoGenerationStats)
      begin
        // cancelamento cooperativo
      end;

    Engine.Gerador.Events.OnToolCall :=
      procedure(const Payload: string)
      begin
        // ciclo de tool call: start, success, failure
      end;

## Cancelamento cooperativo

Para interromper uma geracao em andamento:

    Engine.Gerador.CancelarGeracao;

O pipeline respeita o token de cancelamento e emite OnCancelled.

## Sessao e memoria conversacional

### Reiniciar sessao

    Engine.Chat.ReiniciarSessao;

### Limpar apenas historico

    Engine.Chat.LimparHistorico;

### Inspecao util

- Engine.Chat.QuantidadeMensagens
- Engine.Chat.AutoResumoContagem
- Engine.Chat.EstimarTokensSessao

### Ajuste de auto-resumo

O auto-resumo pode ser afinado via Engine.Config.

- AutoResumo ativa/desativa a funcionalidade
- AutoResumoLimiar define quando resumir com base no budget
- AutoResumoMaxTokens limita o tamanho do resumo
- AutoResumoMensagensRecentes define quantas mensagens recentes preservar

## Tool calling

TYakkoToolManager permite registrar ferramentas customizadas.

### Exemplo de tool customizada

    uses
      System.JSON,
      uYakkoToolManagerComponent;

    type
      TToolHoraAtual = class(TYakkoTool)
      public
        function Nome: string; override;
        function Descricao: string; override;
        function Execute(const AParametrosJson: string): string; override;
      end;

    function TToolHoraAtual.Nome: string;
    begin
      Result := 'hora_atual';
    end;

    function TToolHoraAtual.Descricao: string;
    begin
      Result := 'Retorna data e hora atual em texto.';
    end;

    function TToolHoraAtual.Execute(const AParametrosJson: string): string;
    begin
      Result := DateTimeToStr(Now);
    end;

    // registro
    Engine.ToolManager.RegistrarTool(TToolHoraAtual.Create);

### Observacoes

- ToolManager e owner das tools registradas
- Payload de tool call e parseado por estrategia (parser)
- Resultado vem estruturado com sucesso/erro

## Uso de baixo nivel sem Chat

Para workloads mais controlados, voce pode chamar o gerador diretamente.

    var
      Texto: string;
    begin
      Texto := Engine.Gerador.GerarComMensagens(
        'Resuma este texto em 5 pontos.',
        'Seja tecnico e objetivo.',
        [],
        400,
        nil
      );
    end;

## Padroes de erro e validacao

A biblioteca usa excecoes especificas por componente, por exemplo:

- ELlamaModeloError
- ELlamaContextoError
- ELlamaGeradorError
- EYakkoInferenceConfigError
- EYakkoSamplingError
- EYakkoMemoryManagerError
- EYakkoToolManagerError

Recomendacao:

- validar caminhos de modelo e dll antes de carregar
- evitar trocar dependencias durante geracao ativa
- manter teardown via Engine para ordem segura

## Ordem de vida recomendada em apps

1. Criar Engine
2. Ajustar Engine.Config
3. Configurar ModelPath e DllPath
4. Carregar modelo
5. Conversar via Chat ou Agente
6. Reiniciar sessao quando necessario
7. Descarregar modelo
8. Liberar Engine

## Dicas de performance

- Ajuste NCtx conforme a necessidade real de memoria
- Use Temperature 0 para comportamento mais deterministico
- Limite MaxTokens por caso de uso
- Observe TokensPerSecond e tempos de eval em OnFinished
- Use auto-resumo para evitar estouro de contexto em conversas longas

## FAQ rapido

### Preciso usar so InitializeAgent, Ask e FinalizeAgent?

Nao. Esse e o fluxo mais simples. O ganho real vem de:

- Engine.Config para tuning fino
- eventos para streaming e telemetria
- ToolManager para extensao de capacidades
- Chat e MemoryManager para conversa longa com controle

### Posso usar apenas Engine sem Agente?

Sim. Esse e o caminho recomendado para apps com regras proprias de orquestracao.

## Referencias internas

- [src/runtime/uYakkoEngineComponent.pas](../src/runtime/uYakkoEngineComponent.pas)
- [src/runtime/uYakkoInferenceConfigComponent.pas](../src/runtime/uYakkoInferenceConfigComponent.pas)
- [src/runtime/uYakkoGeradorComponent.pas](../src/runtime/uYakkoGeradorComponent.pas)
- [src/runtime/uYakkoChatComponent.pas](../src/runtime/uYakkoChatComponent.pas)
- [src/runtime/uYakkoMemoryManagerComponent.pas](../src/runtime/uYakkoMemoryManagerComponent.pas)
- [src/runtime/uYakkoToolManagerComponent.pas](../src/runtime/uYakkoToolManagerComponent.pas)
- [src/runtime/uYakkoAgenteComponent.pas](../src/runtime/uYakkoAgenteComponent.pas)
- [apps/YakkoStudio/uYakkoStudioMain.pas](../apps/YakkoStudio/uYakkoStudioMain.pas)
- [apps/YakkoStudio/uYakkoStudioRagModal.pas](../apps/YakkoStudio/uYakkoStudioRagModal.pas)
- [DIAGRAMA_CLASSES.md](DIAGRAMA_CLASSES.md)


