unit InventoryLab.RelationshipGraph;

{ Explicit relationship graph for structured inventory entities. }

interface

uses
  System.SysUtils,
  InventoryLab.Models;

type
  TInventoryLabRelationshipGraph = class
  private
    FEdges: TInventoryLabRelationEdgeList;
    class function Normalize(const AValue: string): string; static;
    function ExistsEdge(const ASourceId, ATargetId: string;
      AType: TInventoryLabRelationType): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddEdge(AEdge: TInventoryLabRelationEdge);
    procedure AddRelation(const ASourceId, ATargetId: string;
      AType: TInventoryLabRelationType; const AEvidence: string);

    function GetOutgoing(const ASourceId: string): TInventoryLabRelationEdgeList;
    function GetByType(const ASourceId: string;
      AType: TInventoryLabRelationType): TInventoryLabRelationEdgeList;

    function EdgeCount: Integer;
    function ToDebugString: string;
  end;

implementation

constructor TInventoryLabRelationshipGraph.Create;
begin
  inherited Create;
  FEdges := TInventoryLabRelationEdgeList.Create(True);
end;

destructor TInventoryLabRelationshipGraph.Destroy;
begin
  FreeAndNil(FEdges);
  inherited;
end;

class function TInventoryLabRelationshipGraph.Normalize(const AValue: string): string;
begin
  Result := Trim(LowerCase(AValue));
end;

function TInventoryLabRelationshipGraph.ExistsEdge(const ASourceId,
  ATargetId: string; AType: TInventoryLabRelationType): Boolean;
var
  LEdge: TInventoryLabRelationEdge;
begin
  Result := False;
  for LEdge in FEdges do
  begin
    if (Normalize(LEdge.SourceEntityId) = Normalize(ASourceId))
      and (Normalize(LEdge.TargetEntityId) = Normalize(ATargetId))
      and (LEdge.RelationType = AType)
    then
      Exit(True);
  end;
end;

procedure TInventoryLabRelationshipGraph.AddEdge(AEdge: TInventoryLabRelationEdge);
begin
  if not Assigned(AEdge) then
    raise EArgumentNilException.Create('AEdge must be assigned.');

  if Trim(AEdge.SourceEntityId) = '' then
    raise EArgumentException.Create('AEdge.SourceEntityId must not be empty.');

  if Trim(AEdge.TargetEntityId) = '' then
    raise EArgumentException.Create('AEdge.TargetEntityId must not be empty.');

  if ExistsEdge(AEdge.SourceEntityId, AEdge.TargetEntityId, AEdge.RelationType) then
    Exit;

  { Ownership is transferred to graph once edge is added. }
  FEdges.Add(AEdge);
end;

procedure TInventoryLabRelationshipGraph.AddRelation(const ASourceId,
  ATargetId: string; AType: TInventoryLabRelationType; const AEvidence: string);
var
  LEdge: TInventoryLabRelationEdge;
begin
  LEdge := TInventoryLabRelationEdge.Create;
  try
    LEdge.SourceEntityId := ASourceId;
    LEdge.TargetEntityId := ATargetId;
    LEdge.RelationType := AType;
    LEdge.Evidence := AEvidence;
    AddEdge(LEdge);
    LEdge := nil;
  finally
    LEdge.Free;
  end;
end;

function TInventoryLabRelationshipGraph.GetOutgoing(
  const ASourceId: string): TInventoryLabRelationEdgeList;
var
  LEdge: TInventoryLabRelationEdge;
begin
  Result := TInventoryLabRelationEdgeList.Create(True);
  try
    for LEdge in FEdges do
    begin
      if Normalize(LEdge.SourceEntityId) = Normalize(ASourceId) then
        Result.Add(LEdge.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TInventoryLabRelationshipGraph.GetByType(const ASourceId: string;
  AType: TInventoryLabRelationType): TInventoryLabRelationEdgeList;
var
  LEdge: TInventoryLabRelationEdge;
begin
  Result := TInventoryLabRelationEdgeList.Create(True);
  try
    for LEdge in FEdges do
    begin
      if (Normalize(LEdge.SourceEntityId) = Normalize(ASourceId))
        and (LEdge.RelationType = AType)
      then
        Result.Add(LEdge.Clone);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TInventoryLabRelationshipGraph.EdgeCount: Integer;
begin
  Result := FEdges.Count;
end;

function TInventoryLabRelationshipGraph.ToDebugString: string;
begin
  Result := Format('TInventoryLabRelationshipGraph(Edges=%d)', [FEdges.Count]);
end;

end.
