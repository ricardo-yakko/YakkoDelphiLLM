unit InventoryLab.Models;

{ Shared domain models for the inventory RAG lab.

  This lab is intentionally deterministic and explicit:
  - no embeddings;
  - no vector DB;
  - no async orchestration;
  - no hidden heuristics. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Yakko.RAG.Types;

type
  TInventoryLabStringList = TList<string>;
  TInventoryLabStringMap = TDictionary<string, string>;

  TInventoryLabRelationType = (
    lrtCompatibleWith,
    lrtIncompatibleWith,
    lrtEquivalentTo,
    lrtUpgradeOf,
    lrtRequires,
    lrtSameSocket,
    lrtSameChipset,
    lrtSamePlatform
  );

  TInventoryLabRelationTypeHelper = record helper for TInventoryLabRelationType
  public
    function ToKey: string;
  end;

  TInventoryLabRawRecord = class
  private
    FSourceFile: string;
    FPartNumber: string;
    FDisplayName: string;
    FBrand: string;
    FCategory: string;
    FSubcategory: string;
    FDescription: string;
    FFlatScalars: TInventoryLabStringMap;
    FArrayLines: TInventoryLabStringList;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TInventoryLabRawRecord;
    function ToDebugString: string;

    property SourceFile: string read FSourceFile write FSourceFile;
    property PartNumber: string read FPartNumber write FPartNumber;
    property DisplayName: string read FDisplayName write FDisplayName;
    property Brand: string read FBrand write FBrand;
    property Category: string read FCategory write FCategory;
    property Subcategory: string read FSubcategory write FSubcategory;
    property Description: string read FDescription write FDescription;
    property FlatScalars: TInventoryLabStringMap read FFlatScalars;
    property ArrayLines: TInventoryLabStringList read FArrayLines;
  end;

  TInventoryLabRawRecordList = TObjectList<TInventoryLabRawRecord>;

  TInventoryLabRelationEdge = class
  private
    FSourceEntityId: string;
    FTargetEntityId: string;
    FRelationType: TInventoryLabRelationType;
    FEvidence: string;
    FMetadata: TInventoryLabStringMap;
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TInventoryLabRelationEdge;
    function ToDebugString: string;

    property SourceEntityId: string read FSourceEntityId write FSourceEntityId;
    property TargetEntityId: string read FTargetEntityId write FTargetEntityId;
    property RelationType: TInventoryLabRelationType read FRelationType write FRelationType;
    property Evidence: string read FEvidence write FEvidence;
    property Metadata: TInventoryLabStringMap read FMetadata;
  end;

  TInventoryLabRelationEdgeList = TObjectList<TInventoryLabRelationEdge>;

  TInventoryLabPipelineResult = class
  private
    FRAGResult: TYakkoRAGResult;
    FContextText: string;
    FDiagnostics: TInventoryLabStringMap;
    FEntityScores: TInventoryLabStringMap;
    procedure SetRAGResult(const Value: TYakkoRAGResult);
  public
    constructor Create;
    destructor Destroy; override;

    function Clone: TInventoryLabPipelineResult;
    function ToDebugString: string;

    property RAGResult: TYakkoRAGResult read FRAGResult write SetRAGResult;
    property ContextText: string read FContextText write FContextText;
    property Diagnostics: TInventoryLabStringMap read FDiagnostics;
    property EntityScores: TInventoryLabStringMap read FEntityScores;
  end;

procedure CloneStringMap(ASource, ADest: TInventoryLabStringMap);
procedure CloneStringList(ASource, ADest: TInventoryLabStringList);

implementation

procedure CloneStringMap(ASource, ADest: TInventoryLabStringMap);
var
  LPair: TPair<string, string>;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  ADest.Clear;
  if not Assigned(ASource) then
    Exit;

  for LPair in ASource do
    ADest.AddOrSetValue(LPair.Key, LPair.Value);
end;

procedure CloneStringList(ASource, ADest: TInventoryLabStringList);
var
  LItem: string;
begin
  if not Assigned(ADest) then
    raise EArgumentNilException.Create('ADest must be assigned.');

  ADest.Clear;
  if not Assigned(ASource) then
    Exit;

  for LItem in ASource do
    ADest.Add(LItem);
end;

{ TInventoryLabRelationTypeHelper }

function TInventoryLabRelationTypeHelper.ToKey: string;
begin
  case Self of
    lrtCompatibleWith:
      Result := 'compatible_with';
    lrtIncompatibleWith:
      Result := 'incompatible_with';
    lrtEquivalentTo:
      Result := 'equivalent_to';
    lrtUpgradeOf:
      Result := 'upgrade_of';
    lrtRequires:
      Result := 'requires';
    lrtSameSocket:
      Result := 'same_socket';
    lrtSameChipset:
      Result := 'same_chipset';
    lrtSamePlatform:
      Result := 'same_platform';
  else
    Result := 'compatible_with';
  end;
end;

{ TInventoryLabRawRecord }

constructor TInventoryLabRawRecord.Create;
begin
  inherited Create;
  FSourceFile := '';
  FPartNumber := '';
  FDisplayName := '';
  FBrand := '';
  FCategory := '';
  FSubcategory := '';
  FDescription := '';
  FFlatScalars := TInventoryLabStringMap.Create;
  FArrayLines := TInventoryLabStringList.Create;
end;

destructor TInventoryLabRawRecord.Destroy;
begin
  FreeAndNil(FArrayLines);
  FreeAndNil(FFlatScalars);
  inherited;
end;

function TInventoryLabRawRecord.Clone: TInventoryLabRawRecord;
begin
  Result := TInventoryLabRawRecord.Create;
  try
    Result.FSourceFile := FSourceFile;
    Result.FPartNumber := FPartNumber;
    Result.FDisplayName := FDisplayName;
    Result.FBrand := FBrand;
    Result.FCategory := FCategory;
    Result.FSubcategory := FSubcategory;
    Result.FDescription := FDescription;
    CloneStringMap(FFlatScalars, Result.FFlatScalars);
    CloneStringList(FArrayLines, Result.FArrayLines);
  except
    Result.Free;
    raise;
  end;
end;

function TInventoryLabRawRecord.ToDebugString: string;
begin
  Result := Format(
    'TInventoryLabRawRecord(PartNumber=%s, DisplayName=%s, Brand=%s, Category=%s, Scalars=%d, ArrayLines=%d, Source=%s)',
    [
      FPartNumber,
      FDisplayName,
      FBrand,
      FCategory,
      FFlatScalars.Count,
      FArrayLines.Count,
      FSourceFile
    ]
  );
end;

{ TInventoryLabRelationEdge }

constructor TInventoryLabRelationEdge.Create;
begin
  inherited Create;
  FSourceEntityId := '';
  FTargetEntityId := '';
  FRelationType := lrtCompatibleWith;
  FEvidence := '';
  FMetadata := TInventoryLabStringMap.Create;
end;

destructor TInventoryLabRelationEdge.Destroy;
begin
  FreeAndNil(FMetadata);
  inherited;
end;

function TInventoryLabRelationEdge.Clone: TInventoryLabRelationEdge;
begin
  Result := TInventoryLabRelationEdge.Create;
  try
    Result.FSourceEntityId := FSourceEntityId;
    Result.FTargetEntityId := FTargetEntityId;
    Result.FRelationType := FRelationType;
    Result.FEvidence := FEvidence;
    CloneStringMap(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TInventoryLabRelationEdge.ToDebugString: string;
begin
  Result := Format(
    'TInventoryLabRelationEdge(Source=%s, Target=%s, Type=%s, EvidenceLength=%d, Metadata=%d)',
    [
      FSourceEntityId,
      FTargetEntityId,
      FRelationType.ToKey,
      Length(FEvidence),
      FMetadata.Count
    ]
  );
end;

{ TInventoryLabPipelineResult }

constructor TInventoryLabPipelineResult.Create;
begin
  inherited Create;
  FRAGResult := TYakkoRAGResult.Create;
  FContextText := '';
  FDiagnostics := TInventoryLabStringMap.Create;
  FEntityScores := TInventoryLabStringMap.Create;
end;

destructor TInventoryLabPipelineResult.Destroy;
begin
  FreeAndNil(FEntityScores);
  FreeAndNil(FDiagnostics);
  FreeAndNil(FRAGResult);
  inherited;
end;

procedure TInventoryLabPipelineResult.SetRAGResult(const Value: TYakkoRAGResult);
begin
  FreeAndNil(FRAGResult);
  if Assigned(Value) then
    FRAGResult := Value.Clone
  else
    FRAGResult := TYakkoRAGResult.Create;
end;

function TInventoryLabPipelineResult.Clone: TInventoryLabPipelineResult;
begin
  Result := TInventoryLabPipelineResult.Create;
  try
    Result.SetRAGResult(FRAGResult);
    Result.FContextText := FContextText;
    CloneStringMap(FDiagnostics, Result.FDiagnostics);
    CloneStringMap(FEntityScores, Result.FEntityScores);
  except
    Result.Free;
    raise;
  end;
end;

function TInventoryLabPipelineResult.ToDebugString: string;
begin
  Result := Format(
    'TInventoryLabPipelineResult(RAG=%s, ContextLength=%d, Diagnostics=%d, EntityScores=%d)',
    [FRAGResult.ToDebugString, Length(FContextText), FDiagnostics.Count, FEntityScores.Count]
  );
end;

end.
