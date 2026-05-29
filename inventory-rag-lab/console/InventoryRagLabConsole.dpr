program InventoryRagLabConsole;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.RAG.Types,
  InventoryLab.Models in '..\models\InventoryLab.Models.pas',
  InventoryLab.JsonLoader in '..\data\InventoryLab.JsonLoader.pas',
  InventoryLab.EntityNormalizer in '..\data\InventoryLab.EntityNormalizer.pas',
  InventoryLab.AliasResolver in '..\data\InventoryLab.AliasResolver.pas',
  InventoryLab.EntityMemory in '..\memory\InventoryLab.EntityMemory.pas',
  InventoryLab.DocumentChunker in '..\memory\InventoryLab.DocumentChunker.pas',
  InventoryLab.KnowledgeMemory in '..\memory\InventoryLab.KnowledgeMemory.pas',
  InventoryLab.RelationshipGraph in '..\relationships\InventoryLab.RelationshipGraph.pas',
  InventoryLab.RelationshipBuilder in '..\relationships\InventoryLab.RelationshipBuilder.pas',
  InventoryLab.ContextAssembler in '..\context\InventoryLab.ContextAssembler.pas',
  InventoryLab.RAGPipeline in '..\retrieval\InventoryLab.RAGPipeline.pas',
  InventoryLab.Engine in '..\retrieval\InventoryLab.Engine.pas';

procedure PrintDiagnostics(ADiagnostics: TInventoryLabStringMap);
var
  LPair: TPair<string, string>;
begin
  Writeln('[Diagnostics]');
  for LPair in ADiagnostics do
    Writeln('  ', LPair.Key, ' = ', LPair.Value);
  Writeln;
end;

procedure PrintResult(AResult: TInventoryLabPipelineResult);
var
  LEntity: TYakkoInventoryEntity;
  LDoc: TYakkoKnowledgeDocument;
  LPair: TPair<string, string>;
begin
  Writeln('[Structured Result]');
  Writeln('  Entities: ', AResult.RAGResult.RetrievedEntities.Count);
  Writeln('  Documents: ', AResult.RAGResult.RetrievedDocuments.Count);
  Writeln('  Chunks: ', AResult.RAGResult.RetrievedChunks.Count);
  Writeln;

  Writeln('[Entities]');
  for LEntity in AResult.RAGResult.RetrievedEntities do
  begin
    Writeln('  - ', LEntity.Id, ' | ', LEntity.Name, ' | ', LEntity.Category, ' | ', LEntity.Brand);
    if AResult.EntityScores.ContainsKey(LEntity.Id) then
      Writeln('    score=', AResult.EntityScores[LEntity.Id]);
  end;
  Writeln;

  Writeln('[Document Titles]');
  for LDoc in AResult.RAGResult.RetrievedDocuments do
    Writeln('  - ', LDoc.Id, ' | ', LDoc.Title);
  Writeln;

  Writeln('[Pipeline Diagnostics]');
  for LPair in AResult.Diagnostics do
    Writeln('  ', LPair.Key, ' = ', LPair.Value);
  Writeln;

  Writeln('[Assembled Context]');
  Writeln(AResult.ContextText);
end;

procedure Run;
var
  LEngine: TInventoryLabEngine;
  LDataDir: string;
  LQuery: string;
  LResult: TInventoryLabPipelineResult;
begin
  LEngine := TInventoryLabEngine.Create;
  try
    LDataDir := ExpandFileName('..\components');
    if not DirectoryExists(LDataDir) then
      LDataDir := ExpandFileName('..\..\components');

    Writeln('Loading data from: ', LDataDir);
    LEngine.LoadFromDirectory(LDataDir);
    PrintDiagnostics(LEngine.Diagnostics);

    if ParamCount > 0 then
      LQuery := ParamStr(1)
    else
      LQuery := 'esse Ryzen 5600 funciona nessa B450?';

    Writeln('Query: ', LQuery);
    Writeln;

    LResult := LEngine.Query(LQuery, 12);
    try
      PrintResult(LResult);
    finally
      LResult.Free;
    end;
  finally
    LEngine.Free;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln('[ERROR] ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
