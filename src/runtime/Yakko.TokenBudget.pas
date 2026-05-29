unit Yakko.TokenBudget;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TYakkoTokenBudgetMetadata = TDictionary<string, string>;

  TYakkoTokenAllocation = class
  private
    FSystemTokens: Integer;
    FRAGTokens: Integer;
    FToolsTokens: Integer;
    FReasoningTokens: Integer;
    FResponseTokens: Integer;
  public
    constructor Create;
    procedure Clear;
    function Clone: TYakkoTokenAllocation;
    function TotalAllocated: Integer;
    function ToDebugString: string;

    property SystemTokens: Integer read FSystemTokens write FSystemTokens;
    property RAGTokens: Integer read FRAGTokens write FRAGTokens;
    property ToolsTokens: Integer read FToolsTokens write FToolsTokens;
    property ReasoningTokens: Integer read FReasoningTokens write FReasoningTokens;
    property ResponseTokens: Integer read FResponseTokens write FResponseTokens;
  end;

  TYakkoTokenBudget = class
  private
    FMaxContextTokens: Integer;
    FMaxResponseTokens: Integer;
    FAllocation: TYakkoTokenAllocation;
    FMetadata: TYakkoTokenBudgetMetadata;
    procedure SetAllocation(const Value: TYakkoTokenAllocation);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    function Clone: TYakkoTokenBudget;
    function ToDebugString: string;

    property MaxContextTokens: Integer read FMaxContextTokens write FMaxContextTokens;
    property MaxResponseTokens: Integer read FMaxResponseTokens write FMaxResponseTokens;
    property Allocation: TYakkoTokenAllocation read FAllocation write SetAllocation;
    property Metadata: TYakkoTokenBudgetMetadata read FMetadata;
  end;

  TYakkoTokenBudgetManager = class
  public
    function CreateDefaultBudget(AMaxContextTokens, AMaxResponseTokens: Integer): TYakkoTokenBudget;
    function ValidateBudget(ABudget: TYakkoTokenBudget; out AReason: string): Boolean;
  end;

implementation

procedure CloneStringDictionary(ASource, ADest: TYakkoTokenBudgetMetadata);
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

{ TYakkoTokenAllocation }

constructor TYakkoTokenAllocation.Create;
begin
  inherited Create;
  Clear;
end;

procedure TYakkoTokenAllocation.Clear;
begin
  FSystemTokens := 0;
  FRAGTokens := 0;
  FToolsTokens := 0;
  FReasoningTokens := 0;
  FResponseTokens := 0;
end;

function TYakkoTokenAllocation.Clone: TYakkoTokenAllocation;
begin
  Result := TYakkoTokenAllocation.Create;
  Result.FSystemTokens := FSystemTokens;
  Result.FRAGTokens := FRAGTokens;
  Result.FToolsTokens := FToolsTokens;
  Result.FReasoningTokens := FReasoningTokens;
  Result.FResponseTokens := FResponseTokens;
end;

function TYakkoTokenAllocation.TotalAllocated: Integer;
begin
  Result := FSystemTokens + FRAGTokens + FToolsTokens + FReasoningTokens + FResponseTokens;
end;

function TYakkoTokenAllocation.ToDebugString: string;
begin
  Result := Format(
    'TYakkoTokenAllocation(System=%d, RAG=%d, Tools=%d, Reasoning=%d, Response=%d, Total=%d)',
    [FSystemTokens, FRAGTokens, FToolsTokens, FReasoningTokens, FResponseTokens, TotalAllocated]
  );
end;

{ TYakkoTokenBudget }

constructor TYakkoTokenBudget.Create;
begin
  inherited Create;
  FMaxContextTokens := 4096;
  FMaxResponseTokens := 512;
  FAllocation := TYakkoTokenAllocation.Create;
  FMetadata := TYakkoTokenBudgetMetadata.Create;
end;

destructor TYakkoTokenBudget.Destroy;
begin
  FreeAndNil(FMetadata);
  FreeAndNil(FAllocation);
  inherited;
end;

procedure TYakkoTokenBudget.SetAllocation(const Value: TYakkoTokenAllocation);
begin
  FreeAndNil(FAllocation);
  if Assigned(Value) then
    FAllocation := Value.Clone
  else
    FAllocation := TYakkoTokenAllocation.Create;
end;

procedure TYakkoTokenBudget.Clear;
begin
  FMaxContextTokens := 4096;
  FMaxResponseTokens := 512;
  FAllocation.Clear;
  FMetadata.Clear;

  { TODO: add deterministic profile presets for model/provider combinations. }
end;

function TYakkoTokenBudget.Clone: TYakkoTokenBudget;
begin
  Result := TYakkoTokenBudget.Create;
  try
    Result.FMaxContextTokens := FMaxContextTokens;
    Result.FMaxResponseTokens := FMaxResponseTokens;
    Result.SetAllocation(FAllocation);
    CloneStringDictionary(FMetadata, Result.FMetadata);
  except
    Result.Free;
    raise;
  end;
end;

function TYakkoTokenBudget.ToDebugString: string;
begin
  Result := Format(
    'TYakkoTokenBudget(MaxContext=%d, MaxResponse=%d, Allocation=%s, Metadata=%d)',
    [FMaxContextTokens, FMaxResponseTokens, FAllocation.ToDebugString, FMetadata.Count]
  );
end;

{ TYakkoTokenBudgetManager }

function TYakkoTokenBudgetManager.CreateDefaultBudget(AMaxContextTokens,
  AMaxResponseTokens: Integer): TYakkoTokenBudget;
begin
  Result := TYakkoTokenBudget.Create;
  Result.MaxContextTokens := AMaxContextTokens;
  Result.MaxResponseTokens := AMaxResponseTokens;

  Result.Allocation.SystemTokens := AMaxContextTokens div 10;
  Result.Allocation.RAGTokens := AMaxContextTokens div 5;
  Result.Allocation.ToolsTokens := AMaxContextTokens div 10;
  Result.Allocation.ReasoningTokens := AMaxContextTokens div 5;
  Result.Allocation.ResponseTokens := AMaxResponseTokens;

  Result.Metadata.AddOrSetValue('mode', 'deterministic-default');
end;

function TYakkoTokenBudgetManager.ValidateBudget(ABudget: TYakkoTokenBudget;
  out AReason: string): Boolean;
begin
  AReason := '';

  if not Assigned(ABudget) then
  begin
    AReason := 'Token budget must be assigned.';
    Exit(False);
  end;

  if ABudget.MaxContextTokens <= 0 then
  begin
    AReason := 'MaxContextTokens must be positive.';
    Exit(False);
  end;

  if ABudget.Allocation.TotalAllocated > (ABudget.MaxContextTokens + ABudget.MaxResponseTokens) then
  begin
    AReason := 'Allocated tokens exceed configured limits.';
    Exit(False);
  end;

  Result := True;
end;

end.
