program InventoryLab.Tests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
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

procedure AssertTrue(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('Assert failed: ' + AMessage);
end;

procedure RunTests;
var
  LEngine: TInventoryLabEngine;
  LResult: TInventoryLabPipelineResult;
  LDataDir: string;
begin
  LEngine := TInventoryLabEngine.Create;
  try
    LDataDir := ExpandFileName('..\components');
    if not DirectoryExists(LDataDir) then
      LDataDir := ExpandFileName('..\..\components');
    LEngine.LoadFromDirectory(LDataDir);

    AssertTrue(LEngine.EntityMemory.EntityCount > 0, 'Entity count must be > 0');
    AssertTrue(LEngine.EntityMemory.AliasCount > 0, 'Alias count must be > 0');
    AssertTrue(LEngine.RelationshipGraph.EdgeCount >= 0, 'Relationship count must be valid');

    LResult := LEngine.Query('qual memoria funciona nessa placa?', 8);
    try
      AssertTrue(Length(LResult.ContextText) > 0, 'Context must not be empty');
    finally
      LResult.Free;
    end;
  finally
    LEngine.Free;
  end;
end;

begin
  try
    RunTests;
    Writeln('InventoryLab.Tests: OK');
  except
    on E: Exception do
    begin
      Writeln('InventoryLab.Tests: FAIL -> ', E.Message);
      Halt(1);
    end;
  end;
end.
