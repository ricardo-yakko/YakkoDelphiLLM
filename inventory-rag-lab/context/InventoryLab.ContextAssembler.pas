unit InventoryLab.ContextAssembler;

{ Deterministic context assembly focused on technical usefulness. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  InventoryLab.Models,
  InventoryLab.RelationshipGraph,
  Yakko.RAG.Types;

type
  TInventoryLabContextAssembler = class
  private
    FMaxContextChars: Integer;
    procedure AppendEntityBlock(ABuilder: TStringBuilder;
      AEntity: TYakkoInventoryEntity; AGraph: TInventoryLabRelationshipGraph);
  public
    constructor Create;

    function BuildContext(AResult: TInventoryLabPipelineResult;
      AGraph: TInventoryLabRelationshipGraph): string;

    property MaxContextChars: Integer read FMaxContextChars write FMaxContextChars;
  end;

implementation

constructor TInventoryLabContextAssembler.Create;
begin
  inherited Create;
  FMaxContextChars := 6000;
end;

procedure TInventoryLabContextAssembler.AppendEntityBlock(ABuilder: TStringBuilder;
  AEntity: TYakkoInventoryEntity; AGraph: TInventoryLabRelationshipGraph);
var
  LPair: TPair<string, string>;
  LEdges: TInventoryLabRelationEdgeList;
  LEdge: TInventoryLabRelationEdge;
  LSpecCount: Integer;
begin
  ABuilder.AppendLine(Format('entity.id=%s', [AEntity.Id]));
  ABuilder.AppendLine(Format('entity.name=%s', [AEntity.Name]));
  ABuilder.AppendLine(Format('entity.brand=%s', [AEntity.Brand]));
  ABuilder.AppendLine(Format('entity.category=%s', [AEntity.Category]));
  if Trim(AEntity.Description) <> '' then
    ABuilder.AppendLine(Format('entity.description=%s', [AEntity.Description]));

  LSpecCount := 0;
  for LPair in AEntity.Specifications do
  begin
    ABuilder.AppendLine(Format('spec.%s=%s', [LPair.Key, LPair.Value]));
    Inc(LSpecCount);
    if LSpecCount >= 8 then
      Break;
  end;

  LEdges := AGraph.GetOutgoing(AEntity.Id);
  try
    for LEdge in LEdges do
      ABuilder.AppendLine(Format('relation.%s=%s', [LEdge.RelationType.ToKey, LEdge.TargetEntityId]));
  finally
    LEdges.Free;
  end;

  ABuilder.AppendLine('');
end;

function TInventoryLabContextAssembler.BuildContext(
  AResult: TInventoryLabPipelineResult;
  AGraph: TInventoryLabRelationshipGraph): string;
var
  LBuilder: TStringBuilder;
  LEntity: TYakkoInventoryEntity;
  LDoc: TYakkoKnowledgeDocument;
begin
  if not Assigned(AResult) then
    raise EArgumentNilException.Create('AResult must be assigned.');
  if not Assigned(AGraph) then
    raise EArgumentNilException.Create('AGraph must be assigned.');

  LBuilder := TStringBuilder.Create;
  try
    LBuilder.AppendLine('[STRUCTURED-INVENTORY-CONTEXT]');

    LBuilder.AppendLine('[ENTITIES-PRIORITIZED]');
    for LEntity in AResult.RAGResult.RetrievedEntities do
    begin
      AppendEntityBlock(LBuilder, LEntity, AGraph);
      if LBuilder.Length >= FMaxContextChars then
        Break;
    end;

    if LBuilder.Length < FMaxContextChars then
    begin
      LBuilder.AppendLine('[DOCUMENT-SUPPORT]');
      for LDoc in AResult.RAGResult.RetrievedDocuments do
      begin
        LBuilder.AppendLine(Format('doc.id=%s', [LDoc.Id]));
        LBuilder.AppendLine(Format('doc.title=%s', [LDoc.Title]));
        if Trim(LDoc.Content) <> '' then
          LBuilder.AppendLine('doc.content=' + Copy(LDoc.Content, 1, 220));
        LBuilder.AppendLine('');

        if LBuilder.Length >= FMaxContextChars then
          Break;
      end;
    end;

    if LBuilder.Length > FMaxContextChars then
      Result := Trim(Copy(LBuilder.ToString, 1, FMaxContextChars)) + sLineBreak + '[context-truncated]'
    else
      Result := Trim(LBuilder.ToString);
  finally
    LBuilder.Free;
  end;
end;

end.
